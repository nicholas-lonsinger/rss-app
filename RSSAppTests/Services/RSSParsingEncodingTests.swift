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

    // MARK: - Graceful degradation

    @Test("Unknown encoding name falls through to raw bytes (no crash)")
    func unknownEncodingNameDoesNotCrash() throws {
        // Unknown charset name — sniffer should give up and pass bytes through.
        // Content is actually UTF-8 so XMLParser handles it fine.
        let xml = """
        <?xml version="1.0" encoding="x-obviously-fake-encoding"?>
        <rss version="2.0"><channel><title>fallback</title><item><title>x</title></item></channel></rss>
        """
        let feed = try service.parse(Data(xml.utf8))
        #expect(feed.title == "fallback")
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
}
