import Foundation
import os

enum RSSParsingError: Error, Sendable {
    case parsingFailed(description: String)
    case noChannelFound
}

struct RSSParsingService: Sendable {

    private static let logger = Logger(category: "RSSParsingService")

    static let snippetMaxLength = 200

    // MARK: - Test Accessors
    //
    // These accessors expose the private `RSSParserDelegate.HoistedDateFormatters` and
    // `RSSParserDelegate.ISO8601Formatters` enums to `@testable` test code so the
    // "never mutated after init" invariant that justifies their `nonisolated(unsafe)`
    // declaration can be pinned down by unit tests. See GitHub issue #242 and the
    // `RATIONALE:` comments on the underlying enums for why the invariant matters.
    //
    // These are only meant to be consumed by tests. Production code inside
    // `RSSParserDelegate` keeps using the private nested enums directly. Exposing them
    // via accessors rather than relaxing the access level on the enums themselves
    // preserves the invariant that no code outside this file can reach for a raw
    // `DateFormatter` reference accidentally.

    /// Pre-built zoned `DateFormatter` entries used by `parseDate`. Exposed for
    /// invariant tests; do not mutate.
    static var hoistedZonedFormattersForTesting: [(format: String, formatter: DateFormatter)] {
        RSSParserDelegate.HoistedDateFormatters.zoned
    }

    /// Pre-built zoneless `DateFormatter` entries used by `parseDate`. Exposed for
    /// invariant tests; do not mutate.
    static var hoistedZonelessFormattersForTesting: [(format: String, formatter: DateFormatter)] {
        RSSParserDelegate.HoistedDateFormatters.zoneless
    }

    /// The standard (non-fractional) `ISO8601DateFormatter` used by `parseDate`. Exposed
    /// for invariant tests; do not mutate.
    static var iso8601StandardFormatterForTesting: ISO8601DateFormatter {
        RSSParserDelegate.ISO8601Formatters.standard
    }

    /// The fractional-second `ISO8601DateFormatter` used by `parseDate`. Exposed for
    /// invariant tests; do not mutate.
    static var iso8601FractionalFormatterForTesting: ISO8601DateFormatter {
        RSSParserDelegate.ISO8601Formatters.fractional
    }

    func parse(_ data: Data) throws -> RSSFeed {
        Self.logger.debug("parse() called with \(data.count, privacy: .public) bytes")

        let delegate = RSSParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        parser.shouldReportNamespacePrefixes = false

        guard parser.parse() else {
            let errorDescription = parser.parserError?.localizedDescription ?? "Unknown parsing error"
            Self.logger.error("XML parsing failed: \(errorDescription, privacy: .public)")
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
            imageURL: imageURL
        )

        Self.logger.notice("Feed parsed: '\(feed.title, privacy: .public)' with \(feed.articles.count, privacy: .public) articles")
        return feed
    }
}

// MARK: - XMLParser Delegate

// RATIONALE: @unchecked Sendable is safe because the delegate is created and consumed
// synchronously within a single parse() call and never escapes that scope.
private final class RSSParserDelegate: NSObject, XMLParserDelegate, @unchecked Sendable {

    private static let logger = Logger(category: "RSSParserDelegate")

    var foundChannel = false
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
            foundChannel = true

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
            case "pubDate":
                itemPubDate = textBuffer
            case "published":
                itemPubDate = textBuffer
            case "updated":
                // Atom <updated>: captured unconditionally as the first-class update signal,
                // and *also* used as a fallback for the publication date when neither RSS
                // <pubDate> nor Atom <published> was present.
                itemUpdatedDate = textBuffer
                if itemPubDate.isEmpty {
                    itemPubDate = textBuffer
                }
            // RATIONALE: namespace processing is disabled on the XMLParser
            // (`shouldProcessNamespaces = false`), so namespaced elements arrive here as
            // their literal qualified names. Matching the standard prefixes — `dc:`, `dcterms:`,
            // and `atom:` — covers the overwhelming majority of feeds. A feed declaring its
            // own custom prefix for the Dublin Core or Atom namespace (e.g.,
            // `xmlns:foo="http://purl.org/dc/elements/1.1/"` and using `foo:modified`) will
            // not be matched. The principled fix would be enabling namespace processing
            // and reworking every existing namespaced case (`content:encoded`, `media:*`,
            // etc.); that is out of scope for issue #74.
            case "dc:modified", "dcterms:modified":
                // Dublin Core modification date — rare in practice but cheap to support
                // because the parser already matches namespaced elements by literal prefix.
                itemUpdatedDate = textBuffer
                if itemPubDate.isEmpty {
                    itemPubDate = textBuffer
                }
            case "atom:updated":
                // Some RSS 2.0 feeds embed Atom elements via `xmlns:atom`. Treat identically
                // to a native Atom <updated>.
                itemUpdatedDate = textBuffer
                if itemPubDate.isEmpty {
                    itemPubDate = textBuffer
                }
            case "dc:date", "dcterms:created":
                // Dublin Core publication date — fallback only. Real RSS <pubDate> or Atom
                // <published> take priority, matching the existing precedence rules. This is
                // a publication signal, not an update signal, so it does NOT populate
                // itemUpdatedDate.
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
                    channelUpdated = Self.parseDate(textBuffer)
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
            publishedDate: Self.parseDate(itemPubDate),
            updatedDate: Self.parseDate(itemUpdatedDate),
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
    private static func parseDate(_ dateString: String) -> Date? {
        let trimmed = dateString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // 1. ISO 8601 / RFC 3339 — most modern feeds use this. Handles `...Z`,
        //    `...+0000`, `...-07:00`, and fractional-second variants.
        if let date = ISO8601Formatters.standard.date(from: trimmed) {
            return sanityChecked(date, input: trimmed, source: "ISO8601")
        }
        if let date = ISO8601Formatters.fractional.date(from: trimmed) {
            return sanityChecked(date, input: trimmed, source: "ISO8601 fractional")
        }

        // 2. Explicit-zone DateFormatter patterns (RFC 822 / RFC 2822 and common variants).
        //    Every format here must end in a zone specifier; zone-less formats are handled
        //    in the fallback block below with clearly documented UTC assumption and logging.
        //    Each formatter is pre-built once in `HoistedDateFormatters` with its
        //    `dateFormat` fixed at initialization — we never mutate shared state here, so
        //    concurrent calls from multiple feed refreshes are safe without locking.
        if let date = parseUsingZonedFormats(trimmed) {
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
           let date = parseUsingZonedFormats(substituted) {
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
                    "Feed date '\(trimmed, privacy: .public)' had no timezone; interpreted as UTC (format '\(format, privacy: .public)')"
                )
                return sanityChecked(date, input: trimmed, source: "zoneless '\(format)'")
            }
        }

        Self.logger.warning(
            "Feed date '\(trimmed, privacy: .public)' did not match any known format; returning nil"
        )
        return nil
    }

    /// Tries every explicit-zone `DateFormatter` pattern against `input`, returning the
    /// first sanity-checked match. Extracted so the named-zone preprocessing pass can
    /// re-run the same loop against a rewritten input without duplicating the formatter
    /// lookup.
    private static func parseUsingZonedFormats(_ input: String) -> Date? {
        for (format, formatter) in HoistedDateFormatters.zoned {
            if let date = formatter.date(from: input) {
                return sanityChecked(date, input: input, source: "zoned '\(format)'")
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
    private static func sanityChecked(_ date: Date, input: String, source: String) -> Date? {
        if date < Self.minimumPlausibleDate {
            Self.logger.warning(
                "Rejected implausibly-old parsed date \(date, privacy: .public) from input '\(input, privacy: .public)' (source: \(source, privacy: .public))"
            )
            return nil
        }
        return date
    }

    // RATIONALE: nonisolated(unsafe) is safe because these formatters are initialized
    // once via static let and never mutated after initialization — only date(from:) is
    // called. Hoisting avoids allocating a fresh `DateFormatter` and mutating its
    // `dateFormat` on every `parseDate` call (~one allocation per article per refresh).
    // Pre-building one formatter per format also eliminates the shared-mutable-state
    // hazard of a single formatter with an in-loop `dateFormat` assignment, so the
    // parser is safe to invoke concurrently from multiple feed refreshes. See GitHub
    // issue #217. The invariant is pinned down by `RSSParsingServiceTests` via the
    // `hoistedZonedFormattersForTesting` / `hoistedZonelessFormattersForTesting`
    // accessors on `RSSParsingService` — see GitHub issue #242.
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
        nonisolated(unsafe) static let zoned: [(format: String, formatter: DateFormatter)] =
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
        nonisolated(unsafe) static let zoneless: [(format: String, formatter: DateFormatter)] =
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
    // called. The invariant is pinned down by `RSSParsingServiceTests` via the
    // `iso8601StandardFormatterForTesting` / `iso8601FractionalFormatterForTesting`
    // accessors on `RSSParsingService` — see GitHub issue #242.
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
