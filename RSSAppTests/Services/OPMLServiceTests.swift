import Testing
import Foundation
@testable import RSSApp

@Suite("OPMLService Tests")
struct OPMLServiceTests {

    private let service = OPMLService()

    // MARK: - Parsing

    @Test("parses simple flat OPML with three feeds")
    func parsesSimpleOPML() throws {
        let data = Data(TestFixtures.sampleOPML.utf8)
        let entries = try service.parseOPML(data)

        #expect(entries.count == 3)

        #expect(entries[0].title == "Feed One")
        #expect(entries[0].feedURL == URL(string: "https://one.com/feed"))
        #expect(entries[0].siteURL == URL(string: "https://one.com"))
        #expect(entries[0].description == "First feed")

        #expect(entries[1].title == "Feed Two")
        #expect(entries[1].feedURL == URL(string: "https://two.com/feed"))
        #expect(entries[1].siteURL == nil)
        #expect(entries[1].description == "Second feed")

        #expect(entries[2].title == "Feed Three")
        #expect(entries[2].feedURL == URL(string: "https://three.com/feed"))
        #expect(entries[2].siteURL == nil)
        #expect(entries[2].description == "")
    }

    @Test("parses nested OPML by flattening folders")
    func parsesNestedOPML() throws {
        let data = Data(TestFixtures.nestedOPML.utf8)
        let entries = try service.parseOPML(data)

        #expect(entries.count == 3)
        #expect(entries[0].title == "Ars Technica")
        #expect(entries[0].feedURL == URL(string: "https://arstechnica.com/feed"))
        #expect(entries[1].title == "The Verge")
        #expect(entries[2].title == "Top Level Feed")
    }

    @Test("skips outlines without xmlUrl")
    func skipsOutlinesWithoutXmlUrl() throws {
        let opml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <opml version="2.0">
              <head><title>Test</title></head>
              <body>
                <outline text="Just a folder"/>
                <outline text="Real Feed" xmlUrl="https://example.com/feed"/>
              </body>
            </opml>
            """
        let entries = try service.parseOPML(Data(opml.utf8))

        #expect(entries.count == 1)
        #expect(entries[0].title == "Real Feed")
    }

    @Test("uses feed URL as title when text attribute is missing")
    func usesFeedURLAsTitleWhenTextMissing() throws {
        let opml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <opml version="2.0">
              <head><title>Test</title></head>
              <body>
                <outline xmlUrl="https://example.com/feed"/>
              </body>
            </opml>
            """
        let entries = try service.parseOPML(Data(opml.utf8))

        #expect(entries.count == 1)
        #expect(entries[0].title == "https://example.com/feed")
    }

    @Test("falls back to title attribute when text is missing")
    func fallsBackToTitleAttribute() throws {
        let opml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <opml version="2.0">
              <head><title>Test</title></head>
              <body>
                <outline title="Title Attr Feed" xmlUrl="https://example.com/feed"/>
              </body>
            </opml>
            """
        let entries = try service.parseOPML(Data(opml.utf8))

        #expect(entries[0].title == "Title Attr Feed")
    }

    @Test("throws on malformed XML")
    func throwsOnMalformedXML() {
        let data = Data(TestFixtures.malformedOPML.utf8)

        #expect(throws: OPMLError.self) {
            try service.parseOPML(data)
        }
    }

    @Test("throws when no body element found")
    func throwsOnNoBody() {
        let data = Data(TestFixtures.noBodyOPML.utf8)

        #expect(throws: OPMLError.self) {
            try service.parseOPML(data)
        }
    }

    @Test("parses empty body and returns empty array")
    func parsesEmptyBody() throws {
        let data = Data(TestFixtures.emptyBodyOPML.utf8)
        let entries = try service.parseOPML(data)

        #expect(entries.isEmpty)
    }

    @Test("parses deeply nested outlines")
    func parsesDeeplyNestedOutlines() throws {
        let opml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <opml version="2.0">
              <head><title>Test</title></head>
              <body>
                <outline text="Level 1">
                  <outline text="Level 2">
                    <outline text="Deep Feed" xmlUrl="https://deep.com/feed"/>
                  </outline>
                </outline>
              </body>
            </opml>
            """
        let entries = try service.parseOPML(Data(opml.utf8))

        #expect(entries.count == 1)
        #expect(entries[0].title == "Deep Feed")
    }

    @Test("ignores outlines before body element")
    func ignoresOutlinesBeforeBody() throws {
        let opml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <opml version="2.0">
              <head>
                <outline text="Head Outline" xmlUrl="https://head.com/feed"/>
              </head>
              <body>
                <outline text="Body Feed" xmlUrl="https://body.com/feed"/>
              </body>
            </opml>
            """
        let entries = try service.parseOPML(Data(opml.utf8))

        #expect(entries.count == 1)
        #expect(entries[0].title == "Body Feed")
    }

    // MARK: - Generation

    @Test("generates valid OPML that round-trips through parser")
    func generatesValidRoundTrip() throws {
        let feeds = [
            TestFixtures.makeSubscribedFeed(
                title: "Feed A",
                url: URL(string: "https://a.com/feed")!,
                feedDescription: "First"
            ),
            TestFixtures.makeSubscribedFeed(
                title: "Feed B",
                url: URL(string: "https://b.com/feed")!,
                feedDescription: "Second"
            ),
        ]

        let data = try service.generateOPML(from: feeds)
        let entries = try service.parseOPML(data)

        #expect(entries.count == 2)
        #expect(entries[0].title == "Feed A")
        #expect(entries[0].feedURL == URL(string: "https://a.com/feed"))
        #expect(entries[0].description == "First")
        #expect(entries[1].title == "Feed B")
        #expect(entries[1].feedURL == URL(string: "https://b.com/feed"))
    }

    @Test("generates valid OPML from empty feed list")
    func generatesEmptyOPML() throws {
        let data = try service.generateOPML(from: [])
        let entries = try service.parseOPML(data)

        #expect(entries.isEmpty)
    }

    @Test("escapes XML special characters in generated output")
    func escapesXMLSpecialCharacters() throws {
        let feeds = [
            TestFixtures.makeSubscribedFeed(
                title: "Feed <A> & \"B\"",
                url: URL(string: "https://example.com/feed?a=1&b=2")!,
                feedDescription: "It's <special>"
            ),
        ]

        let data = try service.generateOPML(from: feeds)
        let xml = String(data: data, encoding: .utf8)!

        #expect(xml.contains("Feed &lt;A&gt; &amp; &quot;B&quot;"))
        #expect(xml.contains("It&apos;s &lt;special&gt;"))

        // Verify it still parses correctly
        let entries = try service.parseOPML(data)
        #expect(entries.count == 1)
        #expect(entries[0].title == "Feed <A> & \"B\"")
    }

    @Test("generated OPML has correct structure")
    func generatedOPMLHasCorrectStructure() throws {
        let feeds = [
            TestFixtures.makeSubscribedFeed(title: "Test"),
        ]

        let data = try service.generateOPML(from: feeds)
        let xml = String(data: data, encoding: .utf8)!

        #expect(xml.contains("<?xml version=\"1.0\" encoding=\"UTF-8\"?>"))
        #expect(xml.contains("<opml version=\"2.0\">"))
        #expect(xml.contains("<head>"))
        #expect(xml.contains("<title>RSS Subscriptions</title>"))
        #expect(xml.contains("<dateCreated>"))
        #expect(xml.contains("<body>"))
        #expect(xml.contains("type=\"rss\""))
        #expect(xml.contains("</opml>"))
    }

    @Test("omits description attribute when feed description is empty")
    func omitsEmptyDescription() throws {
        let feeds = [
            TestFixtures.makeSubscribedFeed(title: "No Desc", feedDescription: ""),
        ]

        let data = try service.generateOPML(from: feeds)
        let xml = String(data: data, encoding: .utf8)!

        #expect(!xml.contains("description="))
    }
}
