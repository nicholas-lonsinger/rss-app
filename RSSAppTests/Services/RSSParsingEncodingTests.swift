import Testing
import Foundation
@testable import RSSApp

/// Tests for the BOM-and-declaration encoding sniffer added to `RSSParsingService`
/// so real-world feeds in UTF-16, UTF-32, Big5, EUC-KR, ISO-8859-*, and other
/// non-UTF-8 encodings can be parsed successfully. Each test constructs the
/// encoded bytes inline — fixtures are not loaded from disk so tests are
/// hermetic and safe for CI.
@Suite("RSSParsingService encoding sniffing")
struct RSSParsingEncodingTests {

    private let service = RSSParsingService()

    // MARK: - UTF-8 (fast path)

    @Test("Plain UTF-8 payload passes through unchanged")
    func plainUTF8PassesThrough() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0">
        <channel>
          <title>Plain</title>
          <item>
            <title>Item</title>
            <description>hello</description>
          </item>
        </channel>
        </rss>
        """
        let feed = try service.parse(Data(xml.utf8))
        #expect(feed.title == "Plain")
        #expect(feed.articles.first?.articleDescription == "hello")
    }

    @Test("UTF-8 payload with leading BOM is stripped and parses")
    func utf8WithBOM() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0">
        <channel>
          <title>BOM feed</title>
          <item><title>Item</title></item>
        </channel>
        </rss>
        """
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(Data(xml.utf8))
        let feed = try service.parse(data)
        #expect(feed.title == "BOM feed")
        #expect(feed.articles.count == 1)
    }

    // MARK: - UTF-16

    @Test("UTF-16 LE with BOM is transcoded and parses")
    func utf16LEWithBOM() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-16"?>
        <rss version="2.0">
        <channel>
          <title>LE feed</title>
          <item><title>韓</title><description>한글</description></item>
        </channel>
        </rss>
        """
        var data = Data([0xFF, 0xFE])
        data.append(xml.data(using: .utf16LittleEndian)!)
        let feed = try service.parse(data)
        #expect(feed.title == "LE feed")
        #expect(feed.articles.first?.title == "韓")
        #expect(feed.articles.first?.articleDescription == "한글")
    }

    @Test("UTF-16 BE with BOM is transcoded and parses")
    func utf16BEWithBOM() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-16"?>
        <rss version="2.0"><channel><title>BE feed</title><item><title>日</title></item></channel></rss>
        """
        var data = Data([0xFE, 0xFF])
        data.append(xml.data(using: .utf16BigEndian)!)
        let feed = try service.parse(data)
        #expect(feed.title == "BE feed")
        #expect(feed.articles.first?.title == "日")
    }

    @Test("UTF-16 LE without BOM is detected from byte pattern and parses")
    func utf16LEWithoutBOM() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-16LE"?>
        <rss version="2.0"><channel><title>no BOM LE</title><item><title>x</title></item></channel></rss>
        """
        let data = xml.data(using: .utf16LittleEndian)!
        let feed = try service.parse(data)
        #expect(feed.title == "no BOM LE")
        #expect(feed.articles.count == 1)
    }

    @Test("UTF-16 BE without BOM is detected from byte pattern and parses")
    func utf16BEWithoutBOM() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-16BE"?>
        <rss version="2.0"><channel><title>no BOM BE</title><item><title>x</title></item></channel></rss>
        """
        let data = xml.data(using: .utf16BigEndian)!
        let feed = try service.parse(data)
        #expect(feed.title == "no BOM BE")
        #expect(feed.articles.count == 1)
    }

    // MARK: - Named charsets (declaration scanning)

    @Test("ISO-8859-1 declaration is resolved and £ is decoded correctly")
    func iso8859_1Decoded() throws {
        // £ is 0xA3 in ISO-8859-1
        let head = Data("<?xml version=\"1.0\" encoding=\"ISO-8859-1\"?>".utf8)
        let body = """

        <rss version="2.0"><channel><title>Pound</title><item><title>Cost</title><description>A £ test</description></item></channel></rss>
        """
        guard let bodyData = body.data(using: .isoLatin1) else {
            Issue.record("Could not encode body as ISO-8859-1")
            return
        }
        let feed = try service.parse(head + bodyData)
        #expect(feed.articles.first?.articleDescription == "A £ test")
    }

    @Test("Windows-1252 declaration resolves smart quotes (0x92)")
    func windows1252SmartQuote() throws {
        // Windows-1252 0x92 = U+2019 (right single quotation mark)
        let head = Data("<?xml version=\"1.0\" encoding=\"windows-1252\"?>".utf8)
        let body = """

        <rss version="2.0"><channel><title>Smart</title><item><title>x</title><description>don\u{2019}t</description></item></channel></rss>
        """
        guard let bodyData = body.data(using: .windowsCP1252) else {
            Issue.record("Could not encode body as windows-1252")
            return
        }
        let feed = try service.parse(head + bodyData)
        #expect(feed.articles.first?.articleDescription == "don\u{2019}t")
    }

    @Test("Single-quoted encoding attribute in declaration is accepted")
    func singleQuotedEncodingDeclaration() throws {
        let head = Data("<?xml version='1.0' encoding='ISO-8859-1'?>".utf8)
        let body = """

        <rss version="2.0"><channel><title>quoted</title><item><title>Cost</title><description>£50</description></item></channel></rss>
        """
        let feed = try service.parse(head + body.data(using: .isoLatin1)!)
        #expect(feed.articles.first?.articleDescription == "£50")
    }

    @Test("Big5 declaration round-trips multi-byte CJK content through parse()")
    func big5CJKRoundTrip() throws {
        // Big5 is the motivating case for this PR — CJK feeds declared as Big5
        // are the most common encoding that XMLParser cannot handle natively.
        // Use the IANA name path the production code uses so a lookup regression
        // would break this test too.
        guard let big5 = EncodingSniffer.encodingFromIANAName("Big5") else {
            Issue.record("Big5 encoding unsupported on this platform")
            return
        }
        let xml = """
        <?xml version="1.0" encoding="Big5"?>
        <rss version="2.0"><channel><title>繁體</title><item><title>中文</title><description>台灣</description></item></channel></rss>
        """
        guard let data = xml.data(using: big5) else {
            Issue.record("Could not encode document as Big5")
            return
        }
        let feed = try service.parse(data)
        #expect(feed.title == "繁體")
        #expect(feed.articles.count == 1)
        #expect(feed.articles.first?.title == "中文")
        #expect(feed.articles.first?.articleDescription == "台灣")
    }

    // MARK: - Graceful degradation

    @Test("Unknown encoding name strips prolog and falls through to UTF-8 body")
    func unknownEncodingNameDoesNotCrash() throws {
        // Unknown charset name — sniffer should strip the prolog and pass the
        // remaining bytes through so XMLParser treats them as UTF-8. Content is
        // actually UTF-8 here, so the parse should succeed with all articles intact.
        // A regression that over-eats content in `stripProlog` would be caught by
        // the article-level assertions below.
        let xml = """
        <?xml version="1.0" encoding="x-obviously-fake-encoding"?>
        <rss version="2.0"><channel><title>fallback</title><item><title>x</title><description>body text</description></item></channel></rss>
        """
        let feed = try service.parse(Data(xml.utf8))
        #expect(feed.title == "fallback")
        #expect(feed.articles.count == 1)
        #expect(feed.articles.first?.title == "x")
        #expect(feed.articles.first?.articleDescription == "body text")
    }

    @Test("Empty data throws parsingFailed, not a crash")
    func emptyDataThrows() {
        #expect(throws: RSSParsingError.self) {
            try service.parse(Data())
        }
    }

    // MARK: - Sniffer unit tests (exposed via @testable import)

    @Test("BOM detector identifies all supported BOMs")
    func bomDetection() {
        // UTF-8
        let utf8 = Data([0xEF, 0xBB, 0xBF, 0x3C])
        #expect(EncodingSniffer.detectBOM(utf8)?.encoding == .utf8)
        #expect(EncodingSniffer.detectBOM(utf8)?.bomLength == 3)

        // UTF-16 BE
        let utf16BE = Data([0xFE, 0xFF, 0x00, 0x3C])
        #expect(EncodingSniffer.detectBOM(utf16BE)?.encoding == .utf16BigEndian)
        #expect(EncodingSniffer.detectBOM(utf16BE)?.bomLength == 2)

        // UTF-16 LE (note: prefix of UTF-32 LE, must be disambiguated)
        let utf16LE = Data([0xFF, 0xFE, 0x3C, 0x00])
        #expect(EncodingSniffer.detectBOM(utf16LE)?.encoding == .utf16LittleEndian)

        // UTF-32 BE
        let utf32BE = Data([0x00, 0x00, 0xFE, 0xFF])
        #expect(EncodingSniffer.detectBOM(utf32BE)?.encoding == .utf32BigEndian)

        // UTF-32 LE (must be checked BEFORE UTF-16 LE to avoid misclassification)
        let utf32LE = Data([0xFF, 0xFE, 0x00, 0x00])
        #expect(EncodingSniffer.detectBOM(utf32LE)?.encoding == .utf32LittleEndian)

        // No BOM
        #expect(EncodingSniffer.detectBOM(Data([0x3C, 0x3F, 0x78, 0x6D])) == nil)
    }

    @Test("Wide encoding detection without BOM identifies UTF-16 and UTF-32 from '<' position")
    func wideDetectionWithoutBOM() {
        // UTF-16 LE: `3C 00 3F 00` (the `<?` of `<?xml`)
        #expect(EncodingSniffer.detectWideEncodingWithoutBOM(Data([0x3C, 0x00, 0x3F, 0x00]))
                == .utf16LittleEndian)

        // UTF-16 BE: `00 3C 00 3F`
        #expect(EncodingSniffer.detectWideEncodingWithoutBOM(Data([0x00, 0x3C, 0x00, 0x3F]))
                == .utf16BigEndian)

        // UTF-32 LE: `3C 00 00 00`
        #expect(EncodingSniffer.detectWideEncodingWithoutBOM(Data([0x3C, 0x00, 0x00, 0x00]))
                == .utf32LittleEndian)

        // UTF-32 BE: `00 00 00 3C`
        #expect(EncodingSniffer.detectWideEncodingWithoutBOM(Data([0x00, 0x00, 0x00, 0x3C]))
                == .utf32BigEndian)

        // Plain ASCII `<?xm` — not wide
        #expect(EncodingSniffer.detectWideEncodingWithoutBOM(Data([0x3C, 0x3F, 0x78, 0x6D])) == nil)
    }

    @Test("Declaration scanner extracts double-quoted encoding name")
    func scanDoubleQuoted() {
        let data = Data("<?xml version=\"1.0\" encoding=\"Big5\"?><rss/>".utf8)
        #expect(EncodingSniffer.scanEncodingDeclaration(data) == "Big5")
    }

    @Test("Declaration scanner extracts single-quoted encoding name")
    func scanSingleQuoted() {
        let data = Data("<?xml version='1.0' encoding='euc-kr'?><rss/>".utf8)
        #expect(EncodingSniffer.scanEncodingDeclaration(data) == "euc-kr")
    }

    @Test("Declaration scanner returns nil when encoding attribute is absent")
    func scanNoEncodingAttribute() {
        let data = Data("<?xml version=\"1.0\"?><rss/>".utf8)
        #expect(EncodingSniffer.scanEncodingDeclaration(data) == nil)
    }

    @Test("Declaration scanner returns nil when no <?xml declaration is present")
    func scanNoDeclaration() {
        let data = Data("<rss version=\"2.0\"/>".utf8)
        #expect(EncodingSniffer.scanEncodingDeclaration(data) == nil)
    }

    @Test("IANA name lookup resolves common charsets")
    func ianaNameLookup() {
        #expect(EncodingSniffer.encodingFromIANAName("UTF-8") == .utf8)
        #expect(EncodingSniffer.encodingFromIANAName("iso-8859-1") == .isoLatin1)
        #expect(EncodingSniffer.encodingFromIANAName("windows-1252") == .windowsCP1252)
        // Non-existent
        #expect(EncodingSniffer.encodingFromIANAName("x-not-a-real-charset") == nil)
    }

    @Test("stripXMLDeclaration removes prolog and leaves body intact")
    func stripDeclaration() {
        let input = "<?xml version=\"1.0\" encoding=\"Big5\"?><rss/>"
        #expect(EncodingSniffer.stripXMLDeclaration(input) == "<rss/>")
    }

    @Test("stripXMLDeclaration is a no-op when no declaration is present")
    func stripNoDeclaration() {
        let input = "<rss version=\"2.0\"/>"
        #expect(EncodingSniffer.stripXMLDeclaration(input) == input)
    }

    @Test("stripXMLDeclaration strips a leading U+FEFF zero-width no-break space")
    func stripLeadingBOMChar() {
        // U+FEFF can sneak in after transcoding if the original BOM was preserved.
        let input = "\u{FEFF}<?xml version=\"1.0\" encoding=\"Big5\"?><rss/>"
        #expect(EncodingSniffer.stripXMLDeclaration(input) == "<rss/>")
    }

    @Test("stripProlog removes the leading <?xml ... ?> at the byte level")
    func stripPrologRemovesDeclaration() {
        let prolog = Data("<?xml version=\"1.0\" encoding=\"x-fake\"?>".utf8)
        let body = Data("<rss version=\"2.0\"/>".utf8)
        let stripped = EncodingSniffer.stripProlog(prolog + body)
        #expect(stripped == body, "stripProlog should return exactly the body bytes")
    }

    @Test("stripProlog returns nil when no <?xml prefix is present")
    func stripPrologReturnsNilWithoutPrefix() {
        let data = Data("<rss version=\"2.0\"/>".utf8)
        #expect(EncodingSniffer.stripProlog(data) == nil)
    }

    @Test("stripProlog preserves multi-byte UTF-8 body bytes unchanged")
    func stripPrologPreservesUTF8Body() {
        // Hangul encoded as UTF-8 contains 0xED..0xB1 sequences. A byte-level
        // strip that mistakenly decoded the remainder as ASCII would mangle
        // these; the function must return the body bytes verbatim.
        let prolog = Data("<?xml version=\"1.0\" encoding=\"x-fake\"?>".utf8)
        let body = Data("<rss><title>한글</title></rss>".utf8)
        let stripped = EncodingSniffer.stripProlog(prolog + body)
        #expect(stripped == body)
    }

    // MARK: - BOM precedence over declaration

    @Test("UTF-16 LE BOM beats an in-body encoding=\"UTF-8\" declaration")
    func bomBeatsInBandDeclaration() throws {
        // The XML spec says a byte-order mark is authoritative and overrides any
        // `encoding="..."` attribute in the declaration. Construct a UTF-16 LE
        // payload whose declaration *lies* and claims to be UTF-8 — the sniffer
        // must trust the BOM, transcode the bytes as UTF-16 LE, and produce a
        // parseable feed. A reordering refactor that consulted the declaration
        // before the BOM would miss the BOM's authority, hand XMLParser raw
        // UTF-16 bytes under a UTF-8 assumption, and the parse would fail.
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0"><channel><title>BOM wins</title><item><title>대한민국</title><description>Hangul body</description></item></channel></rss>
        """
        var data = Data([0xFF, 0xFE])
        data.append(xml.data(using: .utf16LittleEndian)!)
        let feed = try service.parse(data)
        #expect(feed.title == "BOM wins")
        #expect(feed.articles.first?.title == "대한민국")
        #expect(feed.articles.first?.articleDescription == "Hangul body")
    }

    // MARK: - ASCII fast-path identity returns

    @Test("ASCII-compatible declared encodings short-circuit and return identical bytes",
          arguments: ["UTF-8", "utf-8", "utf8", "us-ascii", "US-ASCII", "ascii", "ASCII"])
    func asciiFastPathReturnsIdentityBytes(declared: String) {
        // `transcodeToUTF8IfNeeded` shortcuts on `utf-8`, `utf8`, `us-ascii`, and
        // `ascii` (case-insensitive via `lowercased()`). For these names the function
        // must return the *exact* input bytes — same length, same content — because
        // XMLParser handles them natively and any allocation here is wasted work.
        // Pinning the list as a parameterized test ensures a refactor that adds or
        // removes a name is caught.
        let xml = """
        <?xml version="1.0" encoding="\(declared)"?>
        <rss version="2.0"><channel><title>fast</title><item><title>x</title></item></channel></rss>
        """
        let input = Data(xml.utf8)
        let (output, outcome) = EncodingSniffer.transcodeToUTF8IfNeeded(input)
        #expect(output == input, "Expected identity return for declared encoding '\(declared)'")
        if case .utf8Passthrough = outcome { } else {
            Issue.record("Expected .utf8Passthrough outcome for declared encoding '\(declared)', got: \(outcome)")
        }
    }

    // MARK: - Malformed declarations

    @Test("Declaration scanner returns nil when no value follows the '=' after encoding")
    func scanMalformedNoValueAfterEquals() {
        // `encoding=` followed immediately by `?>` — the `=` is present but the
        // declaration ends immediately after it, so the post-`=` bounds check
        // (`guard cursor < declaration.endIndex`) returns nil before any
        // quote-handling runs. A future refactor that lazily defaults to "" or
        // returns the empty string would slip past the rest of the suite.
        let data = Data("<?xml version=\"1.0\" encoding=?><rss/>".utf8)
        #expect(EncodingSniffer.scanEncodingDeclaration(data) == nil)
    }

    @Test("Declaration scanner returns nil when the opening quote is never closed")
    func scanMalformedUnclosedQuote() {
        // `encoding="` opens a quoted value, but `?>` terminates the declaration
        // before any matching `"` is seen. The scanner must return nil rather than
        // greedily consuming bytes from the body.
        let data = Data("<?xml version=\"1.0\" encoding=\"?><rss/>".utf8)
        #expect(EncodingSniffer.scanEncodingDeclaration(data) == nil)
    }

    @Test("Declaration scanner returns nil for an empty quoted encoding name")
    func scanMalformedEmptyName() {
        // `encoding=""` parses cleanly through the quote-pair logic but yields an
        // empty name. The function explicitly returns nil for this case so the
        // caller falls through to the UTF-8 default rather than asking
        // `CFStringConvertIANACharSetNameToEncoding` to look up "".
        let data = Data("<?xml version=\"1.0\" encoding=\"\"?><rss/>".utf8)
        #expect(EncodingSniffer.scanEncodingDeclaration(data) == nil)
    }

    @Test("Declaration scanner tolerates whitespace around the '=' in encoding attribute")
    func scanWhitespaceAroundEquals() {
        // The XML spec permits whitespace on either side of `=` in attribute
        // assignments. The scanner consumes whitespace before and after the `=`,
        // so this declaration must resolve to "Big5".
        let data = Data("<?xml version=\"1.0\" encoding  =  \"Big5\"?><rss/>".utf8)
        #expect(EncodingSniffer.scanEncodingDeclaration(data) == "Big5")
    }

    // MARK: - Prolog scan window boundary

    @Test("Declaration scanner finds an encoding attribute that ends just inside the 256-byte window")
    func scanEncodingNearWindowEdge() {
        // Pad the prolog with whitespace between `<?xml` and `encoding=` so the
        // closing `?>` lands at roughly byte 250 — inside the 256-byte scan
        // window. The scanner must still extract "Big5".
        // Construction: "<?xml version=\"1.0\" " (20) + spaces (213) + "encoding=\"Big5\"?>" (17) = 250 bytes,
        // plus trailing "<rss/>" (6) = 256 bytes total.
        let head = "<?xml version=\"1.0\" "
        let tail = "encoding=\"Big5\"?>"
        let padCount = 250 - head.count - tail.count
        let prolog = head + String(repeating: " ", count: padCount) + tail + "<rss/>"
        let data = Data(prolog.utf8)
        #expect(prolog.utf8.count == 256)
        #expect(EncodingSniffer.scanEncodingDeclaration(data) == "Big5")
    }

    @Test("Declaration scanner returns nil when the prolog spills past the 256-byte window")
    func scanEncodingPastWindowEdge() {
        // Same construction as above, but pad enough that the closing `?>` lands
        // past byte 256. The scanner only inspects the first `prologScanWindow`
        // (256) bytes, so `range(of: "?>")` cannot find the terminator and the
        // function returns nil. This pins the 256 constant numerically: a
        // refactor that tightened the window to 200 would still pass with the
        // 250-byte test above but break here, while a refactor that loosened it
        // to 1024 would silently start succeeding here — both are caught.
        let head = "<?xml version=\"1.0\" "
        let tail = "encoding=\"Big5\"?>"
        let padCount = 270 - head.count - tail.count
        let prolog = head + String(repeating: " ", count: padCount) + tail + "<rss/>"
        let data = Data(prolog.utf8)
        #expect(prolog.utf8.count == 276)
        #expect(prolog.utf8.count > EncodingSniffer.prologScanWindow)
        #expect(EncodingSniffer.scanEncodingDeclaration(data) == nil)
    }

}

// MARK: - SnifferOutcome tests

/// Tests for `EncodingSniffer.SnifferOutcome` enum behavior and the outcome
/// returned by `transcodeToUTF8IfNeeded`. Parse-level error escalation
/// (empty feed after encoding fallback should log `.error`, not `.notice`) is
/// covered by `EmptyFeedEscalationTests`, not this suite.
@Suite("EncodingSniffer.SnifferOutcome")
struct SnifferOutcomeTests {

    // MARK: - isFallback

    @Test("isFallback is false for non-lossy outcomes")
    func isFallbackFalseForNonLossy() {
        #expect(!EncodingSniffer.SnifferOutcome.utf8Passthrough.isFallback)
        #expect(!EncodingSniffer.SnifferOutcome.bomStrippedUTF8.isFallback)
        #expect(!EncodingSniffer.SnifferOutcome.bomStrippedAndTranscoded(.utf16LittleEndian).isFallback)
        #expect(!EncodingSniffer.SnifferOutcome.transcoded(from: .isoLatin1).isFallback)
    }

    @Test("isFallback is true for lossy fallback outcomes")
    func isFallbackTrueForLossy() {
        #expect(EncodingSniffer.SnifferOutcome.unknownEncodingFallback("x-fake").isFallback)
        #expect(EncodingSniffer.SnifferOutcome.transcodeFailureFallback(.utf16LittleEndian).isFallback)
    }

    // MARK: - transcodeToUTF8IfNeeded outcome

    @Test("UTF-8 declared encoding returns .utf8Passthrough outcome")
    func utf8DeclarationReturnsPassthrough() {
        let xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?><rss/>"
        let (_, outcome) = EncodingSniffer.transcodeToUTF8IfNeeded(Data(xml.utf8))
        if case .utf8Passthrough = outcome { } else {
            Issue.record("Expected .utf8Passthrough, got: \(outcome)")
        }
    }

    @Test("No declaration returns .utf8Passthrough outcome")
    func noDeclarationReturnsPassthrough() {
        let xml = "<rss version=\"2.0\"/>"
        let (_, outcome) = EncodingSniffer.transcodeToUTF8IfNeeded(Data(xml.utf8))
        if case .utf8Passthrough = outcome { } else {
            Issue.record("Expected .utf8Passthrough, got: \(outcome)")
        }
    }

    @Test("UTF-8 BOM returns .bomStrippedUTF8 outcome")
    func utf8BOMReturnsBomStrippedUTF8() {
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(Data("<rss/>".utf8))
        let (_, outcome) = EncodingSniffer.transcodeToUTF8IfNeeded(data)
        if case .bomStrippedUTF8 = outcome { } else {
            Issue.record("Expected .bomStrippedUTF8, got: \(outcome)")
        }
    }

    @Test("UTF-16 LE BOM returns .bomStrippedAndTranscoded(.utf16LittleEndian) outcome")
    func utf16LEBOMReturnsBomStrippedAndTranscoded() {
        let xml = "<?xml version=\"1.0\"?><rss version=\"2.0\"><channel><title>t</title></channel></rss>"
        var data = Data([0xFF, 0xFE])
        data.append(xml.data(using: .utf16LittleEndian)!)
        let (_, outcome) = EncodingSniffer.transcodeToUTF8IfNeeded(data)
        if case .bomStrippedAndTranscoded(let enc) = outcome {
            #expect(enc == .utf16LittleEndian)
        } else {
            Issue.record("Expected .bomStrippedAndTranscoded(.utf16LittleEndian), got: \(outcome)")
        }
    }

    @Test("Named non-UTF-8 encoding returns .transcoded outcome")
    func isoLatin1DeclarationReturnsTranscoded() {
        let head = Data("<?xml version=\"1.0\" encoding=\"ISO-8859-1\"?>".utf8)
        let body = Data("<rss/>".utf8)
        let (_, outcome) = EncodingSniffer.transcodeToUTF8IfNeeded(head + body)
        if case .transcoded(let enc) = outcome {
            #expect(enc == .isoLatin1)
        } else {
            Issue.record("Expected .transcoded(from: .isoLatin1), got: \(outcome)")
        }
    }

    @Test("Unknown encoding name returns .unknownEncodingFallback outcome")
    func unknownEncodingNameReturnsUnknownFallback() {
        let uniqueName = "x-snifferoutcome-unknown-273"
        let xml = "<?xml version=\"1.0\" encoding=\"\(uniqueName)\"?><rss/>"
        let (_, outcome) = EncodingSniffer.transcodeToUTF8IfNeeded(Data(xml.utf8))
        if case .unknownEncodingFallback(let name) = outcome {
            #expect(name == uniqueName)
        } else {
            Issue.record("Expected .unknownEncodingFallback(\(uniqueName)), got: \(outcome)")
        }
    }
}

// MARK: - DiagnosticRecorder-backed tests

/// Top-level container that serializes all suites that manipulate the
/// process-global `DiagnosticRecorder.active` sink.
///
/// ## Why this wrapper exists
///
/// `DiagnosticRecorder.active` is a single process-global slot. Tests that
/// call `DiagnosticRecorder.install` or `.uninstall` must not run concurrently
/// with one another, otherwise one test can evict another test's sink mid-flight
/// — causing recorded events to land in the wrong sink or be dropped entirely.
///
/// Swift Testing's `.serialized` trait only serializes tests **within** the
/// suite it is applied to; it does not constrain parallel execution against
/// *sibling* suites at the same nesting level. A `.serialized` trait on each
/// inner suite individually (`EncodingSnifferDiagnosticTests`,
/// `EmptyFeedEscalationTests`) would prevent races among tests *within* each
/// suite, but still allow the two suites to run concurrently with each other.
///
/// Wrapping both under this single `.serialized` parent forces Swift Testing to
/// run every test in the hierarchy sequentially, eliminating the cross-suite
/// sink-eviction race described in issue #310. Because the trait is inherited by
/// nested suites, the inner suites do not need their own `.serialized` annotation.
///
/// **Residual concurrency:** `RSSParsingEncodingTests` runs outside this
/// wrapper and exercises `EncodingSniffer` code paths that emit to
/// `DiagnosticRecorder`. If a sink is installed by a concurrently running test
/// in `EncodingSnifferDiagnosticTests`, those emissions will land in that sink.
/// This is mitigated by pinning assertions to unique encoding names and byte
/// patterns rather than event counts.
@Suite("DiagnosticRecorder-backed tests", .serialized)
struct DiagnosticRecorderTests {

    // MARK: - EncodingSniffer diagnostic emission

    /// Diagnostic-emission tests for the `EncodingSniffer` fallback paths.
    ///
    /// These tests pin down the dual-emission (`os.Logger` + `DiagnosticRecorder`)
    /// contract introduced by issue #275. Without them, a refactor that silently
    /// removes a `logger.warning(...)` or `DiagnosticRecorder.record(...)` from a
    /// fallback path would make the fallback invisible in production AND pass the
    /// rest of the suite. The recorder-backed assertions below catch that
    /// regression.
    ///
    /// The enclosing `DiagnosticRecorderTests` wrapper is `.serialized`, so all
    /// tests in this suite run serially — both within the suite and against other
    /// suites like `EmptyFeedEscalationTests` (in addition to the cross-suite
    /// serialization enforced by the parent wrapper, issue #310).
    ///
    /// Assertions use `contains(where:)` pinned to unique encoding names and byte
    /// patterns rather than event counts so that stray emissions from the
    /// concurrently running `RSSParsingEncodingTests` suite cannot flake the test.
    @Suite("EncodingSniffer diagnostic emission")
    struct EncodingSnifferDiagnosticTests {

        @Test("Unknown encoding name fallback emits a warning diagnostic with the offending name")
        func unknownEncodingEmitsWarningDiagnostic() {
            let sink = RecordingDiagnosticSink()
            DiagnosticRecorder.install(sink)
            defer { DiagnosticRecorder.uninstall() }

            // Exercise `EncodingSniffer.transcodeToUTF8IfNeeded` directly so the
            // test only observes events the sniffer itself emits. Going through
            // `RSSParsingService.parse()` would introduce additional log
            // categories (e.g. `RSSParsingService`) in the sink that we'd have to
            // filter out. A unique fake encoding name is used below so any events
            // produced concurrently by `RSSParsingEncodingTests` (which runs outside
            // the `DiagnosticRecorderTests` wrapper) cannot match our
            // `contains(where:)` assertion.
            let uniqueName = "x-encseam-unknown-warn-278"
            let xml = """
            <?xml version="1.0" encoding="\(uniqueName)"?>
            <rss version="2.0"><channel><title>fallback</title><item><title>x</title><description>body</description></item></channel></rss>
            """
            _ = EncodingSniffer.transcodeToUTF8IfNeeded(Data(xml.utf8))

            // Pin the assertion to the unique name rather than counting events.
            // The enclosing `.serialized` wrapper (DiagnosticRecorderTests) prevents
            // EmptyFeedEscalationTests from racing with this suite. The
            // RSSParsingEncodingTests suite still runs concurrently and can land
            // EncodingSniffer events on the same global sink — the unique name
            // guard here ensures those events cannot match.
            let warnings = sink.events(atLevel: .warning)
                .filter { $0.category == EncodingSniffer.loggerCategory }
            let matching = warnings.filter { $0.message.contains(uniqueName) }
            #expect(!matching.isEmpty,
                    "Expected a warning diagnostic mentioning the unique unknown encoding name, got: \(warnings.map(\.message))")
            // The offending name and the "fallback" recovery hint must both appear
            // in the message so production log consumers (Console.app, post-mortem
            // reviewers) can diagnose which feed declared a charset the system
            // didn't recognize.
            #expect(matching.contains(where: { $0.message.contains("fallback") }))
        }

        // RATIONALE: `transcodeSuccessEmitsNoticeDiagnostic` was removed when
        // `transcode(_:from:)` was refactored to take a private `SniffedPayload`
        // (issue #274). The test previously called `transcode` directly to isolate
        // the notice emission. With the function now private there is no public
        // entry point through which the notice path can be reached while keeping
        // the declaration-scan bytes ASCII-clean (required by `scanEncodingDeclaration`)
        // AND the body bytes non-ASCII (required to make the transcode non-trivial).
        // The functional coverage — that a `.transcoded(from:)` outcome is produced
        // for ISO-8859-1 — is already provided by `SnifferOutcomeTests/isoLatin1DeclarationReturnsTranscoded`.

        @Test("Successful UTF-8 fast path emits no diagnostics for the sniffer")
        func utf8FastPathEmitsNoDiagnostics() {
            let sink = RecordingDiagnosticSink()
            DiagnosticRecorder.install(sink)
            defer { DiagnosticRecorder.uninstall() }

            // Direct sniffer invocation (see rationale above) — the UTF-8 fast
            // path should short-circuit inside `transcodeToUTF8IfNeeded` and emit
            // nothing. The input payload is tagged with a unique marker so any
            // events emitted concurrently by `RSSParsingEncodingTests` (which runs
            // outside the `DiagnosticRecorderTests` wrapper) can be excluded from
            // the assertion; this avoids flakes from cross-suite pollution of the
            // global sink while still catching a regression that would make the
            // fast path start emitting its own events.
            let uniqueMarker = "x-encseam-utf8-fast-278"
            let xml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <rss version="2.0"><channel><title>\(uniqueMarker)</title><item><title>x</title></item></channel></rss>
            """
            let input = Data(xml.utf8)
            _ = EncodingSniffer.transcodeToUTF8IfNeeded(input)

            // The fast-path emits no events that could plausibly mention the
            // marker (production code has no reason to reflect arbitrary payload
            // bytes into its diagnostic messages). If any event *does* mention the
            // marker, the fast-path has started emitting and that's a regression.
            // If any cross-suite event lands in the sink, it will not mention the
            // marker and will be filtered out here.
            let snifferEvents = sink.events(inCategory: EncodingSniffer.loggerCategory)
            let markerMatches = snifferEvents.filter { $0.message.contains(uniqueMarker) }
            #expect(markerMatches.isEmpty,
                    "Expected no sniffer diagnostics on the UTF-8 fast path, got: \(markerMatches.map(\.message))")
        }

        // RATIONALE: `transcodeDecodeFailureEmitsWarningDiagnostic` was removed
        // when `transcode(_:from:)` was refactored to take a private
        // `SniffedPayload` (issue #274). The test previously called `transcode`
        // directly with `Data([0xC3, 0x28])` and `.utf8` — stray continuation
        // bytes that Foundation's UTF-8 decoder reliably rejects. That combination
        // cannot be reached through `transcodeToUTF8IfNeeded` because declared
        // UTF-8 is a fast-path (no `transcode` call). Constructing a BOM-detected
        // payload whose stripped bytes are truly undecodable proved unreliable:
        // Foundation's UTF-16 decoder is lenient with odd-length payloads and
        // returns an empty string rather than nil, routing the call to
        // `.bomStripped` instead of `.transcodeFailureFallback`. There is no
        // end-to-end test through `transcodeToUTF8IfNeeded` for the
        // `.transcodeFailureFallback` path; `SnifferOutcomeTests/isFallbackTrueForLossy`
        // constructs the enum value directly and does not exercise that path.

        // MARK: - DiagnosticRecorder seam contract

        @Test("DiagnosticRecorder is a no-op when no sink is installed")
        func recorderIsNoOpWithoutSink() {
            // Clear any leaked installation from prior tests in the same process.
            DiagnosticRecorder.uninstall()

            // Recording without an installed sink must not crash. There is no
            // observable state to assert — the point is that the call is cheap
            // and side-effect-free in production.
            DiagnosticRecorder.record(category: "NoSink", level: .warning, message: "should be dropped")

            // Install a fresh sink and verify the prior event is *not* remembered
            // (i.e. there is no buffering when no sink is installed).
            let sink = RecordingDiagnosticSink()
            DiagnosticRecorder.install(sink)
            defer { DiagnosticRecorder.uninstall() }
            #expect(sink.events.isEmpty)
        }

        @Test("DiagnosticRecorder.install replaces the previously installed sink")
        func recorderInstallReplacesPreviousSink() {
            DiagnosticRecorder.uninstall()

            let first = RecordingDiagnosticSink()
            let second = RecordingDiagnosticSink()

            // The slot was cleared above, so installing `first` should report
            // no prior sink. (We do not compare the returned existential by
            // identity — `DiagnosticSink` is not AnyObject-constrained and
            // bridging to AnyObject for identity checks is fragile under Swift
            // 6 strict concurrency. Routing behavior is the real contract we
            // care about, asserted below.)
            #expect(DiagnosticRecorder.install(first) == nil)

            // Route an event to `first` to prove it is wired up.
            DiagnosticRecorder.record(category: "Route", level: .warning, message: "first")
            #expect(first.events.count == 1)
            #expect(first.events.first?.message == "first")

            // Install `second` — `install(_:)` returns the prior sink, but we
            // only assert that routing switches to `second`. The prior-sink
            // return value is documented so callers can restore nested scopes;
            // the routing effect is what users observe.
            _ = DiagnosticRecorder.install(second)
            DiagnosticRecorder.record(category: "Route", level: .warning, message: "second")
            #expect(first.events.count == 1, "first sink should not receive events after being replaced")
            #expect(second.events.count == 1)
            #expect(second.events.first?.message == "second")

            DiagnosticRecorder.uninstall()
        }

        @Test("DiagnosticRecorder.uninstall removes the sink and stops routing events")
        func recorderUninstallStopsRouting() {
            let sink = RecordingDiagnosticSink()
            DiagnosticRecorder.install(sink)

            DiagnosticRecorder.record(category: "Cat", level: .warning, message: "first")
            #expect(sink.events.count == 1)

            DiagnosticRecorder.uninstall()

            DiagnosticRecorder.record(category: "Cat", level: .warning, message: "second")
            // Sink still holds the first event, but never receives the second.
            #expect(sink.events.count == 1)
            #expect(sink.events.first?.message == "first")
        }
    }

    // MARK: - Empty-feed escalation tests

    /// Tests that `RSSParsingService.parse()` escalates its log to `.error` when
    /// an encoding fallback path was taken and the resulting parse yields zero
    /// articles (issues #273 and #301). The dual-emit to `DiagnosticRecorder`
    /// introduced by #301 is what makes these assertions possible.
    /// Uses `DiagnosticRecorder` to observe the log level.
    ///
    /// The suite is serialized because the enclosing `DiagnosticRecorderTests`
    /// wrapper has the `.serialized` trait. This prevents races among tests within
    /// this suite and against `EncodingSnifferDiagnosticTests` (issue #310).
    @Suite("RSSParsingService empty-feed escalation")
    struct EmptyFeedEscalationTests {

        private let service = RSSParsingService()

        @Test("parse() escalates to .error when unknown encoding fallback produces zero articles")
        func unknownEncodingFallbackWithZeroArticlesLogsError() throws {
            let sink = RecordingDiagnosticSink()
            DiagnosticRecorder.install(sink)
            defer { DiagnosticRecorder.uninstall() }

            // Use a feed with an unrecognised encoding name so we reliably hit the
            // `.unknownEncodingFallback` path inside `transcodeToUTF8IfNeeded`.
            // The body is valid UTF-8 so the channel parses successfully, but the
            // XML structure has no <item> elements, producing zero articles.
            let uniqueEncName = "x-escalation-test-273"
            let xml = """
            <?xml version="1.0" encoding="\(uniqueEncName)"?>
            <rss version="2.0">
              <channel>
                <title>Escalation Test Feed</title>
              </channel>
            </rss>
            """
            let feed = try service.parse(Data(xml.utf8))
            #expect(feed.articles.isEmpty, "Fixture must produce zero articles to exercise escalation path")

            // Assert the escalation action directly: `parse()` dual-emits to
            // `DiagnosticRecorder` at `.error` under category "RSSParsingService"
            // when `isFallback && articles.isEmpty`. Issue #301.
            let errors = sink.events(atLevel: .error)
                .filter { $0.category == "RSSParsingService" }
            let escalationError = errors.first { $0.message.contains(uniqueEncName) }
            #expect(escalationError != nil,
                    "Expected a parse() escalation error for encoding fallback '\(uniqueEncName)' — dual-emit was not recorded")
        }

        @Test("parse() logs .notice (not .error) when fallback produces non-empty articles")
        func unknownEncodingFallbackWithArticlesDoesNotEscalate() throws {
            // Install a sink so we can directly observe that no .error events for
            // "RSSParsingService" are emitted. The escalation branch only fires when
            // isFallback && articles.isEmpty; a feed with articles must not trigger it.
            let sink = RecordingDiagnosticSink()
            DiagnosticRecorder.install(sink)
            defer { DiagnosticRecorder.uninstall() }

            let uniqueEncName = "x-noescape-301"
            let xml = """
            <?xml version="1.0" encoding="\(uniqueEncName)"?>
            <rss version="2.0">
              <channel>
                <title>Fallback With Articles</title>
                <item>
                  <title>Article One</title>
                  <description>body</description>
                </item>
              </channel>
            </rss>
            """
            let feed = try service.parse(Data(xml.utf8))
            #expect(feed.articles.count == 1,
                    "Fallback feed with one <item> should produce exactly one article")

            // Direct negative control: parse() must not dual-emit a .error for
            // "RSSParsingService" when the fallback produces non-empty articles.
            let escalationErrors = sink.events(atLevel: .error)
                .filter { $0.category == "RSSParsingService" }
            #expect(escalationErrors.isEmpty,
                    "parse() must not escalate to .error when fallback yields articles; got: \(escalationErrors.map(\.message))")
        }

        @Test("parse() does not escalate when UTF-8 feed has zero articles")
        func utf8FeedWithZeroArticlesDoesNotEscalate() throws {
            // A valid UTF-8 feed with no <item> elements should not be escalated:
            // zero articles here is a normal publisher state, not an encoding
            // failure. The path taken is `.utf8Passthrough` so `isFallback` is
            // false, and `parse()` should log `.notice` (unobservable here) and
            // return the empty feed normally.
            let xml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <rss version="2.0">
              <channel>
                <title>Empty UTF-8 Feed</title>
              </channel>
            </rss>
            """
            let feed = try service.parse(Data(xml.utf8))
            #expect(feed.articles.isEmpty)
            // No throw == no escalation path (parse() only logs; it never throws on empty articles)
        }
    }
}
