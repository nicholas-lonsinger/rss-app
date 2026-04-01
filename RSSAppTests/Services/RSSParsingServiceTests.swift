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
