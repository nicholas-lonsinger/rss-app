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
        #expect(entries[0].groupName == nil)

        #expect(entries[1].title == "Feed Two")
        #expect(entries[1].feedURL == URL(string: "https://two.com/feed"))
        #expect(entries[1].siteURL == nil)
        #expect(entries[1].description == "Second feed")
        #expect(entries[1].groupName == nil)

        #expect(entries[2].title == "Feed Three")
        #expect(entries[2].feedURL == URL(string: "https://three.com/feed"))
        #expect(entries[2].siteURL == nil)
        #expect(entries[2].description == "")
        #expect(entries[2].groupName == nil)
    }

    @Test("parses nested OPML with category group names")
    func parsesNestedOPML() throws {
        let data = Data(TestFixtures.nestedOPML.utf8)
        let entries = try service.parseOPML(data)

        #expect(entries.count == 3)
        #expect(entries[0].title == "Ars Technica")
        #expect(entries[0].feedURL == URL(string: "https://arstechnica.com/feed"))
        #expect(entries[0].groupName == "Tech")
        #expect(entries[1].title == "The Verge")
        #expect(entries[1].groupName == "Tech")
        #expect(entries[2].title == "Top Level Feed")
        #expect(entries[2].groupName == nil)
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

    @Test("parses deeply nested outlines using nearest ancestor category")
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
        // Deeply nested feeds use the nearest (innermost) ancestor category.
        #expect(entries[0].groupName == "Level 2")
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
        let data = try service.generateOPML(from: [] as [SubscribedFeed])
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

    // MARK: - Grouped Parsing

    @Test("parses multiple categories with feeds in each")
    func parsesMultipleCategories() throws {
        let opml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <opml version="2.0">
              <head><title>Test</title></head>
              <body>
                <outline text="Tech">
                  <outline text="Ars" xmlUrl="https://ars.com/feed"/>
                </outline>
                <outline text="News">
                  <outline text="Reuters" xmlUrl="https://reuters.com/feed"/>
                  <outline text="AP" xmlUrl="https://ap.com/feed"/>
                </outline>
                <outline text="Ungrouped" xmlUrl="https://ungrouped.com/feed"/>
              </body>
            </opml>
            """
        let entries = try service.parseOPML(Data(opml.utf8))

        #expect(entries.count == 4)
        #expect(entries[0].title == "Ars")
        #expect(entries[0].groupName == "Tech")
        #expect(entries[1].title == "Reuters")
        #expect(entries[1].groupName == "News")
        #expect(entries[2].title == "AP")
        #expect(entries[2].groupName == "News")
        #expect(entries[3].title == "Ungrouped")
        #expect(entries[3].groupName == nil)
    }

    @Test("parses feed under multiple categories when duplicated")
    func parsesFeedUnderMultipleCategories() throws {
        let opml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <opml version="2.0">
              <head><title>Test</title></head>
              <body>
                <outline text="Tech">
                  <outline text="Multi Feed" xmlUrl="https://multi.com/feed"/>
                </outline>
                <outline text="Favorites">
                  <outline text="Multi Feed" xmlUrl="https://multi.com/feed"/>
                </outline>
              </body>
            </opml>
            """
        let entries = try service.parseOPML(Data(opml.utf8))

        // Feed appears once per category — two entries with different group names.
        #expect(entries.count == 2)
        #expect(entries[0].groupName == "Tech")
        #expect(entries[1].groupName == "Favorites")
        #expect(entries[0].feedURL == entries[1].feedURL)
    }

    @Test("category uses title attribute when text is missing")
    func categoryUsesTitleWhenTextMissing() throws {
        let opml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <opml version="2.0">
              <head><title>Test</title></head>
              <body>
                <outline title="My Category">
                  <outline text="Feed" xmlUrl="https://example.com/feed"/>
                </outline>
              </body>
            </opml>
            """
        let entries = try service.parseOPML(Data(opml.utf8))

        #expect(entries.count == 1)
        #expect(entries[0].groupName == "My Category")
    }

    @Test("empty category outline does not set group name")
    func emptyCategoryOutlineNoGroupName() throws {
        let opml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <opml version="2.0">
              <head><title>Test</title></head>
              <body>
                <outline>
                  <outline text="Feed" xmlUrl="https://example.com/feed"/>
                </outline>
              </body>
            </opml>
            """
        let entries = try service.parseOPML(Data(opml.utf8))

        #expect(entries.count == 1)
        // Category outline with no text/title attributes is skipped as a group.
        #expect(entries[0].groupName == nil)
    }

    @Test("category stack pops correctly after nested categories")
    func categoryStackPopsCorrectly() throws {
        let opml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <opml version="2.0">
              <head><title>Test</title></head>
              <body>
                <outline text="Category A">
                  <outline text="Feed A" xmlUrl="https://a.com/feed"/>
                </outline>
                <outline text="Category B">
                  <outline text="Feed B" xmlUrl="https://b.com/feed"/>
                </outline>
                <outline text="Feed C" xmlUrl="https://c.com/feed"/>
              </body>
            </opml>
            """
        let entries = try service.parseOPML(Data(opml.utf8))

        #expect(entries.count == 3)
        #expect(entries[0].groupName == "Category A")
        #expect(entries[1].groupName == "Category B")
        // Feed C is at top level after both categories have closed.
        #expect(entries[2].groupName == nil)
    }

    // MARK: - Grouped Generation

    @Test("generates OPML with category nesting for grouped feeds")
    func generatesGroupedOPML() throws {
        let groupedFeeds = [
            GroupedFeed(
                feed: TestFixtures.makeSubscribedFeed(title: "Tech Feed", url: URL(string: "https://tech.com/feed")!),
                groupNames: ["Tech"]
            ),
            GroupedFeed(
                feed: TestFixtures.makeSubscribedFeed(title: "News Feed", url: URL(string: "https://news.com/feed")!),
                groupNames: ["News"]
            ),
            GroupedFeed(
                feed: TestFixtures.makeSubscribedFeed(title: "Ungrouped Feed", url: URL(string: "https://ungrouped.com/feed")!),
                groupNames: []
            ),
        ]

        let data = try service.generateOPML(from: groupedFeeds)
        let xml = String(data: data, encoding: .utf8)!

        // Category outlines should exist.
        #expect(xml.contains("<outline text=\"News\">"))
        #expect(xml.contains("<outline text=\"Tech\">"))
        #expect(xml.contains("</outline>"))

        // Ungrouped feed should be at top level (not nested).
        // Verify by round-tripping.
        let entries = try service.parseOPML(data)
        #expect(entries.count == 3)

        let techEntry = entries.first { $0.feedURL == URL(string: "https://tech.com/feed") }
        let newsEntry = entries.first { $0.feedURL == URL(string: "https://news.com/feed") }
        let ungroupedEntry = entries.first { $0.feedURL == URL(string: "https://ungrouped.com/feed") }

        #expect(techEntry?.groupName == "Tech")
        #expect(newsEntry?.groupName == "News")
        #expect(ungroupedEntry?.groupName == nil)
    }

    @Test("generates OPML duplicating feeds in multiple groups")
    func generatesOPMLWithMultiGroupFeed() throws {
        let groupedFeeds = [
            GroupedFeed(
                feed: TestFixtures.makeSubscribedFeed(title: "Multi Feed", url: URL(string: "https://multi.com/feed")!),
                groupNames: ["Tech", "Favorites"]
            ),
        ]

        let data = try service.generateOPML(from: groupedFeeds)
        let entries = try service.parseOPML(data)

        // Feed should appear under both categories.
        #expect(entries.count == 2)
        let groupNames = Set(entries.compactMap(\.groupName))
        #expect(groupNames == ["Tech", "Favorites"])
    }

    @Test("grouped OPML round-trips through parser preserving categories")
    func groupedOPMLRoundTrip() throws {
        let groupedFeeds = [
            GroupedFeed(
                feed: TestFixtures.makeSubscribedFeed(title: "Feed A", url: URL(string: "https://a.com/feed")!, feedDescription: "First"),
                groupNames: ["Category X"]
            ),
            GroupedFeed(
                feed: TestFixtures.makeSubscribedFeed(title: "Feed B", url: URL(string: "https://b.com/feed")!, feedDescription: "Second"),
                groupNames: ["Category X"]
            ),
            GroupedFeed(
                feed: TestFixtures.makeSubscribedFeed(title: "Feed C", url: URL(string: "https://c.com/feed")!, feedDescription: ""),
                groupNames: []
            ),
        ]

        let data = try service.generateOPML(from: groupedFeeds)
        let entries = try service.parseOPML(data)

        #expect(entries.count == 3)
        #expect(entries[0].title == "Feed A")
        #expect(entries[0].groupName == "Category X")
        #expect(entries[0].description == "First")
        #expect(entries[1].title == "Feed B")
        #expect(entries[1].groupName == "Category X")
        #expect(entries[2].title == "Feed C")
        #expect(entries[2].groupName == nil)
    }

    @Test("generates categories in alphabetical order")
    func generatesCategoriesAlphabetically() throws {
        let groupedFeeds = [
            GroupedFeed(
                feed: TestFixtures.makeSubscribedFeed(title: "Z Feed", url: URL(string: "https://z.com/feed")!),
                groupNames: ["Zebra"]
            ),
            GroupedFeed(
                feed: TestFixtures.makeSubscribedFeed(title: "A Feed", url: URL(string: "https://a.com/feed")!),
                groupNames: ["Apple"]
            ),
        ]

        let data = try service.generateOPML(from: groupedFeeds)
        let xml = String(data: data, encoding: .utf8)!

        // Apple should appear before Zebra in the output.
        let appleIndex = xml.range(of: "Apple")!.lowerBound
        let zebraIndex = xml.range(of: "Zebra")!.lowerBound
        #expect(appleIndex < zebraIndex)
    }

    @Test("escapes XML special characters in category names")
    func escapesXMLInCategoryNames() throws {
        let groupedFeeds = [
            GroupedFeed(
                feed: TestFixtures.makeSubscribedFeed(title: "Feed", url: URL(string: "https://example.com/feed")!),
                groupNames: ["Tech & Science"]
            ),
        ]

        let data = try service.generateOPML(from: groupedFeeds)
        let xml = String(data: data, encoding: .utf8)!

        #expect(xml.contains("Tech &amp; Science"))

        // Verify round-trip preserves the name.
        let entries = try service.parseOPML(data)
        #expect(entries[0].groupName == "Tech & Science")
    }
}
