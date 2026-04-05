import Testing
import Foundation
@testable import RSSApp

@Suite("RSSParsingService Tests")
struct RSSParsingServiceTests {

    let service = RSSParsingService()

    // MARK: - Valid Parsing

    @Test("Parses valid RSS feed with correct channel info")
    func parsesChannelInfo() throws {
        let data = Data(TestFixtures.sampleRSSXML.utf8)
        let feed = try service.parse(data)

        #expect(feed.title == "Test Feed")
        #expect(feed.link?.absoluteString == "https://example.com")
        #expect(feed.feedDescription == "A test RSS feed")
    }

    @Test("Parses correct number of articles")
    func parsesArticleCount() throws {
        let data = Data(TestFixtures.sampleRSSXML.utf8)
        let feed = try service.parse(data)

        #expect(feed.articles.count == 3)
    }

    @Test("Parses article title, link, and guid")
    func parsesArticleBasicFields() throws {
        let data = Data(TestFixtures.sampleRSSXML.utf8)
        let feed = try service.parse(data)
        let article = feed.articles[0]

        #expect(article.title == "First Article")
        #expect(article.link?.absoluteString == "https://example.com/article-1")
        #expect(article.id == "article-1-guid")
    }

    @Test("Parses pubDate correctly")
    func parsesPubDate() throws {
        let data = Data(TestFixtures.sampleRSSXML.utf8)
        let feed = try service.parse(data)

        #expect(feed.articles[0].publishedDate != nil)
        #expect(feed.articles[1].publishedDate != nil)
    }

    @Test("Generates snippet from HTML description")
    func generatesSnippet() throws {
        let data = Data(TestFixtures.sampleRSSXML.utf8)
        let feed = try service.parse(data)
        let snippet = feed.articles[0].snippet

        #expect(!snippet.contains("<p>"))
        #expect(!snippet.contains("<b>"))
        #expect(snippet.contains("first"))
    }

    @Test("Stores raw description including HTML")
    func storesRawDescription() throws {
        let data = Data(TestFixtures.sampleRSSXML.utf8)
        let feed = try service.parse(data)

        #expect(feed.articles[0].articleDescription.contains("<p>"))
    }

    // MARK: - Thumbnail Extraction

    @Test("Extracts thumbnail from media:thumbnail")
    func mediaThumbnail() throws {
        let data = Data(TestFixtures.sampleRSSXML.utf8)
        let feed = try service.parse(data)

        #expect(feed.articles[0].thumbnailURL?.absoluteString == "https://example.com/thumb1.jpg")
    }

    @Test("Extracts thumbnail from enclosure with image type")
    func enclosureThumbnail() throws {
        let data = Data(TestFixtures.sampleRSSXML.utf8)
        let feed = try service.parse(data)

        #expect(feed.articles[1].thumbnailURL?.absoluteString == "https://example.com/enclosure.jpg")
    }

    @Test("Falls back to img in description for thumbnail")
    func imgFallbackThumbnail() throws {
        let data = Data(TestFixtures.sampleRSSXML.utf8)
        let feed = try service.parse(data)

        #expect(feed.articles[2].thumbnailURL?.absoluteString == "https://example.com/body-img.jpg")
    }

    @Test("Extracts thumbnail from media:content with image medium")
    func mediaContentThumbnail() throws {
        let data = Data(TestFixtures.mediaContentXML.utf8)
        let feed = try service.parse(data)

        #expect(feed.articles[0].thumbnailURL?.absoluteString == "https://example.com/media-img.jpg")
    }

    @Test("media:thumbnail takes priority over enclosure and img")
    func thumbnailPriority() throws {
        let data = Data(TestFixtures.thumbnailPriorityXML.utf8)
        let feed = try service.parse(data)

        #expect(feed.articles[0].thumbnailURL?.absoluteString == "https://example.com/thumb.jpg")
    }

    @Test("Article with no images has nil thumbnailURL")
    func noImagesThumbnailNil() throws {
        let data = Data(TestFixtures.sampleRSSXMLNoImages.utf8)
        let feed = try service.parse(data)

        #expect(feed.articles[0].thumbnailURL == nil)
    }

    // MARK: - ID Derivation

    @Test("Uses guid as article ID when present")
    func idFromGuid() throws {
        let data = Data(TestFixtures.sampleRSSXML.utf8)
        let feed = try service.parse(data)

        #expect(feed.articles[0].id == "article-1-guid")
    }

    @Test("Falls back to link for ID when no guid")
    func idFromLink() throws {
        let data = Data(TestFixtures.sampleRSSXML.utf8)
        let feed = try service.parse(data)

        // Third article has no guid
        #expect(feed.articles[2].id == "https://example.com/article-3")
    }

    @Test("RSS guid takes precedence over Atom id in hybrid entry")
    func guidPrecedenceOverAtomId() throws {
        let xml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <rss version="2.0" xmlns:atom="http://www.w3.org/2005/Atom">
            <channel>
                <title>Hybrid Feed</title>
                <link>https://example.com</link>
                <description>A feed with both guid and id</description>
                <item>
                    <title>Hybrid Entry</title>
                    <guid>urn:guid-value</guid>
                    <id>urn:id-value</id>
                    <link>https://example.com/hybrid</link>
                </item>
            </channel>
            </rss>
            """
        let data = Data(xml.utf8)
        let feed = try service.parse(data)

        #expect(feed.articles[0].id == "urn:guid-value")
    }

    // MARK: - Edge Cases

    @Test("Parses empty channel with no articles")
    func emptyChannel() throws {
        let data = Data(TestFixtures.emptyChannelXML.utf8)
        let feed = try service.parse(data)

        #expect(feed.title == "Empty Feed")
        #expect(feed.articles.isEmpty)
    }

    @Test("Throws on malformed XML")
    func malformedXMLThrows() {
        let data = Data(TestFixtures.malformedXML.utf8)

        #expect(throws: RSSParsingError.self) {
            try service.parse(data)
        }
    }

    @Test("Throws on empty data")
    func emptyDataThrows() {
        let data = Data()

        #expect(throws: (any Error).self) {
            try service.parse(data)
        }
    }

    @Test("Article with missing optional fields uses defaults")
    func missingOptionalFields() throws {
        let xml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <rss version="2.0">
            <channel>
                <title>Minimal</title>
                <link>https://example.com</link>
                <description>Minimal feed</description>
                <item>
                    <title>Minimal Item</title>
                </item>
            </channel>
            </rss>
            """
        let data = Data(xml.utf8)
        let feed = try service.parse(data)

        let article = feed.articles[0]
        #expect(article.title == "Minimal Item")
        #expect(article.link == nil)
        #expect(article.publishedDate == nil)
        #expect(article.thumbnailURL == nil)
    }

    @Test("Article with empty title defaults to Untitled")
    func emptyTitleDefaultsToUntitled() throws {
        let xml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <rss version="2.0">
            <channel>
                <title>Feed</title>
                <link>https://example.com</link>
                <description>Feed</description>
                <item>
                    <title></title>
                    <link>https://example.com/empty-title</link>
                </item>
            </channel>
            </rss>
            """
        let data = Data(xml.utf8)
        let feed = try service.parse(data)

        #expect(feed.articles[0].title == "Untitled")
    }

    @Test("Decodes HTML entities in CDATA article titles")
    func decodesHTMLEntitiesInCDATATitle() throws {
        let xml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <rss version="2.0">
            <channel>
                <title>Test Feed</title>
                <link>https://example.com</link>
                <description>Feed</description>
                <item>
                    <title><![CDATA[Los Thuthanaka&#8217;s Wak&#8217;a is great]]></title>
                    <link>https://example.com/article</link>
                </item>
            </channel>
            </rss>
            """
        let data = Data(xml.utf8)
        let feed = try service.parse(data)

        #expect(feed.articles[0].title == "Los Thuthanaka\u{2019}s Wak\u{2019}a is great")
    }

    // MARK: - Atom Feed Parsing

    @Test("Parses valid Atom feed with correct channel info")
    func parsesAtomChannelInfo() throws {
        let data = Data(TestFixtures.sampleAtomXML.utf8)
        let feed = try service.parse(data)

        #expect(feed.title == "Atom Test Feed")
        #expect(feed.link?.absoluteString == "https://example.com")
        #expect(feed.feedDescription == "A test Atom feed description")
    }

    @Test("Parses correct number of Atom entries")
    func parsesAtomEntryCount() throws {
        let data = Data(TestFixtures.sampleAtomXML.utf8)
        let feed = try service.parse(data)

        #expect(feed.articles.count == 2)
    }

    @Test("Parses Atom entry title, link, and ID")
    func parsesAtomEntryBasicFields() throws {
        let data = Data(TestFixtures.sampleAtomXML.utf8)
        let feed = try service.parse(data)
        let entry = feed.articles[0]

        #expect(entry.title == "First Atom Entry")
        #expect(entry.link?.absoluteString == "https://example.com/entry-1")
        #expect(entry.id == "entry-1-id")
    }

    @Test("Parses Atom published date with timezone offset")
    func parsesAtomPublishedDate() throws {
        let data = Data(TestFixtures.sampleAtomXML.utf8)
        let feed = try service.parse(data)

        #expect(feed.articles[0].publishedDate != nil)
        #expect(feed.articles[1].publishedDate != nil)
    }

    @Test("Atom content element overrides summary")
    func atomContentOverridesSummary() throws {
        let data = Data(TestFixtures.sampleAtomXML.utf8)
        let feed = try service.parse(data)
        let entry = feed.articles[0]

        #expect(entry.articleDescription.contains("Full content"))
        #expect(!entry.articleDescription.contains("Short summary"))
    }

    @Test("Atom summary used when no content element")
    func atomSummaryUsedWithoutContent() throws {
        let data = Data(TestFixtures.sampleAtomXML.utf8)
        let feed = try service.parse(data)
        let entry = feed.articles[1]

        #expect(entry.articleDescription.contains("Summary only"))
    }

    @Test("Atom entry extracts thumbnail from content HTML")
    func atomThumbnailFromContent() throws {
        let data = Data(TestFixtures.sampleAtomXML.utf8)
        let feed = try service.parse(data)

        #expect(feed.articles[0].thumbnailURL?.absoluteString == "https://example.com/img1.jpg")
    }

    @Test("Atom feed uses alternate link, not self link")
    func atomAlternateLinkOnly() throws {
        let data = Data(TestFixtures.sampleAtomXML.utf8)
        let feed = try service.parse(data)

        #expect(feed.link?.absoluteString == "https://example.com")
    }

    @Test("Atom feed with only rel=self link produces nil feed link")
    func atomSelfLinkOnly() throws {
        let data = Data(TestFixtures.atomSelfLinkOnlyXML.utf8)
        let feed = try service.parse(data)

        #expect(feed.link == nil)
        #expect(feed.title == "Self Link Only Feed")
        #expect(feed.articles.count == 1)
    }

    @Test("Atom feed with no subtitle has empty description")
    func atomNoSubtitle() throws {
        let data = Data(TestFixtures.atomNoContentXML.utf8)
        let feed = try service.parse(data)

        #expect(feed.feedDescription.isEmpty)
    }

    @Test("Atom entry with plain text summary generates snippet")
    func atomPlainTextSnippet() throws {
        let data = Data(TestFixtures.atomNoContentXML.utf8)
        let feed = try service.parse(data)

        #expect(feed.articles[0].snippet == "Plain text summary with no HTML")
    }

    @Test("Atom entry uses updated date when published is absent")
    func atomUpdatedDateFallback() throws {
        let data = Data(TestFixtures.atomNoContentXML.utf8)
        let feed = try service.parse(data)

        #expect(feed.articles[0].publishedDate != nil)

        // Verify exact date to catch timezone-offset inversions
        let calendar = Calendar(identifier: .gregorian)
        let components = calendar.dateComponents(
            in: TimeZone(identifier: "UTC")!,
            from: feed.articles[0].publishedDate!
        )
        #expect(components.year == 2026)
        #expect(components.month == 4)
        #expect(components.day == 1)
    }

    @Test("Atom feed-level updated date is parsed")
    func atomFeedUpdatedDate() throws {
        let data = Data(TestFixtures.sampleAtomXML.utf8)
        let feed = try service.parse(data)

        #expect(feed.lastUpdated != nil)
    }

    @Test("Atom entry author name is extracted")
    func atomEntryAuthor() throws {
        let data = Data(TestFixtures.sampleAtomXML.utf8)
        let feed = try service.parse(data)

        #expect(feed.articles[0].author == "Alice")
        #expect(feed.articles[1].author == "Bob")
    }

    // MARK: - XHTML Content

    @Test("Atom XHTML content is reconstructed as HTML")
    func atomXHTMLContentReconstruction() throws {
        let data = Data(TestFixtures.atomXHTMLContentXML.utf8)
        let feed = try service.parse(data)
        let entry = feed.articles[0]

        #expect(entry.articleDescription.contains("<p>"))
        #expect(entry.articleDescription.contains("<b>bold</b>"))
        #expect(entry.articleDescription.contains("<em>italic</em>"))
        #expect(!entry.articleDescription.isEmpty)
    }

    @Test("Atom XHTML void elements use self-closing tags")
    func atomXHTMLVoidElements() throws {
        let data = Data(TestFixtures.atomXHTMLContentXML.utf8)
        let feed = try service.parse(data)
        let entry = feed.articles[0]

        #expect(entry.articleDescription.contains("<img "))
        #expect(entry.articleDescription.contains(" />"))
        #expect(!entry.articleDescription.contains("</img>"))
        #expect(!entry.articleDescription.contains("</br>"))
    }

    @Test("Atom XHTML content extracts thumbnail from img tag")
    func atomXHTMLThumbnail() throws {
        let data = Data(TestFixtures.atomXHTMLContentXML.utf8)
        let feed = try service.parse(data)

        #expect(feed.articles[0].thumbnailURL?.absoluteString == "https://example.com/xhtml-img.jpg")
    }

    @Test("Atom XHTML summary used as fallback")
    func atomXHTMLSummaryFallback() throws {
        let data = Data(TestFixtures.atomXHTMLContentXML.utf8)
        let feed = try service.parse(data)
        let entry = feed.articles[1]

        #expect(entry.articleDescription.contains("Summary in XHTML format"))
    }

    @Test("Atom XHTML content overrides XHTML summary")
    func atomXHTMLContentOverridesSummary() throws {
        let data = Data(TestFixtures.atomXHTMLContentXML.utf8)
        let feed = try service.parse(data)
        let entry = feed.articles[2]

        #expect(entry.articleDescription.contains("Content wins over summary"))
        #expect(!entry.articleDescription.contains("Should be ignored"))
    }

    @Test("Atom XHTML text nodes are HTML-escaped in reconstruction")
    func atomXHTMLTextEscaping() throws {
        let xml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <feed xmlns="http://www.w3.org/2005/Atom">
                <title>Escape Feed</title>
                <link rel="alternate" href="https://example.com" />
                <id>https://example.com/escape-feed</id>
                <updated>2026-04-01T00:00:00Z</updated>
                <entry>
                    <title>Escape Entry</title>
                    <link rel="alternate" href="https://example.com/escape" />
                    <id>escape-entry</id>
                    <content type="xhtml">
                        <div xmlns="http://www.w3.org/1999/xhtml">
                            <p>Tom &amp; Jerry</p>
                        </div>
                    </content>
                </entry>
            </feed>
            """
        let data = Data(xml.utf8)
        let feed = try service.parse(data)
        let entry = feed.articles[0]

        // The reconstructed HTML must re-escape the ampersand
        #expect(entry.articleDescription.contains("&amp;"))
        #expect(!entry.articleDescription.contains("Tom & Jerry"))
    }

    @Test("Atom XHTML content generates non-empty snippet")
    func atomXHTMLSnippet() throws {
        let data = Data(TestFixtures.atomXHTMLContentXML.utf8)
        let feed = try service.parse(data)
        let entry = feed.articles[0]

        #expect(entry.snippet.contains("bold"))
        #expect(entry.snippet.contains("italic"))
        #expect(!entry.snippet.contains("<"))
    }

    @Test("Atom deeply nested XHTML is reconstructed correctly")
    func atomXHTMLDeeplyNested() throws {
        let xml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <feed xmlns="http://www.w3.org/2005/Atom">
                <title>Nested XHTML Feed</title>
                <link rel="alternate" href="https://example.com" />
                <id>https://example.com/nested</id>
                <updated>2026-04-01T00:00:00Z</updated>
                <entry>
                    <title>Nested Entry</title>
                    <link rel="alternate" href="https://example.com/nested-1" />
                    <id>nested-entry-1</id>
                    <content type="xhtml">
                        <div xmlns="http://www.w3.org/1999/xhtml">
                            <div><ul><li>Item one</li><li>Item two</li></ul></div>
                        </div>
                    </content>
                </entry>
            </feed>
            """
        let data = Data(xml.utf8)
        let feed = try service.parse(data)
        let entry = feed.articles[0]

        #expect(entry.articleDescription.contains("<div><ul><li>Item one</li><li>Item two</li></ul></div>"))
    }

    @Test("Atom empty XHTML content produces empty description")
    func atomXHTMLEmptyContent() throws {
        let xml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <feed xmlns="http://www.w3.org/2005/Atom">
                <title>Empty XHTML Feed</title>
                <link rel="alternate" href="https://example.com" />
                <id>https://example.com/empty-xhtml</id>
                <updated>2026-04-01T00:00:00Z</updated>
                <entry>
                    <title>Empty Entry</title>
                    <link rel="alternate" href="https://example.com/empty-1" />
                    <id>empty-xhtml-entry</id>
                    <content type="xhtml">
                        <div xmlns="http://www.w3.org/1999/xhtml">
                        </div>
                    </content>
                </entry>
            </feed>
            """
        let data = Data(xml.utf8)
        let feed = try service.parse(data)
        let entry = feed.articles[0]

        #expect(entry.articleDescription.isEmpty)
    }

    @Test("Atom XHTML attributes with special characters are escaped")
    func atomXHTMLAttributeEscaping() throws {
        let xml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <feed xmlns="http://www.w3.org/2005/Atom">
                <title>Attribute Escape Feed</title>
                <link rel="alternate" href="https://example.com" />
                <id>https://example.com/attr-escape</id>
                <updated>2026-04-01T00:00:00Z</updated>
                <entry>
                    <title>Attribute Entry</title>
                    <link rel="alternate" href="https://example.com/attr-1" />
                    <id>attr-escape-entry</id>
                    <content type="xhtml">
                        <div xmlns="http://www.w3.org/1999/xhtml">
                            <a href="https://example.com?a=1&amp;b=2" title="Tom &amp; Jerry">Link</a>
                        </div>
                    </content>
                </entry>
            </feed>
            """
        let data = Data(xml.utf8)
        let feed = try service.parse(data)
        let entry = feed.articles[0]

        #expect(entry.articleDescription.contains("href=\"https://example.com?a=1&amp;b=2\""))
        #expect(entry.articleDescription.contains("title=\"Tom &amp; Jerry\""))
    }

    // MARK: - Categories

    @Test("Atom category term attributes are extracted")
    func atomCategoryTerms() throws {
        let data = Data(TestFixtures.atomCategoriesXML.utf8)
        let feed = try service.parse(data)
        let entry = feed.articles[0]

        #expect(entry.categories == ["swift", "ios", "development"])
    }

    @Test("Atom category with term attribute and text content is not double-counted")
    func atomCategoryDoubleCountPrevention() throws {
        let data = Data(TestFixtures.atomCategoryDoubleCountXML.utf8)
        let feed = try service.parse(data)
        let entry = feed.articles[0]

        #expect(entry.categories == ["tech", "swift"])
        #expect(entry.categories.count == 2)
    }

    @Test("RSS category text content is extracted")
    func rssCategoryText() throws {
        let data = Data(TestFixtures.rssCategoriesXML.utf8)
        let feed = try service.parse(data)
        let article = feed.articles[0]

        #expect(article.categories == ["technology", "programming"])
    }

    // MARK: - Atom Enclosure Links

    @Test("Atom link rel=enclosure extracts image thumbnail")
    func atomEnclosureLink() throws {
        let data = Data(TestFixtures.atomEnclosureLinkXML.utf8)
        let feed = try service.parse(data)

        #expect(feed.articles[0].thumbnailURL?.absoluteString == "https://example.com/enclosure-img.png")
    }

    // MARK: - RSS Author

    @Test("RSS author element is extracted")
    func rssAuthor() throws {
        let data = Data(TestFixtures.rssAuthorXML.utf8)
        let feed = try service.parse(data)

        #expect(feed.articles[0].author == "jane@example.com (Jane Doe)")
    }

    // MARK: - RSS lastBuildDate

    @Test("RSS lastBuildDate is parsed as lastUpdated")
    func rssLastBuildDate() throws {
        let data = Data(TestFixtures.rssLastBuildDateXML.utf8)
        let feed = try service.parse(data)

        #expect(feed.lastUpdated != nil)
    }

    // MARK: - Articles default to nil author and empty categories

    @Test("Articles without author or categories have default values")
    func defaultAuthorAndCategories() throws {
        let data = Data(TestFixtures.sampleRSSXML.utf8)
        let feed = try service.parse(data)

        #expect(feed.articles[0].author == nil)
        #expect(feed.articles[0].categories.isEmpty)
    }

    // MARK: - Snippet Truncation

    // MARK: - Channel Image / Logo

    @Test("RSS channel <image><url> is extracted as imageURL")
    func rssChannelImage() throws {
        let data = Data(TestFixtures.rssWithImageXML.utf8)
        let feed = try service.parse(data)

        #expect(feed.imageURL?.absoluteString == "https://example.com/logo.png")
    }

    @Test("Atom <logo> is extracted as imageURL")
    func atomLogo() throws {
        let data = Data(TestFixtures.atomWithLogoXML.utf8)
        let feed = try service.parse(data)

        #expect(feed.imageURL?.absoluteString == "https://example.com/atom-logo.png")
    }

    @Test("Atom <icon> is extracted as imageURL when no logo")
    func atomIconFallback() throws {
        let data = Data(TestFixtures.atomWithIconXML.utf8)
        let feed = try service.parse(data)

        #expect(feed.imageURL?.absoluteString == "https://example.com/favicon.ico")
    }

    @Test("Atom <logo> takes priority over <icon>")
    func atomLogoPriorityOverIcon() throws {
        let data = Data(TestFixtures.atomWithLogoAndIconXML.utf8)
        let feed = try service.parse(data)

        #expect(feed.imageURL?.absoluteString == "https://example.com/atom-logo.png")
    }

    @Test("Feed without channel image has nil imageURL")
    func noChannelImage() throws {
        let data = Data(TestFixtures.sampleRSSXML.utf8)
        let feed = try service.parse(data)

        #expect(feed.imageURL == nil)
    }

    // MARK: - Snippet Truncation

    @Test("Truncates long snippets with ellipsis")
    func longSnippetTruncation() throws {
        let longText = String(repeating: "A", count: 300)
        let xml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <rss version="2.0">
            <channel>
                <title>Feed</title>
                <link>https://example.com</link>
                <description>Feed</description>
                <item>
                    <title>Long</title>
                    <description>\(longText)</description>
                </item>
            </channel>
            </rss>
            """
        let data = Data(xml.utf8)
        let feed = try service.parse(data)

        let snippet = feed.articles[0].snippet
        #expect(snippet.count <= RSSParsingService.snippetMaxLength + 1) // +1 for ellipsis
        #expect(snippet.hasSuffix("…"))
    }
}
