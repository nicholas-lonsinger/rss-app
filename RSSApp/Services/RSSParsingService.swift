import Foundation
import os

enum RSSParsingError: Error, Sendable {
    case parsingFailed(description: String)
    case noChannelFound
}

struct RSSParsingService: Sendable {

    private static let logger = Logger(category: "RSSParsingService")

    static let snippetMaxLength = 200

    func parse(_ data: Data) throws -> RSSFeed {
        Self.logger.debug("parse() called with \(data.count, privacy: .public) bytes")

        // Transcode to UTF-8 if the payload declares a different encoding or carries
        // a UTF-16/UTF-32 BOM. XMLParser only reliably handles UTF-8 and ASCII, so
        // CJK publishers (big5, euc-kr, gb2312) and UTF-16-emitting systems would
        // otherwise fail outright. See `EncodingSniffer` below.
        let (parseData, snifferOutcome) = EncodingSniffer.transcodeToUTF8IfNeeded(data)

        let delegate = RSSParserDelegate()
        let parser = XMLParser(data: parseData)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        parser.shouldReportNamespacePrefixes = false

        guard parser.parse() else {
            let errorDescription = parser.parserError?.localizedDescription ?? "Unknown parsing error"
            let encodingContext = snifferOutcome.diagnosticDescription
            Self.logger.error("XML parsing failed: \(errorDescription, privacy: .public) (encoding: \(encodingContext, privacy: .public))")
            throw RSSParsingError.parsingFailed(description: errorDescription)
        }

        guard delegate.foundChannel else {
            Self.logger.error("No <channel> (RSS) or <feed> (Atom) element found in feed")
            throw RSSParsingError.noChannelFound
        }

        let imageURL: URL?
        if let urlString = delegate.channelImageURL {
            imageURL = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines))
        } else {
            imageURL = nil
        }

        let feed = RSSFeed(
            title: HTMLUtilities.decodeHTMLEntities(
                delegate.channelTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            ),
            link: URL(string: delegate.channelLink.trimmingCharacters(in: .whitespacesAndNewlines)),
            feedDescription: HTMLUtilities.decodeHTMLEntities(
                delegate.channelDescription.trimmingCharacters(in: .whitespacesAndNewlines)
            ),
            articles: delegate.articles,
            lastUpdated: delegate.channelUpdated,
            imageURL: imageURL,
            format: delegate.feedFormat
        )

        // If the sniffer took a lossy fallback path and the parse produced zero
        // articles, escalate from .notice to .error so the log clearly indicates
        // a likely encoding failure rather than an empty feed from the publisher.
        // This prevents a silent "feed up-to-date" when the real cause is a
        // charset that couldn't be decoded.
        if snifferOutcome.isFallback && feed.articles.isEmpty {
            let escalationMessage = "Feed parsed with zero articles after encoding fallback '\(snifferOutcome.diagnosticDescription)' — encoding may have prevented content from being decoded: '\(feed.title)'"
            Self.logger.error("\(escalationMessage, privacy: .public)")
            // Dual-emit to the DiagnosticRecorder so tests can assert the escalation
            // path was hit directly, rather than using the upstream sniffer warning as
            // a proxy. See `DiagnosticRecorder` for rationale. Issue #301.
            DiagnosticRecorder.record(category: "RSSParsingService", level: .error, message: escalationMessage)
        } else {
            Self.logger.notice("Feed parsed: '\(feed.title, privacy: .public)' with \(feed.articles.count, privacy: .public) articles")
        }
        return feed
    }
}

// MARK: - Encoding Sniffer

/// Detects the character encoding of a raw feed payload and transcodes it to UTF-8
/// if needed so the downstream `XMLParser` (which only reliably handles UTF-8 and
/// ASCII) sees bytes it can consume. Pure logic, no I/O, no mutation — safe to call
/// concurrently.
///
/// Detection rules, in order of precedence:
///
/// 1. **Byte-order mark (BOM).** A BOM is authoritative per the XML spec and wins
///    over any `encoding="..."` attribute in the declaration. We check for
///    UTF-32 (BE/LE) before UTF-16 (BE/LE) because `FF FE 00 00` begins with the
///    UTF-16 LE BOM prefix — checking UTF-16 first would misclassify UTF-32 LE.
///
/// 2. **Byte pattern of the first four bytes.** UTF-16 and UTF-32 without a BOM
///    can still be detected unambiguously because a well-formed XML document must
///    start with `<` (0x3C), which has distinctive zero-padding in wider encodings.
///    See https://www.w3.org/TR/xml/#sec-guessing.
///
/// 3. **`<?xml ... encoding="..."?>` declaration.** For ASCII-compatible encodings
///    (UTF-8, ISO-8859-*, Big5, EUC-KR, GB2312, Shift-JIS, etc.) the XML prolog
///    itself is ASCII-safe, so we can scan the first `prologScanWindow` bytes as
///    ASCII and pull out the declared encoding name. The name is resolved via
///    `CFStringConvertIANACharSetNameToEncoding`, which handles every IANA charset
///    the system supports.
///
/// 4. **Default to UTF-8.** No BOM, no declaration → assume UTF-8 per XML spec.
///
/// When transcoding, the original `<?xml ... ?>` prolog is stripped from the UTF-8
/// output so XMLParser doesn't see a stale `encoding="big5"` attribute that
/// contradicts the actual bytes it's about to read. UTF-8 with no prolog is the
/// spec default, so stripping is safe.
///
/// `internal` rather than `fileprivate` so unit tests can pin down the individual
/// detection helpers directly. The type is stateless and has no invariants beyond
/// what each function documents locally, so widening access is benign.
enum EncodingSniffer {

    /// Shared between the `os.Logger` category and `DiagnosticRecorder` events so
    /// the test seam and the production log stream carry the same label.
    static let loggerCategory = "EncodingSniffer"

    private static let logger = Logger(category: loggerCategory)

    /// Maximum number of leading bytes scanned when looking for an XML declaration
    /// or stripping the prolog. 256 bytes comfortably fits any realistic
    /// `<?xml version="..." encoding="..." standalone="..."?>` plus leading
    /// whitespace, but is short enough that ASCII decoding is trivial.
    static let prologScanWindow = 256

    // MARK: - SnifferOutcome

    /// Describes which path `transcodeToUTF8IfNeeded` took so `parse()` can
    /// escalate its log level when a fallback was needed but produced no articles.
    enum SnifferOutcome: Sendable {
        /// Payload was already UTF-8 (or ASCII-compatible); returned as-is.
        case utf8Passthrough
        /// UTF-8 BOM (3 bytes) was stripped; bytes otherwise unchanged (lossless).
        case bomStrippedUTF8
        /// Non-UTF-8 BOM was stripped and the payload was fully transcoded to UTF-8.
        case bomStrippedAndTranscoded(String.Encoding)
        /// Payload was transcoded from the declared encoding to UTF-8.
        case transcoded(from: String.Encoding)
        /// The declared IANA encoding name was not recognised; prolog was stripped
        /// and the payload passed through as-is (best-effort UTF-8 fallback).
        case unknownEncodingFallback(String)
        /// `String(data:encoding:)` returned nil; payload passed through unchanged.
        case transcodeFailureFallback(String.Encoding)

        /// `true` for any outcome that represents a lossy or best-effort fallback
        /// — i.e. the bytes handed to XMLParser may not be correctly decoded.
        var isFallback: Bool {
            switch self {
            case .utf8Passthrough, .bomStrippedUTF8, .bomStrippedAndTranscoded, .transcoded: return false
            case .unknownEncodingFallback, .transcodeFailureFallback: return true
            }
        }

        /// A short human-readable label for use in log messages.
        var diagnosticDescription: String {
            switch self {
            case .utf8Passthrough:
                return "utf8Passthrough"
            case .bomStrippedUTF8:
                return "bomStrippedUTF8"
            case .bomStrippedAndTranscoded(let enc):
                return "bomStrippedAndTranscoded(\(enc))"
            case .transcoded(let enc):
                return "transcoded(from: \(enc))"
            case .unknownEncodingFallback(let name):
                return "unknownEncodingFallback(\(name))"
            case .transcodeFailureFallback(let enc):
                return "transcodeFailureFallback(\(enc))"
            }
        }
    }

    /// Inspects `data` and returns the same bytes if the payload is already UTF-8
    /// (the 95% case — no allocation), or a freshly-transcoded UTF-8 representation
    /// otherwise, paired with a `SnifferOutcome` describing which path was taken.
    /// Never throws: on any detection or transcoding failure the original bytes are
    /// returned unchanged, letting XMLParser produce its own error for the caller
    /// to surface.
    static func transcodeToUTF8IfNeeded(_ data: Data) -> (Data, SnifferOutcome) {
        guard !data.isEmpty else { return (data, .utf8Passthrough) }

        // 1. BOM check — authoritative.
        if let bom = detectBOM(data) {
            if bom.encoding == .utf8 {
                // UTF-8 BOM: strip it. XMLParser tolerates the BOM in practice but
                // stripping makes the downstream byte stream canonical.
                return (data.subdata(in: bom.bomLength..<data.count), .bomStrippedUTF8)
            }
            let stripped = data.subdata(in: bom.bomLength..<data.count)
            if let transcoded = transcode(SniffedPayload(data: stripped, encoding: bom.encoding)) {
                return (transcoded, .bomStrippedAndTranscoded(bom.encoding))
            }
            return (data, .transcodeFailureFallback(bom.encoding))
        }

        // 2. UTF-16 / UTF-32 without BOM — detect from first four bytes.
        if let encoding = detectWideEncodingWithoutBOM(data) {
            if let transcoded = transcode(SniffedPayload(data: data, encoding: encoding)) {
                return (transcoded, .transcoded(from: encoding))
            }
            return (data, .transcodeFailureFallback(encoding))
        }

        // 3. ASCII-compatible: scan the declaration.
        if let declaredName = scanEncodingDeclaration(data) {
            let normalized = declaredName.lowercased()
            if normalized == "utf-8" || normalized == "utf8" || normalized == "us-ascii" || normalized == "ascii" {
                // Already UTF-8-compatible; XMLParser handles this natively.
                return (data, .utf8Passthrough)
            }
            if let encoding = encodingFromIANAName(declaredName) {
                if let transcoded = transcode(SniffedPayload(data: data, encoding: encoding)) {
                    return (transcoded, .transcoded(from: encoding))
                }
                return (data, .transcodeFailureFallback(encoding))
            }
            // Unknown encoding name: XMLParser would reject the declaration outright,
            // wasting any ASCII-compatible content in the body. Strip the prolog at
            // the byte level (leaving the rest of the bytes unchanged) and let
            // XMLParser try the default (UTF-8). Best-effort recovery for feeds that
            // typo their encoding attribute but are actually ASCII/UTF-8 underneath.
            let unknownEncodingMessage = "Unknown encoding name '\(declaredName)' in XML declaration; stripping prolog and attempting UTF-8 fallback"
            logger.warning("\(unknownEncodingMessage, privacy: .public)")
            // Dual-emit to the DiagnosticRecorder so tests can assert the fallback
            // path was hit. See `DiagnosticRecorder` for rationale. Issue #275.
            DiagnosticRecorder.record(category: loggerCategory, level: .warning, message: unknownEncodingMessage)
            return (stripProlog(data) ?? data, .unknownEncodingFallback(declaredName))
        }

        // 4. No BOM, no declaration → UTF-8 default.
        return (data, .utf8Passthrough)
    }

    // MARK: - BOMMatch

    /// A matched byte-order mark: the identified encoding and the number of BOM
    /// bytes to skip before the payload content begins.
    struct BOMMatch {
        let encoding: String.Encoding
        var bomLength: Int {
            switch encoding {
            case .utf32BigEndian, .utf32LittleEndian: return 4
            case .utf8:                               return 3
            default:                                  return 2  // UTF-16 BE/LE
            }
        }
    }

    // MARK: - SniffedPayload

    /// A raw payload whose encoding has already been identified. Bundles the bytes
    /// and their detected encoding together so `transcode` always receives a named,
    /// coherent pair rather than two loose arguments.
    private struct SniffedPayload {
        let data: Data
        let encoding: String.Encoding
    }

    // MARK: - BOM detection

    /// Returns the detected encoding and the BOM byte length, or nil if no BOM is
    /// present. Order matters: UTF-32 LE (`FF FE 00 00`) must be checked before
    /// UTF-16 LE (`FF FE`) or it would be misclassified.
    static func detectBOM(_ data: Data) -> BOMMatch? {
        if data.count >= 4 {
            // UTF-32 BE
            if data[0] == 0x00 && data[1] == 0x00 && data[2] == 0xFE && data[3] == 0xFF {
                return BOMMatch(encoding: .utf32BigEndian)
            }
            // UTF-32 LE
            if data[0] == 0xFF && data[1] == 0xFE && data[2] == 0x00 && data[3] == 0x00 {
                return BOMMatch(encoding: .utf32LittleEndian)
            }
        }
        if data.count >= 3 {
            // UTF-8
            if data[0] == 0xEF && data[1] == 0xBB && data[2] == 0xBF {
                return BOMMatch(encoding: .utf8)
            }
        }
        if data.count >= 2 {
            // UTF-16 BE
            if data[0] == 0xFE && data[1] == 0xFF {
                return BOMMatch(encoding: .utf16BigEndian)
            }
            // UTF-16 LE
            if data[0] == 0xFF && data[1] == 0xFE {
                return BOMMatch(encoding: .utf16LittleEndian)
            }
        }
        return nil
    }

    // MARK: - BOM-less wide detection

    /// Detects UTF-16 / UTF-32 without a BOM by pattern-matching the first four
    /// bytes against the expected encoding of the leading `<` character (0x3C).
    static func detectWideEncodingWithoutBOM(_ data: Data) -> String.Encoding? {
        guard data.count >= 4 else { return nil }
        let b0 = data[0], b1 = data[1], b2 = data[2], b3 = data[3]

        // UTF-32 BE: 00 00 00 3C
        if b0 == 0x00 && b1 == 0x00 && b2 == 0x00 && b3 == 0x3C {
            return .utf32BigEndian
        }
        // UTF-32 LE: 3C 00 00 00
        if b0 == 0x3C && b1 == 0x00 && b2 == 0x00 && b3 == 0x00 {
            return .utf32LittleEndian
        }
        // UTF-16 BE: 00 3C 00 ?? — second byte is 0x3C, first and third are 0x00.
        if b0 == 0x00 && b1 == 0x3C && b2 == 0x00 {
            return .utf16BigEndian
        }
        // UTF-16 LE: 3C 00 ?? 00 — first byte is 0x3C, second and fourth are 0x00.
        if b0 == 0x3C && b1 == 0x00 && b3 == 0x00 {
            return .utf16LittleEndian
        }
        return nil
    }

    // MARK: - XML declaration scanner

    /// Scans the first `prologScanWindow` bytes of `data` as ASCII looking for
    /// `<?xml ... encoding="name" ... ?>`. Returns the encoding name unquoted, or
    /// nil if no declaration is present or the encoding attribute is missing.
    /// Only runs on ASCII-compatible payloads: the caller is expected to have
    /// ruled out UTF-16/UTF-32 already.
    static func scanEncodingDeclaration(_ data: Data) -> String? {
        let sniffLength = min(data.count, prologScanWindow)
        guard sniffLength >= 6 else { return nil }
        let prefix = data.prefix(sniffLength)

        // Decode as ASCII (lossy — any non-ASCII byte becomes nil and short-circuits).
        // We do not need to decode the full document here, just the prolog.
        guard let prolog = String(data: prefix, encoding: .ascii),
              let declStart = prolog.range(of: "<?xml"),
              let declEnd = prolog.range(of: "?>", range: declStart.upperBound..<prolog.endIndex) else {
            return nil
        }

        let declaration = prolog[declStart.upperBound..<declEnd.lowerBound]
        // Find `encoding=` (case-insensitive per XML spec).
        guard let encRange = declaration.range(of: "encoding", options: .caseInsensitive) else {
            return nil
        }
        var cursor = encRange.upperBound
        // Skip whitespace and `=`.
        while cursor < declaration.endIndex, declaration[cursor].isWhitespace {
            cursor = declaration.index(after: cursor)
        }
        guard cursor < declaration.endIndex, declaration[cursor] == "=" else { return nil }
        cursor = declaration.index(after: cursor)
        while cursor < declaration.endIndex, declaration[cursor].isWhitespace {
            cursor = declaration.index(after: cursor)
        }
        guard cursor < declaration.endIndex else { return nil }
        let quote = declaration[cursor]
        guard quote == "\"" || quote == "'" else { return nil }
        cursor = declaration.index(after: cursor)
        guard let closingQuote = declaration[cursor...].firstIndex(of: quote) else { return nil }
        let name = String(declaration[cursor..<closingQuote])
        return name.isEmpty ? nil : name
    }

    // MARK: - IANA name lookup

    /// Maps an IANA charset name (from an XML declaration) to a `String.Encoding`.
    /// Uses CoreFoundation's registry, which covers every charset the system
    /// understands. Returns nil for unrecognized names.
    static func encodingFromIANAName(_ name: String) -> String.Encoding? {
        let cfEncoding = CFStringConvertIANACharSetNameToEncoding(name as CFString)
        guard cfEncoding != kCFStringEncodingInvalidId else { return nil }
        let nsEncoding = CFStringConvertEncodingToNSStringEncoding(cfEncoding)
        return String.Encoding(rawValue: nsEncoding)
    }

    // MARK: - Transcoding

    /// Decodes the payload bytes using the identified encoding and re-encodes as
    /// UTF-8, stripping any `<?xml ... ?>` prolog so the downstream parser doesn't
    /// see a stale `encoding="..."` attribute that contradicts the actual bytes.
    /// Returns nil if decoding fails.
    private static func transcode(_ payload: SniffedPayload) -> Data? {
        let data = payload.data
        let encoding = payload.encoding
        guard let decoded = String(data: data, encoding: encoding) else {
            let decodeFailureMessage = "Failed to decode feed payload as \(String(describing: encoding)); passing through unchanged"
            logger.warning("\(decodeFailureMessage, privacy: .public)")
            // Dual-emit to the DiagnosticRecorder so tests can assert the fallback
            // path was hit. See `DiagnosticRecorder` for rationale. Issue #275.
            DiagnosticRecorder.record(category: loggerCategory, level: .warning, message: decodeFailureMessage)
            return nil
        }
        let stripped = stripXMLDeclaration(decoded)
        guard let utf8 = stripped.data(using: .utf8) else {
            let message = "UTF-8 re-encoding of transcoded string failed unexpectedly (encoding=\(String(describing: encoding)), chars=\(stripped.count))"
            logger.fault("\(message, privacy: .public)")
            // Dual-emit to the DiagnosticRecorder so this fault is observable
            // in Console.app via the recording sink if it ever fires in production.
            // No test covers this branch: data(using: .utf8) cannot return nil on a
            // valid Swift String in practice. See `DiagnosticRecorder` for rationale.
            // Issue #275.
            DiagnosticRecorder.record(category: loggerCategory, level: .fault, message: message)
            assertionFailure(message)
            return nil
        }
        let transcodeSuccessMessage = "Transcoded \(data.count) bytes from \(String(describing: encoding)) to \(utf8.count) bytes UTF-8"
        logger.notice("\(transcodeSuccessMessage, privacy: .public)")
        // Dual-emit to the DiagnosticRecorder so tests can assert the success
        // path was hit without reparsing the returned Data. Issue #275.
        DiagnosticRecorder.record(category: loggerCategory, level: .notice, message: transcodeSuccessMessage)
        return utf8
    }

    /// Byte-level strip of the leading `<?xml ... ?>` prolog. Scans for the
    /// ASCII sequence and removes it without decoding the rest of the payload,
    /// so multi-byte UTF-8 content in the body is preserved byte-for-byte.
    /// Returns nil if no prolog is present (caller can fall through).
    static func stripProlog(_ data: Data) -> Data? {
        // Scan at most `prologScanWindow` bytes — the prolog, if present, must be first.
        let scanLength = min(data.count, prologScanWindow)
        guard scanLength >= 7 else { return nil }  // "<?xml?>" is 7 bytes minimum

        // Skip any leading whitespace bytes (0x20, 0x09, 0x0A, 0x0D).
        var start = 0
        while start < scanLength {
            let b = data[start]
            if b == 0x20 || b == 0x09 || b == 0x0A || b == 0x0D {
                start += 1
            } else {
                break
            }
        }
        // Check `<?xml` (lowercase — XML spec is strict here).
        let xmlPrefix: [UInt8] = [0x3C, 0x3F, 0x78, 0x6D, 0x6C]  // <?xml
        guard start + 5 <= data.count else { return nil }
        for (i, expected) in xmlPrefix.enumerated() where data[start + i] != expected {
            return nil
        }
        // Find the closing `?>`.
        var cursor = start + 5
        while cursor + 1 < data.count && cursor < scanLength {
            if data[cursor] == 0x3F && data[cursor + 1] == 0x3E {
                return data.subdata(in: (cursor + 2)..<data.count)
            }
            cursor += 1
        }
        return nil
    }

    /// Removes the leading `<?xml ... ?>` prolog from a string if present.
    /// The spec treats a missing prolog as UTF-8 by default, which is what we
    /// want after transcoding.
    static func stripXMLDeclaration(_ text: String) -> String {
        // Trim leading whitespace and any residual BOM character that might have
        // survived decoding (the zero-width no-break space U+FEFF).
        var cursor = text.startIndex
        while cursor < text.endIndex, text[cursor].isWhitespace || text[cursor] == "\u{FEFF}" {
            cursor = text.index(after: cursor)
        }
        let trimmed = text[cursor...]
        guard trimmed.hasPrefix("<?xml"),
              let declEnd = trimmed.range(of: "?>") else {
            return String(trimmed)
        }
        return String(trimmed[declEnd.upperBound...])
    }
}

// MARK: - XMLParser Delegate

// RATIONALE: @unchecked Sendable is safe because the delegate is created and consumed
// synchronously within a single parse() call and never escapes that scope.
private final class RSSParserDelegate: NSObject, XMLParserDelegate, @unchecked Sendable {

    private static let logger = Logger(category: "RSSParserDelegate")

    var foundChannel = false
    /// Set when the root container element is first encountered. `<channel>` → `.rss`,
    /// `<feed>` → `.atom`. Defaults to `.rss` because `parse()` throws
    /// `noChannelFound` before consulting this field if neither element was
    /// seen — the default is unreachable in current control flow and exists
    /// only to keep the field non-optional for callers.
    var feedFormat: FeedFormat = .rss
    var channelTitle = ""
    var channelLink = ""
    var channelDescription = ""
    var channelUpdated: Date?
    var channelImageURL: String?
    var articles: [Article] = []

    private var isInsideItem = false
    private var isInsideChannelImage = false
    private var currentElement = ""
    private var textBuffer = ""

    // Per-item accumulators
    private var itemTitle = ""
    private var itemLink = ""
    private var itemDescription = ""
    private var itemGuid = ""
    private var itemPubDate = ""
    private var itemUpdatedDate = ""
    private var itemThumbnailURL: String?
    private var itemEnclosureURL: String?
    private var itemAuthor = ""
    private var itemCategories: [String] = []

    // Atom author nesting: <author><name>Text</name></author>
    private var isInsideAuthor = false

    // Tracks whether the current <category> had a term attribute (Atom style)
    // to prevent double-appending when text content also exists.
    private var categoryHandledByAttribute = false

    // XHTML content reconstruction: when <content type="xhtml"> or <summary type="xhtml">
    // is encountered, inner XML elements must be serialized back to HTML rather than parsed
    // as feed structure. Grouped into a struct so enter/exit are single-assignment operations.
    private var xhtmlState: XHTMLState?

    private struct XHTMLState {
        enum Target {
            case content
            case summary

            var closingElementName: String {
                switch self {
                case .content: "content"
                case .summary: "summary"
                }
            }
        }

        var target: Target
        var depth = 0
        var buffer = ""
    }

    private static let htmlVoidElements: Set<String> = [
        "area", "base", "br", "col", "embed", "hr", "img",
        "input", "link", "meta", "param", "source", "track", "wbr",
    ]

    // MARK: - XMLParserDelegate

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let name = qualifiedName ?? elementName

        // XHTML reconstruction: serialize inner elements as HTML
        if xhtmlState != nil {
            xhtmlState!.depth += 1
            // RATIONALE: Atom spec requires <content type="xhtml"> to contain exactly one
            // wrapper <div xmlns="http://www.w3.org/1999/xhtml">. We skip it at depth 1
            // so only its inner content is captured.
            if xhtmlState!.depth > 1 {
                xhtmlState!.buffer += "<\(elementName)"
                for (key, value) in attributeDict where key != "xmlns" {
                    xhtmlState!.buffer += " \(key)=\"\(HTMLUtilities.escapeAttribute(value))\""
                }
                if Self.htmlVoidElements.contains(elementName.lowercased()) {
                    xhtmlState!.buffer += " />"
                } else {
                    xhtmlState!.buffer += ">"
                }
            }
            return
        }

        currentElement = name
        textBuffer = ""

        switch name {
        case "channel", "feed":
            // Capture the root container format on first occurrence. `<channel>`
            // belongs to RSS 2.0 / RSS 0.9x; `<feed>` is the Atom root element.
            // `!foundChannel` guards against a later nested occurrence (rare but
            // possible in deeply nested or malformed payloads) overwriting the
            // outer format classification.
            if !foundChannel {
                foundChannel = true
                feedFormat = (name == "feed") ? .atom : .rss
            }

        case "image":
            if !isInsideItem {
                isInsideChannelImage = true
            }

        case "item", "entry":
            isInsideItem = true
            itemTitle = ""
            itemLink = ""
            itemDescription = ""
            itemGuid = ""
            itemPubDate = ""
            itemUpdatedDate = ""
            itemThumbnailURL = nil
            itemEnclosureURL = nil
            itemAuthor = ""
            itemCategories = []
            isInsideAuthor = false
            categoryHandledByAttribute = false

        case "author":
            if isInsideItem {
                isInsideAuthor = true
            }

        case "link":
            // RATIONALE: Atom uses self-closing <link rel="alternate" href="URL"/> while
            // RSS uses <link>URL</link> text content. Extracting href here handles Atom;
            // RSS <link> elements carry no href attribute, so the guard below is a no-op
            // for RSS feeds — assignment happens in didEndElement via text content instead.
            let rel = attributeDict["rel"] ?? "alternate"
            if rel == "alternate", let href = attributeDict["href"] {
                if isInsideItem {
                    if itemLink.isEmpty { itemLink = href }
                } else {
                    if channelLink.isEmpty { channelLink = href }
                }
            }
            // Atom enclosure links: <link rel="enclosure" type="image/..." href="URL"/>
            if rel == "enclosure", isInsideItem {
                let type = attributeDict["type"] ?? ""
                if type.hasPrefix("image/"), let href = attributeDict["href"] {
                    if itemEnclosureURL == nil {
                        itemEnclosureURL = href
                    }
                }
            }

        case "media:thumbnail":
            if isInsideItem, itemThumbnailURL == nil {
                itemThumbnailURL = attributeDict["url"]
            }

        case "media:content":
            if isInsideItem, itemThumbnailURL == nil {
                let medium = attributeDict["medium"] ?? ""
                let type = attributeDict["type"] ?? ""
                if medium == "image" || type.hasPrefix("image/") {
                    itemThumbnailURL = attributeDict["url"]
                }
            }

        case "enclosure":
            if isInsideItem {
                let type = attributeDict["type"] ?? ""
                if type.hasPrefix("image/") {
                    itemEnclosureURL = attributeDict["url"]
                }
            }

        case "category":
            // Atom uses <category term="value"/>, RSS uses <category>text</category>
            if isInsideItem, let term = attributeDict["term"] {
                let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    itemCategories.append(trimmed)
                    categoryHandledByAttribute = true
                }
            } else {
                categoryHandledByAttribute = false
            }

        case "content":
            if isInsideItem, attributeDict["type"] == "xhtml" {
                xhtmlState = XHTMLState(target: .content)
            }

        case "summary":
            if isInsideItem, attributeDict["type"] == "xhtml" {
                xhtmlState = XHTMLState(target: .summary)
            }

        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if xhtmlState != nil {
            // XMLParser resolves entities before delivering text, so we must re-escape
            // to produce valid HTML (e.g., "&amp;" → "&" from parser → "&amp;" in output).
            xhtmlState!.buffer += HTMLUtilities.escapeHTML(string)
        } else {
            textBuffer += string
        }
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if let string = String(data: CDATABlock, encoding: .utf8) {
            if xhtmlState != nil {
                xhtmlState!.buffer += HTMLUtilities.escapeHTML(string)
            } else {
                textBuffer += string
            }
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?
    ) {
        let name = qualifiedName ?? elementName

        // XHTML reconstruction: close inner elements
        if let state = xhtmlState {
            if name == state.target.closingElementName && state.depth == 0 {
                // End of the XHTML container — flush the reconstructed HTML
                let html = state.buffer.trimmingCharacters(in: .whitespacesAndNewlines)
                switch state.target {
                case .content:
                    if !html.isEmpty {
                        itemDescription = html
                    } else {
                        Self.logger.debug("XHTML content reconstruction produced empty result for '\(self.itemTitle, privacy: .public)'")
                    }
                case .summary:
                    if itemDescription.isEmpty {
                        if !html.isEmpty {
                            itemDescription = html
                        } else {
                            Self.logger.debug("XHTML summary reconstruction produced empty result for '\(self.itemTitle, privacy: .public)'")
                        }
                    }
                }
                xhtmlState = nil
                currentElement = ""
                textBuffer = ""
                return
            }
            let newDepth = state.depth - 1
            if newDepth < 0 {
                Self.logger.warning("XHTML depth underflow at </\(elementName, privacy: .public)> in '\(self.itemTitle, privacy: .public)'")
            }
            xhtmlState!.depth = max(0, newDepth)
            // Close tags for elements deeper than the wrapper <div>, skipping void elements
            if xhtmlState!.depth > 0, !Self.htmlVoidElements.contains(elementName.lowercased()) {
                xhtmlState!.buffer += "</\(elementName)>"
            }
            return
        }

        if isInsideItem {
            switch name {
            case "title":
                if !isInsideAuthor { itemTitle = textBuffer }
            case "link":
                // Only set from text content (RSS style) if non-empty.
                // Also guards against overwriting the href already set in didStartElement
                // for Atom feeds, since Atom <link> elements produce no text content.
                if itemLink.isEmpty, !textBuffer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    itemLink = textBuffer
                }
            case "description":
                itemDescription = textBuffer
            case "content:encoded":
                // Prefer content:encoded over description if available
                if !textBuffer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    itemDescription = textBuffer
                }
            case "summary":
                // Atom summary; used as description fallback if no RSS <description> was found
                if itemDescription.isEmpty {
                    itemDescription = textBuffer
                }
            case "content":
                // Atom content; treated like RSS content:encoded — overwrites description/summary
                // if non-empty. (XHTML type is handled separately above.)
                if !textBuffer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    itemDescription = textBuffer
                }
            case "guid":
                itemGuid = textBuffer
            case "id":
                // Atom entry ID; used as guid fallback. RSS <guid> takes priority if present.
                if itemGuid.isEmpty {
                    itemGuid = textBuffer
                }
            case "pubDate", "published":
                // RSS <pubDate> and Atom <published> are the format-native publication
                // timestamps. Both set itemPubDate unconditionally — this is what enforces
                // the precedence rule that Dublin Core fallbacks (dc:date / dcterms:created
                // below) cannot clobber a real publication date, regardless of element
                // order in the source XML.
                itemPubDate = textBuffer
            // RATIONALE: namespace processing is disabled on the XMLParser
            // (`shouldProcessNamespaces = false` at parse(_:)), so namespaced elements
            // arrive here as their literal qualified names. The cases below match the
            // standard prefixes — `dc:`, `dcterms:`, and `atom:` — which covers the
            // overwhelming majority of feeds. A feed declaring its own custom prefix for
            // the Dublin Core or Atom namespace (e.g., `xmlns:foo="http://purl.org/dc/elements/1.1/"`
            // and using `foo:modified`) will not be matched. The principled fix would be
            // enabling namespace processing and reworking every existing namespaced case
            // in both `didStartElement` (e.g., `media:thumbnail`/`media:content` attribute
            // extraction) and `didEndElement` (`content:encoded`); that is out of scope
            // for issue #74. The four cases below — Atom native + the namespaced aliases —
            // share identical bodies and are folded into a single switch arm.
            case "updated", "dc:modified", "dcterms:modified", "atom:updated":
                // First-class update signal. Captured into itemUpdatedDate unconditionally,
                // and *also* used as a fallback for the publication date when no
                // <pubDate>/<published> was present (preserves the historical Atom
                // <updated>-as-published-fallback semantics).
                itemUpdatedDate = textBuffer
                if itemPubDate.isEmpty {
                    itemPubDate = textBuffer
                }
            case "dc:date", "dcterms:created":
                // Dublin Core publication date — a publication signal, NOT an update
                // signal, so it deliberately does not populate itemUpdatedDate. The
                // `if itemPubDate.isEmpty` guard is what enforces precedence: if a native
                // <pubDate> or <published> appears anywhere in the same item, those arms
                // overwrite itemPubDate unconditionally and the value set here is replaced.
                // The precedence therefore holds regardless of element order in the XML.
                if itemPubDate.isEmpty {
                    itemPubDate = textBuffer
                }
            case "author":
                // RSS <author> stores plain text; Atom <author> is a container (handled via name)
                isInsideAuthor = false
                let text = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
                if itemAuthor.isEmpty, !text.isEmpty {
                    itemAuthor = text
                }
            case "name":
                // Atom <author><name>Text</name></author>
                if isInsideAuthor {
                    let text = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !text.isEmpty { itemAuthor = text }
                }
            case "category":
                // RSS <category>text</category> — skip if already handled via term attribute
                if !categoryHandledByAttribute {
                    let text = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !text.isEmpty {
                        itemCategories.append(text)
                    }
                }
                categoryHandledByAttribute = false
            case "item", "entry":
                articles.append(buildArticle())
                isInsideItem = false
            default:
                break
            }
        } else {
            switch name {
            case "title":
                if channelTitle.isEmpty { channelTitle = textBuffer }
            case "link":
                if channelLink.isEmpty, !textBuffer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    channelLink = textBuffer
                }
            case "description":
                if channelDescription.isEmpty { channelDescription = textBuffer }
            case "subtitle":
                // Atom feed subtitle; used as channel description when no RSS <description> was found
                if channelDescription.isEmpty { channelDescription = textBuffer }
            case "updated", "lastBuildDate":
                if channelUpdated == nil {
                    channelUpdated = Self.parseDate(textBuffer, field: "channel-updated")
                }
            case "url":
                // RSS <image><url>text</url></image>
                if isInsideChannelImage {
                    let trimmed = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { channelImageURL = trimmed }
                }
            case "image":
                isInsideChannelImage = false
            case "logo":
                // Atom <logo> — highest priority feed image for Atom feeds
                let trimmed = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { channelImageURL = trimmed }
            case "icon":
                // Atom <icon> — fallback when no <logo> is present
                if channelImageURL == nil {
                    let trimmed = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { channelImageURL = trimmed }
                }
            default:
                break
            }
        }

        currentElement = ""
        textBuffer = ""
    }

    // MARK: - Article Construction

    private func buildArticle() -> Article {
        let title = HTMLUtilities.decodeHTMLEntities(
            itemTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        let linkString = itemLink.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawDescription = itemDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let guid = itemGuid.trimmingCharacters(in: .whitespacesAndNewlines)

        // ID: guid → link → hash of title+description
        let id: String
        if !guid.isEmpty {
            id = guid
        } else if !linkString.isEmpty {
            id = linkString
        } else {
            id = String(abs("\(title)\(rawDescription)".hashValue))
        }

        // Snippet: strip HTML and truncate
        let plainText = HTMLUtilities.stripHTML(rawDescription)
        let snippet: String
        if plainText.count > RSSParsingService.snippetMaxLength {
            let endIndex = plainText.index(plainText.startIndex, offsetBy: RSSParsingService.snippetMaxLength)
            snippet = String(plainText[..<endIndex]) + "…"
        } else {
            snippet = plainText
        }

        // Thumbnail: media:thumbnail → media:content → enclosure → first img in description
        let thumbnailURL: URL?
        if let urlString = itemThumbnailURL {
            thumbnailURL = URL(string: urlString)
        } else if let urlString = itemEnclosureURL {
            thumbnailURL = URL(string: urlString)
        } else {
            thumbnailURL = HTMLUtilities.extractFirstImageURL(from: rawDescription)
        }

        // Author: decode entities, trimmed, nil if empty
        let authorTrimmed = HTMLUtilities.decodeHTMLEntities(
            itemAuthor.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        return Article(
            id: id,
            title: title.isEmpty ? "Untitled" : title,
            link: URL(string: linkString),
            articleDescription: rawDescription,
            snippet: snippet,
            publishedDate: Self.parseDate(itemPubDate, field: "pubDate"),
            updatedDate: Self.parseDate(itemUpdatedDate, field: "updated"),
            thumbnailURL: thumbnailURL,
            author: authorTrimmed.isEmpty ? nil : authorTrimmed,
            categories: itemCategories
        )
    }

    // MARK: - Date Parsing

    /// Parses a feed date string into an absolute `Date`, prioritizing formats with
    /// explicit timezone information to avoid ambiguity.
    ///
    /// Parsing strategy, in order:
    /// 1. `ISO8601DateFormatter` with `.withInternetDateTime` and/or `.withFractionalSeconds`
    ///    — covers RFC 3339 / Atom formats. This is the correct format for Atom feeds and
    ///    the most common format for modern RSS, so it's the common-case fast path.
    /// 2. A list of explicit `DateFormatter` patterns covering RFC 822 / RFC 2822 variants
    ///    and their common real-world deviations (named zones, missing seconds, single-digit
    ///    day, space separator instead of `T`, etc.) — all of which include an explicit zone.
    /// 3. Zone-less fallback: the same patterns without a trailing zone specifier, interpreted
    ///    as UTC with a `.warning` log. This produces *some* valid `Date` for feeds that emit
    ///    ambiguous timestamps rather than silently discarding them. The alternative —
    ///    returning `nil` — hides the feed's age entirely in the UI.
    ///
    /// All successful parses are sanity-checked against a plausible date range. Inputs that
    /// parse to an impossible absolute moment (e.g., `DateFormatter`'s `yyyy` "year of era"
    /// accepting `"26"` as year 26 AD) are rejected to prevent corrupt timestamps from
    /// poisoning cross-feed sorting and retention. See GitHub issue #208 for the motivating
    /// bug report on incorrect article timestamps.
    private static func parseDate(_ dateString: String, field: String = "feed-date") -> Date? {
        let trimmed = dateString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // 1. ISO 8601 / RFC 3339 — most modern feeds use this. Handles `...Z`,
        //    `...+0000`, `...-07:00`, and fractional-second variants.
        if let date = ISO8601Formatters.standard.date(from: trimmed) {
            return sanityChecked(date, input: trimmed, source: "ISO8601", field: field)
        }
        if let date = ISO8601Formatters.fractional.date(from: trimmed) {
            return sanityChecked(date, input: trimmed, source: "ISO8601 fractional", field: field)
        }

        // 2. Explicit-zone DateFormatter patterns (RFC 822 / RFC 2822 and common variants).
        //    Every format here must end in a zone specifier; zone-less formats are handled
        //    in the fallback block below with clearly documented UTC assumption and logging.
        //    Each formatter is pre-built once in `HoistedDateFormatters` with its
        //    `dateFormat` fixed at initialization — we never mutate shared state here, so
        //    concurrent calls from multiple feed refreshes are safe without locking.
        if let date = parseUsingZonedFormats(trimmed, field: field) {
            return date
        }

        // 2b. Non-US named-zone preprocessing. `DateFormatter`'s `zzz` specifier with
        //     `en_US_POSIX` only recognizes a small set of historical North American zone
        //     abbreviations (`PDT`, `EST`, `GMT`, etc.). Feeds emitting European or Asian
        //     named zones (`CET`, `CEST`, `BST`, `JST`, ...) fail every explicit-zone
        //     format above and would otherwise either fall through to the zoneless UTC
        //     fallback (off by N hours) or return `nil`. We rewrite the trailing zone
        //     token to its numeric offset so the standard numeric-offset formatters can
        //     consume it. See GitHub issue #213.
        if let substituted = substituteNamedZone(in: trimmed),
           let date = parseUsingZonedFormats(substituted, field: field) {
            return date
        }

        // 3. Zone-less fallback. The input doesn't match any explicit-zone format; the
        //    publisher almost certainly omitted zone information. Interpreting as UTC is
        //    a documented fallback — not a silent guess. Logged at `.debug` so the signal
        //    is available via `log stream` when investigating a specific feed without
        //    flooding the persisted log buffer: a feed that always emits zoneless
        //    timestamps would otherwise produce ~one persisted warning per article per
        //    refresh cycle, masking other warnings during post-mortem analysis. See
        //    GitHub issue #214.
        for (format, formatter) in HoistedDateFormatters.zoneless {
            if let date = formatter.date(from: trimmed) {
                Self.logger.debug(
                    "Feed date '\(trimmed, privacy: .public)' (field: \(field, privacy: .public)) had no timezone; interpreted as UTC (format '\(format, privacy: .public)')"
                )
                return sanityChecked(date, input: trimmed, source: "zoneless '\(format)'", field: field)
            }
        }

        Self.logger.warning(
            "Feed date '\(trimmed, privacy: .public)' (field: \(field, privacy: .public)) did not match any known format; returning nil"
        )
        return nil
    }

    /// Tries every explicit-zone `DateFormatter` pattern against `input`, returning the
    /// first sanity-checked match. Extracted so the named-zone preprocessing pass can
    /// re-run the same loop against a rewritten input without duplicating the formatter
    /// lookup.
    private static func parseUsingZonedFormats(_ input: String, field: String) -> Date? {
        for (format, formatter) in HoistedDateFormatters.zoned {
            if let date = formatter.date(from: input) {
                return sanityChecked(date, input: input, source: "zoned '\(format)'", field: field)
            }
        }
        return nil
    }

    /// If `input` ends with a recognized non-US named timezone abbreviation, returns a
    /// new string with that token replaced by its numeric offset (e.g.,
    /// `"...08:30:00 CET"` → `"...08:30:00 +0100"`). Returns `nil` if no recognized
    /// trailing zone is present, so the caller can short-circuit.
    ///
    /// Only the trailing whitespace-delimited token is examined: feed dates almost
    /// universally place the zone last, and rewriting tokens elsewhere risks corrupting
    /// month names or weekdays that happen to share letters with a zone abbreviation.
    ///
    /// The input is trimmed of leading/trailing whitespace and newlines before token
    /// extraction so trailing-space inputs (e.g., `"...08:30:00 CET "`) still resolve.
    /// Without this trim, the trailing token would be empty and the lookup would miss,
    /// causing the input to fall through to the zoneless UTC fallback (off by N hours).
    private static func substituteNamedZone(in input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let separatorIndex = trimmed.lastIndex(where: { $0 == " " }) else {
            return nil
        }
        let token = trimmed[trimmed.index(after: separatorIndex)...]
        guard let offset = Self.namedZoneOffsets[String(token).uppercased()] else {
            return nil
        }
        return trimmed[..<separatorIndex] + " " + offset
    }

    /// Lookup table mapping non-US named timezone abbreviations to their RFC 822 numeric
    /// offsets. The values intentionally use the `±HHMM` form so the substituted output
    /// is consumed by the standard `Z` specifier in `HoistedDateFormatters.zoned`.
    ///
    /// Some abbreviations are genuinely ambiguous; the chosen interpretations below are
    /// the most common worldwide usage and match what mainstream Python/Ruby/Java date
    /// libraries default to:
    ///
    /// - `IST` → India Standard Time (UTC+5:30). Could also mean Irish Standard Time
    ///   (UTC+1) or Israel Standard Time (UTC+2); India is the dominant publishing
    ///   population, so we default to it.
    /// - `CST` → China Standard Time (UTC+8). The North American "Central Standard
    ///   Time" (UTC-6) is parsed by `DateFormatter`'s `zzz` specifier directly and
    ///   never reaches this table because the prior explicit-zone pass already matched.
    ///   The substitution pass only runs when every explicit-zone format failed, which
    ///   in practice means the publisher meant the China zone.
    /// - `BST` → British Summer Time (UTC+1). Bangladesh Standard Time (UTC+6) is far
    ///   less common in feed payloads.
    ///
    /// Standard time and daylight time abbreviations are listed separately so each
    /// resolves to its own fixed offset; the parser deliberately does not consult the
    /// surrounding date to decide which form to apply.
    private static let namedZoneOffsets: [String: String] = [
        // Western Europe
        "WET": "+0000",     // Western European Time
        "WEST": "+0100",    // Western European Summer Time
        "BST": "+0100",     // British Summer Time
        "IST": "+0530",     // India Standard Time (see RATIONALE in doc comment)

        // Central Europe
        "CET": "+0100",     // Central European Time
        "CEST": "+0200",    // Central European Summer Time
        "MET": "+0100",     // Middle European Time (legacy alias for CET)
        "MEST": "+0200",    // Middle European Summer Time

        // Eastern Europe / Africa / Middle East
        "EET": "+0200",     // Eastern European Time
        "EEST": "+0300",    // Eastern European Summer Time
        "MSK": "+0300",     // Moscow Standard Time
        "MSD": "+0400",     // Moscow Summer Time (historical, retained for archival feeds)
        "TRT": "+0300",     // Turkey Time
        "SAST": "+0200",    // South Africa Standard Time
        "EAT": "+0300",     // East Africa Time

        // Asia
        "CST": "+0800",     // China Standard Time (see RATIONALE in doc comment)
        "HKT": "+0800",     // Hong Kong Time
        "SGT": "+0800",     // Singapore Time
        "PHT": "+0800",     // Philippine Time
        "JST": "+0900",     // Japan Standard Time
        "KST": "+0900",     // Korea Standard Time
        "ICT": "+0700",     // Indochina Time
        "WIB": "+0700",     // Western Indonesian Time
        "WITA": "+0800",    // Central Indonesian Time
        "WIT": "+0900",     // Eastern Indonesian Time

        // Oceania
        "AEST": "+1000",    // Australian Eastern Standard Time
        "AEDT": "+1100",    // Australian Eastern Daylight Time
        "ACST": "+0930",    // Australian Central Standard Time
        "ACDT": "+1030",    // Australian Central Daylight Time
        "AWST": "+0800",    // Australian Western Standard Time
        "NZST": "+1200",    // New Zealand Standard Time
        "NZDT": "+1300",    // New Zealand Daylight Time

        // South America
        "BRT": "-0300",     // Brasília Time
        "BRST": "-0200",    // Brasília Summer Time (no longer observed; archival feeds)
        "ART": "-0300",     // Argentina Time
        "CLT": "-0400",     // Chile Standard Time
        "CLST": "-0300",    // Chile Summer Time

        // Universal aliases not always recognized by DateFormatter. Bare "Z" is
        // intentionally omitted: any input ending in `" Z"` is consumed by the
        // first numeric-zone format (`...HH:mm:ss Z`) in `HoistedDateFormatters.zoned`,
        // since `DateFormatter`'s `Z` specifier with `en_US_POSIX` accepts the literal
        // `Z`. The substitution pass would never see it.
        "UT": "+0000",      // Universal Time (RFC 822 alias for UTC)
        "UTC": "+0000",     // Coordinated Universal Time (defense-in-depth)
    ]

    /// Lower bound used to reject obviously-wrong parse results. Predates RSS itself, so
    /// any feed date older than this is almost certainly a parser artifact (e.g.,
    /// `DateFormatter`'s `yyyy` accepting `"26"` as year 26 AD). Upper-bound handling is
    /// not a fixed value: see `sanityChecked` for the future-date clamp policy.
    private static let minimumPlausibleDate: Date = {
        var components = DateComponents()
        components.year = 1990
        components.month = 1
        components.day = 1
        components.timeZone = TimeZone(identifier: "UTC")
        // RATIONALE: Calendar.date(from:) on a hardcoded valid DateComponents can only
        // return nil under pathological calendar misconfiguration; distantPast is a safe
        // fallback that still allows all real-world feeds through.
        return Calendar(identifier: .gregorian).date(from: components) ?? Date.distantPast
    }()

    /// Validates that a parsed `Date` is plausible enough to preserve as the publisher's
    /// stated publication moment. Only the lower bound is enforced here: dates older than
    /// `minimumPlausibleDate` are rejected (returns `nil` with a `.warning` log) because
    /// they are almost certainly parser artifacts (e.g., `DateFormatter`'s `yyyy` "year of
    /// era" accepting `"26"` as year 26 AD) and clamping them would invent a fake date.
    ///
    /// **Future dates are intentionally allowed through unchanged.** Real-world feeds
    /// publish scheduled posts whose `pubDate` lies hours ahead of the fetch time (e.g.,
    /// the Cloudflare blog announces upcoming content). The publisher-supplied
    /// `publishedDate` is preserved verbatim because a planned content-update detection
    /// feature compares pubDate values across refreshes, so any mutation here would
    /// destroy that signal. The sort/retention/display problem caused by future dates is
    /// solved at insert time by `PersistentArticle.init(from:)`, which computes a
    /// separate clamped `sortDate` field — see `RSSApp/Models/ModelConversion.swift`.
    private static func sanityChecked(_ date: Date, input: String, source: String, field: String) -> Date? {
        if date < Self.minimumPlausibleDate {
            Self.logger.warning(
                "Rejected implausibly-old parsed date \(date, privacy: .public) from input '\(input, privacy: .public)' (source: \(source, privacy: .public), field: \(field, privacy: .public))"
            )
            return nil
        }
        return date
    }

    // The pre-built formatters below are initialized once via `static let` and never
    // mutated after initialization — only `date(from:)` is called. Hoisting avoids
    // allocating a fresh `DateFormatter` and mutating its `dateFormat` on every
    // `parseDate` call (~one allocation per article per refresh). Pre-building one
    // formatter per format also eliminates the shared-mutable-state hazard of a
    // single formatter with an in-loop `dateFormat` assignment, so the parser is
    // safe to invoke concurrently from multiple feed refreshes. See GitHub issue
    // #217. The "never mutated after init" invariant is protected by the existing
    // date-parsing tests: any stray `formatter.dateFormat = ...` within `parseDate`
    // would corrupt subsequent format branches within the same `parse()` call
    // (which walks multiple formatters for multi-item feeds), making a dedicated
    // invariant pin redundant.
    fileprivate enum HoistedDateFormatters {
        /// Date formats that include an explicit timezone specifier, each paired with a
        /// pre-configured `DateFormatter`. Ordered roughly by expected frequency (RFC
        /// 822 numeric-offset forms first). `parseUsingZonedFormats` tries each entry in
        /// order and stops on the first match, so ordering affects parse cost for
        /// non-matching inputs but not correctness.
        ///
        /// Every formatter's `timeZone` is pinned to UTC as defense-in-depth so that
        /// any format that fails to read a zone from the input (rather than falling
        /// through to the zoneless block) won't silently inherit the device's local
        /// zone.
        static let zoned: [(format: String, formatter: DateFormatter)] =
            makeFormatters(for: [
                // RFC 822 / RFC 2822 with numeric offset (most common in RSS)
                "EEE, dd MMM yyyy HH:mm:ss Z",
                // RFC 822 with named timezone (e.g., "GMT", "EST", "PDT")
                "EEE, dd MMM yyyy HH:mm:ss zzz",
                // Single-digit day variant (appears in real RFC 822 feeds)
                "EEE, d MMM yyyy HH:mm:ss Z",
                "EEE, d MMM yyyy HH:mm:ss zzz",
                // Without weekday (seen in the wild). Only the single-digit-day (`d`)
                // variants are listed: `DateFormatter`'s `d` specifier with
                // `en_US_POSIX` accepts both one- and two-digit days, so a separate
                // `dd`-prefixed entry would be dead code (the `d` variant immediately
                // below would already match every input the `dd` variant could).
                "d MMM yyyy HH:mm:ss Z",
                "d MMM yyyy HH:mm:ss zzz",
                // Without seconds (RFC 2822/5322 permits this; rare but appears in some wire formats)
                "EEE, dd MMM yyyy HH:mm Z",
                "EEE, dd MMM yyyy HH:mm zzz",
                // ISO 8601 with 'T' separator and numeric zone. These are
                // defense-in-depth safety nets for ISO 8601-ish inputs that
                // ISO8601DateFormatter rejects (e.g., unusual fractional-seconds
                // precision or minor whitespace quirks).
                "yyyy-MM-dd'T'HH:mm:ssZ",
                "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
                // ISO 8601 with space separator instead of 'T' (common in
                // SQL-flavored feeds).
                // RATIONALE: there is no separate `"yyyy-MM-dd HH:mm:ss Z"` entry
                // (with a space before `Z`) because `DateFormatter`'s `Z` specifier
                // with `en_US_POSIX` tolerates leading whitespace before the offset
                // token, so the no-space form below already absorbs
                // `"2026-04-06 08:30:00 -0700"` and a separate spaced variant would be
                // dead code.
                "yyyy-MM-dd HH:mm:ssZ",
                "yyyy-MM-dd HH:mm:ss zzz",
            ])

        /// Date formats *without* a timezone specifier, each paired with a
        /// pre-configured `DateFormatter` whose `timeZone` is forced to UTC. These are
        /// attempted last. A debug log is emitted whenever one of these matches because
        /// the resulting `Date` is necessarily an educated guess.
        static let zoneless: [(format: String, formatter: DateFormatter)] =
            makeFormatters(for: [
                "EEE, dd MMM yyyy HH:mm:ss",
                "EEE, dd MMM yyyy HH:mm",
                "dd MMM yyyy HH:mm:ss",
                "yyyy-MM-dd'T'HH:mm:ss.SSS",
                "yyyy-MM-dd'T'HH:mm:ss",
                "yyyy-MM-dd HH:mm:ss",
                "yyyy-MM-dd",
            ])

        private static func makeFormatters(for formats: [String]) -> [(format: String, formatter: DateFormatter)] {
            formats.map { format in
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.timeZone = TimeZone(identifier: "UTC")
                formatter.dateFormat = format
                return (format, formatter)
            }
        }
    }

    // RATIONALE: nonisolated(unsafe) is safe because these formatters are initialized
    // once via static let and never mutated after initialization — only date(from:) is
    // called. The invariant is protected by the existing ISO 8601 date-parsing tests,
    // which would deterministically fail on any `formatOptions` mutation observed
    // within a single parse call.
    fileprivate enum ISO8601Formatters {
        nonisolated(unsafe) static let standard: ISO8601DateFormatter = {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            return formatter
        }()

        nonisolated(unsafe) static let fractional: ISO8601DateFormatter = {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter
        }()
    }
}
