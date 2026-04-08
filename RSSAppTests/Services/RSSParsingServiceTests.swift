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

    @Test("Decodes HTML entities in CDATA channel title")
    func decodesHTMLEntitiesInCDATAChannelTitle() throws {
        let xml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <rss version="2.0">
            <channel>
                <title><![CDATA[Tom&#8217;s Feed]]></title>
                <link>https://example.com</link>
                <description>Feed</description>
                <item>
                    <title>Article</title>
                    <link>https://example.com/article</link>
                </item>
            </channel>
            </rss>
            """
        let data = Data(xml.utf8)
        let feed = try service.parse(data)

        #expect(feed.title == "Tom\u{2019}s Feed")
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

    // MARK: - Update Detection Signals (issue #74)
    //
    // These tests pin down the parser's handling of `<updated>` and equivalent
    // namespaced modification timestamps as first-class signals (separate from
    // the publication date) that the persistence layer uses to detect when a
    // publisher has revised an article.

    @Test("Atom entry with both <published> and <updated> populates publishedDate from <published> and updatedDate from <updated>")
    func atomDistinctPublishedAndUpdated() throws {
        let data = Data(TestFixtures.sampleAtomXML.utf8)
        let feed = try service.parse(data)

        // sampleAtomXML's first entry has:
        //   <published>2026-04-01T10:00:00-04:00</published>
        //   <updated>2026-04-01T11:00:00-04:00</updated>
        let entry = feed.articles[0]
        #expect(entry.publishedDate != nil)
        #expect(entry.updatedDate != nil)
        #expect(entry.publishedDate != entry.updatedDate)
        // The updated timestamp should be one hour after published.
        if let published = entry.publishedDate, let updated = entry.updatedDate {
            #expect(updated.timeIntervalSince(published) == 3600)
        }
    }

    @Test("Atom entry with only <updated> populates both publishedDate and updatedDate from it")
    func atomUpdatedOnlyFallback() throws {
        let data = Data(TestFixtures.atomUpdatedOnlyXML.utf8)
        let feed = try service.parse(data)

        let entry = feed.articles[0]
        #expect(entry.publishedDate != nil)
        #expect(entry.updatedDate != nil)
        // The fallback path should set both fields to the same parsed value.
        #expect(entry.publishedDate == entry.updatedDate)
    }

    @Test("RSS item with only <pubDate> has nil updatedDate")
    func rssPubDateOnlyHasNilUpdatedDate() throws {
        let data = Data(TestFixtures.sampleRSSXML.utf8)
        let feed = try service.parse(data)

        // None of the items in sampleRSSXML carry any update signal.
        for article in feed.articles {
            #expect(article.publishedDate != nil)
            #expect(article.updatedDate == nil)
        }
    }

    @Test("RSS item with <dc:modified> populates updatedDate distinctly from publishedDate")
    func rssDcModifiedPopulatesUpdatedDate() throws {
        let data = Data(TestFixtures.rssWithDcModifiedXML.utf8)
        let feed = try service.parse(data)

        let item = feed.articles[0]
        #expect(item.publishedDate != nil)
        #expect(item.updatedDate != nil)
        #expect(item.publishedDate != item.updatedDate)
        // dc:modified is 2026-04-01, pubDate is 2026-03-30, so updated > published.
        if let published = item.publishedDate, let updated = item.updatedDate {
            #expect(updated > published)
        }
    }

    @Test("RSS item with <dcterms:modified> populates updatedDate")
    func rssDctermsModifiedPopulatesUpdatedDate() throws {
        let data = Data(TestFixtures.rssWithDctermsModifiedXML.utf8)
        let feed = try service.parse(data)

        let item = feed.articles[0]
        #expect(item.publishedDate != nil)
        #expect(item.updatedDate != nil)
        #expect(item.publishedDate != item.updatedDate)
    }

    @Test("RSS item with <atom:updated> embedded via xmlns:atom populates updatedDate")
    func rssAtomUpdatedPopulatesUpdatedDate() throws {
        let data = Data(TestFixtures.rssWithAtomUpdatedXML.utf8)
        let feed = try service.parse(data)

        let item = feed.articles[0]
        #expect(item.publishedDate != nil)
        #expect(item.updatedDate != nil)
        #expect(item.publishedDate != item.updatedDate)
    }

    @Test("RSS item with only <dc:date> populates publishedDate but not updatedDate")
    func rssDcDateIsPublicationFallbackOnly() throws {
        let data = Data(TestFixtures.rssWithDcDateOnlyXML.utf8)
        let feed = try service.parse(data)

        let item = feed.articles[0]
        // dc:date is a publication signal, not an update signal — should populate
        // publishedDate via the fallback chain and leave updatedDate nil.
        #expect(item.publishedDate != nil)
        #expect(item.updatedDate == nil)
    }

    @Test("RSS <pubDate> takes precedence over <dc:date> for publishedDate")
    func rssPubDatePrecedesDcDate() throws {
        let data = Data(TestFixtures.rssWithPubDateAndDcDateXML.utf8)
        let feed = try service.parse(data)

        let item = feed.articles[0]
        #expect(item.publishedDate != nil)
        #expect(item.updatedDate == nil)

        // pubDate is 2026-03-30; dc:date is 2020-01-01. The parsed publishedDate
        // must be the 2026 value, not the 2020 fallback.
        let calendar = Calendar(identifier: .gregorian)
        let year = calendar.component(.year, from: item.publishedDate!)
        #expect(year == 2026)
    }

    @Test("RSS <pubDate> wins over <dc:date> regardless of source-document order")
    func rssPubDatePrecedenceIsOrderIndependent() throws {
        // Same precedence rule as `rssPubDatePrecedesDcDate`, but with the elements
        // in the opposite source order: <dc:date> appears BEFORE <pubDate>. The
        // precedence is enforced by `<pubDate>` setting `itemPubDate` unconditionally,
        // not by switch-arm ordering, so the order in the XML must not matter.
        let data = Data(TestFixtures.rssWithDcDateBeforePubDateXML.utf8)
        let feed = try service.parse(data)

        let item = feed.articles[0]
        #expect(item.publishedDate != nil)
        #expect(item.updatedDate == nil)

        let calendar = Calendar(identifier: .gregorian)
        let year = calendar.component(.year, from: item.publishedDate!)
        #expect(year == 2026)
    }

    @Test("RSS item with only <dcterms:created> populates publishedDate but not updatedDate")
    func rssDctermsCreatedIsPublicationFallbackOnly() throws {
        // dcterms:created is grouped with dc:date in a single switch case in the parser.
        // Without this dedicated test, a future refactor that splits the case (e.g., to
        // give dcterms:created different precedence) would have zero coverage signal.
        let data = Data(TestFixtures.rssWithDctermsCreatedOnlyXML.utf8)
        let feed = try service.parse(data)

        let item = feed.articles[0]
        #expect(item.publishedDate != nil)
        #expect(item.updatedDate == nil)
    }

    @Test("Unparseable <dc:modified> yields nil updatedDate without poisoning publishedDate")
    func malformedUpdatedDateYieldsNil() throws {
        // Pins the parseDate-returns-nil contract for the new updatedDate code path.
        // If parseDate ever changed its nil-handling (e.g., started returning
        // Date.distantPast for unparseable input), every article in every feed would
        // suddenly look "updated" forever.
        let data = Data(TestFixtures.rssWithMalformedDcModifiedXML.utf8)
        let feed = try service.parse(data)

        let item = feed.articles[0]
        // pubDate must still resolve normally — the failed updatedDate parse must not
        // contaminate the rest of the item.
        #expect(item.publishedDate != nil)
        // Garbage modification timestamp must yield nil, not an unintended fallback.
        #expect(item.updatedDate == nil)
    }

    @Test("Implausibly old <dc:modified> is rejected by sanity check and yields nil updatedDate")
    func implausiblyOldUpdatedDateRejected() throws {
        // The parser's parseDate rejects pre-1990 dates via sanityChecked. This pins
        // that the rejection path applies to the new updatedDate code path too — without
        // it, a refactor that switches sanityChecked to clamp instead of reject would
        // silently start firing update detection for any feed with a malformed pre-1990
        // timestamp.
        let xml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <rss version="2.0" xmlns:dc="http://purl.org/dc/elements/1.1/">
            <channel>
                <title>Old Modified</title>
                <link>https://example.com</link>
                <description>desc</description>
                <item>
                    <title>Item</title>
                    <link>https://example.com/old</link>
                    <description>d</description>
                    <guid>old-modified</guid>
                    <pubDate>Mon, 30 Mar 2026 12:00:00 +0000</pubDate>
                    <dc:modified>1985-01-01T00:00:00Z</dc:modified>
                </item>
            </channel>
            </rss>
            """
        let feed = try service.parse(Data(xml.utf8))

        #expect(feed.articles[0].publishedDate != nil)
        #expect(feed.articles[0].updatedDate == nil)
    }

    @Test("itemUpdatedDate accumulator resets between sibling items")
    func updatedDateAccumulatorResetsBetweenItems() throws {
        // The parser uses an instance-level accumulator for itemUpdatedDate that must
        // be reset on each <item>/<entry> start. Without the reset, an item with no
        // update signal would silently inherit the previous item's value — a textbook
        // silent-contamination regression hazard for the brittle accumulator pattern.
        // This test pins the reset by parsing a two-item feed where item 1 has
        // <dc:modified> and item 2 has only <pubDate>.
        let data = Data(TestFixtures.rssAccumulatorLeakageProbeXML.utf8)
        let feed = try service.parse(data)

        #expect(feed.articles.count == 2)
        // Item 1: has dc:modified
        #expect(feed.articles[0].updatedDate != nil)
        #expect(feed.articles[0].publishedDate != nil)
        // Item 2: must NOT inherit item 1's update value
        #expect(feed.articles[1].updatedDate == nil)
        #expect(feed.articles[1].publishedDate != nil)
        // Sanity: items must have distinct publishedDates from their own <pubDate>
        // elements, not from cross-contamination
        #expect(feed.articles[0].publishedDate != feed.articles[1].publishedDate)
    }

    @Test("Atom entry without <updated> following an entry with <updated> has nil updatedDate")
    func atomUpdatedAccumulatorResetsBetweenEntries() throws {
        // sampleAtomXML has the perfect shape: entry[0] has <published> + <updated>,
        // entry[1] has <published> only. Pins the same accumulator-reset invariant as
        // `updatedDateAccumulatorResetsBetweenItems`, but for the <entry> code path.
        let data = Data(TestFixtures.sampleAtomXML.utf8)
        let feed = try service.parse(data)

        #expect(feed.articles.count == 2)
        #expect(feed.articles[0].updatedDate != nil)
        #expect(feed.articles[1].updatedDate == nil)
    }

    @Test("When multiple update signals appear on one item, the last one in source order wins")
    func multipleUpdateSignalsLastWins() throws {
        // Pins the "last-wins" accumulator semantics for itemUpdatedDate. The switch arm
        // sets itemUpdatedDate unconditionally on every match, so the last encountered
        // element in source order determines the final value. A future contributor might
        // plausibly add an `if itemUpdatedDate.isEmpty` guard (mirroring the pubDate
        // fallback pattern) which would silently flip the semantics to first-wins. That
        // change would break update-detection logic (issue #74) without any other test
        // failing. This test pins the contract explicitly.
        let xml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <rss version="2.0"
                 xmlns:dc="http://purl.org/dc/elements/1.1/"
                 xmlns:atom="http://www.w3.org/2005/Atom">
            <channel>
                <title>Multi Signal</title>
                <link>https://example.com</link>
                <description>desc</description>
                <item>
                    <title>Item</title>
                    <link>https://example.com/multi</link>
                    <description>d</description>
                    <guid>multi-signal-guid</guid>
                    <pubDate>Mon, 30 Mar 2026 12:00:00 +0000</pubDate>
                    <dc:modified>2026-04-01T08:00:00Z</dc:modified>
                    <atom:updated>2026-04-02T09:00:00Z</atom:updated>
                </item>
            </channel>
            </rss>
            """
        let feed = try service.parse(Data(xml.utf8))

        let updated = try #require(feed.articles[0].updatedDate)
        let calendar = Calendar(identifier: .gregorian)
        let day = calendar.component(.day, from: updated)
        // atom:updated (Apr 2) appears after dc:modified (Apr 1) in source order, so it
        // must win. If the semantics were first-wins, day would be 1 instead.
        #expect(day == 2)
    }

    // MARK: - Date Parsing (Absolute Moment)

    /// Builds a minimal RSS feed with a single item and a configurable pubDate string.
    /// Used to exercise `parseDate` through the public `parse()` entry point.
    private static func rssXML(pubDate: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0">
        <channel>
            <title>Date Test Feed</title>
            <link>https://example.com</link>
            <description>Feed</description>
            <item>
                <title>Item</title>
                <link>https://example.com/item</link>
                <guid>item-1</guid>
                <pubDate>\(pubDate)</pubDate>
            </item>
        </channel>
        </rss>
        """
    }

    /// Builds a minimal Atom feed with a single entry and a configurable published date.
    private static func atomXML(published: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
            <title>Date Test Atom Feed</title>
            <link rel="alternate" href="https://example.com" />
            <id>https://example.com/atom</id>
            <updated>2026-04-06T00:00:00Z</updated>
            <entry>
                <title>Entry</title>
                <link rel="alternate" href="https://example.com/entry" />
                <id>entry-1</id>
                <published>\(published)</published>
                <summary>Body</summary>
            </entry>
        </feed>
        """
    }

    /// Returns `(year, month, day, hour, minute, second)` for a `Date` in UTC, for
    /// assertions that verify the absolute moment independent of the runner's timezone.
    private static func utcComponents(_ date: Date) -> (Int, Int, Int, Int, Int, Int) {
        let calendar = Calendar(identifier: .gregorian)
        let components = calendar.dateComponents(in: TimeZone(identifier: "UTC")!, from: date)
        return (
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0,
            components.hour ?? 0,
            components.minute ?? 0,
            components.second ?? 0
        )
    }

    @Test("RSS pubDate with numeric zone parses to correct absolute UTC moment")
    func rssPubDateNumericZone() throws {
        // 08:30 at -0700 = 15:30 UTC
        let xml = Self.rssXML(pubDate: "Mon, 06 Apr 2026 08:30:00 -0700")
        let feed = try service.parse(Data(xml.utf8))

        let date = try #require(feed.articles[0].publishedDate)
        let (y, m, d, hr, min, sec) = Self.utcComponents(date)
        #expect(y == 2026)
        #expect(m == 4)
        #expect(d == 6)
        #expect(hr == 15)
        #expect(min == 30)
        #expect(sec == 0)
    }

    @Test("RSS pubDate with colon-separated numeric zone parses to correct absolute UTC moment")
    func rssPubDateColonNumericZone() throws {
        // RFC 3339 spells offsets with a colon (`-07:00`). The first parser in `parseDate`
        // is `ISO8601DateFormatter.withInternetDateTime`, which accepts the colon form;
        // that's what catches this input in practice. This test guards against regressions
        // where the colon form is silently dropped from the parser chain.
        let xml = Self.rssXML(pubDate: "Mon, 06 Apr 2026 08:30:00 -07:00")
        let feed = try service.parse(Data(xml.utf8))

        let date = try #require(feed.articles[0].publishedDate)
        let (_, _, _, hr, min, _) = Self.utcComponents(date)
        #expect(hr == 15)
        #expect(min == 30)
    }

    @Test("RSS pubDate with named PDT zone parses to correct absolute UTC moment")
    func rssPubDateNamedPDT() throws {
        // 08:30 PDT = 15:30 UTC (daylight saving, UTC-7)
        let xml = Self.rssXML(pubDate: "Mon, 06 Apr 2026 08:30:00 PDT")
        let feed = try service.parse(Data(xml.utf8))

        let date = try #require(feed.articles[0].publishedDate)
        let (_, _, _, hr, min, _) = Self.utcComponents(date)
        #expect(hr == 15)
        #expect(min == 30)
    }

    // MARK: - DST Boundary Tests for Named US Zones
    //
    // These tests pin behavior at the spring-forward and fall-back transitions, which
    // are exactly the moments where `DateFormatter`'s `zzz` named-zone resolution is
    // most likely to drift between OS versions or produce off-by-an-hour results.
    //
    // The tests intentionally treat `PDT` and `PST` as fixed-offset abbreviations
    // (UTC-7 and UTC-8 respectively), not as zone identifiers that consult a tz
    // database to decide whether DST is in effect on a given wall-clock date. This
    // matches how RSS feeds use these tokens in practice: a publisher who writes
    // `01:00:00 PST` means "01:00:00 at UTC-8", not "01:00:00 at America/Los_Angeles
    // resolved against the IANA database, possibly returning a non-existent or
    // ambiguous local time". The fixed-offset interpretation is also what
    // `en_US_POSIX` + `zzz` actually delivers, so these tests double as a regression
    // guard against an OS-level change to that behavior. See GitHub issue #216.
    //
    // The 2025 transition dates (rather than 2026) are used so every input is in the
    // past relative to any plausible test-run clock. The parser no longer rejects
    // future dates (the upper bound was removed when `sortDate` was introduced — see
    // `RSSApp/Models/PersistentArticle.swift`), but past-dated inputs keep these
    // assertions stable across test-run years and avoid relying on the unrelated
    // year-1990 lower-bound rejection from edge-case clock skew.

    @Test("RSS pubDate at 2025 spring-forward instant in PDT parses to correct UTC moment")
    func rssPubDateSpringForwardPDT() throws {
        // First wall-clock moment in PDT after the 2025 spring-forward transition
        // (Sun, 09 Mar 2025). 03:00:00 PDT (UTC-7) = 10:00:00 UTC on the same day.
        let xml = Self.rssXML(pubDate: "Sun, 09 Mar 2025 03:00:00 PDT")
        let feed = try service.parse(Data(xml.utf8))

        let date = try #require(feed.articles[0].publishedDate)
        let expected = try #require(
            Calendar(identifier: .gregorian).date(
                from: DateComponents(
                    timeZone: TimeZone(identifier: "UTC"),
                    year: 2025, month: 3, day: 9, hour: 10, minute: 0, second: 0
                )
            )
        )
        #expect(date == expected)
    }

    @Test("RSS pubDate just before 2025 spring-forward in PST parses to correct UTC moment")
    func rssPubDateJustBeforeSpringForwardPST() throws {
        // Last wall-clock minute of PST before the 2025 spring-forward transition.
        // 01:59:00 PST (UTC-8) = 09:59:00 UTC on the same day. Crucially, this
        // wall-clock time exists in PST and does NOT collide with the skipped
        // 02:00–03:00 local hour.
        let xml = Self.rssXML(pubDate: "Sun, 09 Mar 2025 01:59:00 PST")
        let feed = try service.parse(Data(xml.utf8))

        let date = try #require(feed.articles[0].publishedDate)
        let expected = try #require(
            Calendar(identifier: .gregorian).date(
                from: DateComponents(
                    timeZone: TimeZone(identifier: "UTC"),
                    year: 2025, month: 3, day: 9, hour: 9, minute: 59, second: 0
                )
            )
        )
        #expect(date == expected)
    }

    @Test("RSS pubDate at 2025 fall-back instant in PST parses to correct UTC moment")
    func rssPubDateFallBackPST() throws {
        // First wall-clock moment in PST after the 2025 fall-back transition
        // (Sun, 02 Nov 2025). 01:00:00 PST (UTC-8) = 09:00:00 UTC on the same day.
        // The same wall-clock hour 01:00–02:00 occurs twice on this day in
        // America/Los_Angeles (once in PDT, once in PST); the explicit `PST` token
        // disambiguates to the second occurrence.
        let xml = Self.rssXML(pubDate: "Sun, 02 Nov 2025 01:00:00 PST")
        let feed = try service.parse(Data(xml.utf8))

        let date = try #require(feed.articles[0].publishedDate)
        let expected = try #require(
            Calendar(identifier: .gregorian).date(
                from: DateComponents(
                    timeZone: TimeZone(identifier: "UTC"),
                    year: 2025, month: 11, day: 2, hour: 9, minute: 0, second: 0
                )
            )
        )
        #expect(date == expected)
    }

    @Test("RSS pubDate at 2025 fall-back instant in PDT parses to correct UTC moment")
    func rssPubDateAtFallBackInstantPDT() throws {
        // Wall-clock instant immediately before the fall-back transition completes,
        // when 02:00 PDT rolls back to 01:00 PST on Sun, 02 Nov 2025. The same
        // wall-clock string "01:00:00" occurs twice on this date (once in PDT,
        // once in PST); the explicit `PDT` token disambiguates to the first
        // (pre-rollback) occurrence. 01:00:00 PDT (UTC-7) = 08:00:00 UTC. Pairs
        // with `rssPubDateFallBackPST` above to lock in the one-hour gap between
        // the two occurrences — the same wall-clock string resolves to two
        // distinct UTC instants depending solely on the trailing zone token.
        let xml = Self.rssXML(pubDate: "Sun, 02 Nov 2025 01:00:00 PDT")
        let feed = try service.parse(Data(xml.utf8))

        let date = try #require(feed.articles[0].publishedDate)
        let expected = try #require(
            Calendar(identifier: .gregorian).date(
                from: DateComponents(
                    timeZone: TimeZone(identifier: "UTC"),
                    year: 2025, month: 11, day: 2, hour: 8, minute: 0, second: 0
                )
            )
        )
        #expect(date == expected)
    }

    @Test("PDT and PST tokens at fall-back disambiguate to different UTC instants")
    func rssPubDateFallBackTokenDisambiguation() throws {
        // Single-assertion pair check: the one-hour gap between the two
        // occurrences of "01:00:00" on the 2025 fall-back date is entirely
        // determined by the trailing zone token. If a regression broke
        // PDT/PST disambiguation (e.g. both tokens resolving to the same
        // offset), this is the most obvious symptom.
        let pdtFeed = try service.parse(
            Data(Self.rssXML(pubDate: "Sun, 02 Nov 2025 01:00:00 PDT").utf8)
        )
        let pstFeed = try service.parse(
            Data(Self.rssXML(pubDate: "Sun, 02 Nov 2025 01:00:00 PST").utf8)
        )
        let pdtDate = try #require(pdtFeed.articles[0].publishedDate)
        let pstDate = try #require(pstFeed.articles[0].publishedDate)
        #expect(pstDate.timeIntervalSince(pdtDate) == 3600)
    }

    @Test("RSS pubDate in non-existent spring-forward hour parses as fixed offset, not rejected")
    func rssPubDateInSpringForwardGap() throws {
        // 02:30:00 on Sun, 09 Mar 2025 does not exist in America/Los_Angeles: the
        // local clock jumps from 01:59:59 PST straight to 03:00:00 PDT. A parser
        // that consults the IANA database to validate wall-clock inputs would
        // reject these as non-existent. The fixed-offset interpretation treats
        // PDT/PST as UTC-7/UTC-8 abbreviations, so both strings must parse
        // non-nil. This test pins that behavior against a future "fix" that
        // might reject skipped-hour inputs as ambiguous.
        let pstFeed = try service.parse(
            Data(Self.rssXML(pubDate: "Sun, 09 Mar 2025 02:30:00 PST").utf8)
        )
        let pdtFeed = try service.parse(
            Data(Self.rssXML(pubDate: "Sun, 09 Mar 2025 02:30:00 PDT").utf8)
        )
        #expect(pstFeed.articles[0].publishedDate != nil)
        #expect(pdtFeed.articles[0].publishedDate != nil)
    }

    // MARK: - DST Boundary Tests for EDT/EST, CDT/CST, MDT/MST
    //
    // These mirror the PDT/PST coverage above for the other North American named
    // zones accepted by `parseDate` via the `zzz` specifier. The same OS-level
    // drift risk applies to every zone resolved through `zzz`, so each pair is
    // pinned at the 2025 spring-forward and fall-back transitions following the
    // pattern established for PDT/PST. See GitHub issues #216 and #240.
    //
    // The CST/CDT pair is especially important because the named-zone substitution
    // table in `RSSParsingService` routes `CST` to `+0800` (China Standard Time)
    // as a fallback for feeds that specify CST without an explicit-zone format
    // match. The zoned-format pass runs before the substitution pass, so North
    // American `CST` inputs are expected to resolve as Central Standard Time
    // (UTC-6) via `zzz` and never reach the substitution table. These tests pin
    // that ordering: a regression that made `CST` drop through to the substitution
    // table would push the parsed instant 14 hours away from the intended UTC
    // moment and immediately break these assertions.
    //
    // As with the PDT/PST block, 2025 dates are used so every input remains in
    // the past relative to any plausible test-run clock — keeping the assertions
    // year-stable. The parser no longer enforces a future-date upper bound (see
    // the PDT/PST block above for the rationale).

    @Test("RSS pubDate at 2025 spring-forward instant in EDT parses to correct UTC moment")
    func rssPubDateSpringForwardEDT() throws {
        // First wall-clock moment in EDT after the 2025 spring-forward transition
        // (Sun, 09 Mar 2025). 03:00:00 EDT (UTC-4) = 07:00:00 UTC on the same day.
        let xml = Self.rssXML(pubDate: "Sun, 09 Mar 2025 03:00:00 EDT")
        let feed = try service.parse(Data(xml.utf8))

        let date = try #require(feed.articles[0].publishedDate)
        let expected = try #require(
            Calendar(identifier: .gregorian).date(
                from: DateComponents(
                    timeZone: TimeZone(identifier: "UTC"),
                    year: 2025, month: 3, day: 9, hour: 7, minute: 0, second: 0
                )
            )
        )
        #expect(date == expected)
    }

    @Test("RSS pubDate at 2025 fall-back instant in EST parses to correct UTC moment")
    func rssPubDateFallBackEST() throws {
        // First wall-clock moment in EST after the 2025 fall-back transition
        // (Sun, 02 Nov 2025). 01:00:00 EST (UTC-5) = 06:00:00 UTC on the same day.
        // The wall-clock hour 01:00–02:00 occurs twice in America/New_York on
        // this date; the explicit `EST` token disambiguates to the second (post-
        // rollback) occurrence.
        let xml = Self.rssXML(pubDate: "Sun, 02 Nov 2025 01:00:00 EST")
        let feed = try service.parse(Data(xml.utf8))

        let date = try #require(feed.articles[0].publishedDate)
        let expected = try #require(
            Calendar(identifier: .gregorian).date(
                from: DateComponents(
                    timeZone: TimeZone(identifier: "UTC"),
                    year: 2025, month: 11, day: 2, hour: 6, minute: 0, second: 0
                )
            )
        )
        #expect(date == expected)
    }

    @Test("EDT and EST tokens at fall-back disambiguate to different UTC instants")
    func rssPubDateFallBackEasternTokenDisambiguation() throws {
        // The one-hour gap between the two occurrences of "01:00:00" on the 2025
        // fall-back date is entirely determined by the trailing zone token.
        let edtFeed = try service.parse(
            Data(Self.rssXML(pubDate: "Sun, 02 Nov 2025 01:00:00 EDT").utf8)
        )
        let estFeed = try service.parse(
            Data(Self.rssXML(pubDate: "Sun, 02 Nov 2025 01:00:00 EST").utf8)
        )
        let edtDate = try #require(edtFeed.articles[0].publishedDate)
        let estDate = try #require(estFeed.articles[0].publishedDate)
        #expect(estDate.timeIntervalSince(edtDate) == 3600)
    }

    @Test("RSS pubDate in non-existent spring-forward hour parses as fixed offset for Eastern zones")
    func rssPubDateInSpringForwardGapEastern() throws {
        // 02:30:00 on Sun, 09 Mar 2025 does not exist in America/New_York: the
        // local clock jumps from 01:59:59 EST to 03:00:00 EDT. Pins the fixed-
        // offset interpretation against a future change that would reject
        // skipped-hour inputs as ambiguous.
        let estFeed = try service.parse(
            Data(Self.rssXML(pubDate: "Sun, 09 Mar 2025 02:30:00 EST").utf8)
        )
        let edtFeed = try service.parse(
            Data(Self.rssXML(pubDate: "Sun, 09 Mar 2025 02:30:00 EDT").utf8)
        )
        #expect(estFeed.articles[0].publishedDate != nil)
        #expect(edtFeed.articles[0].publishedDate != nil)
    }

    @Test("RSS pubDate at 2025 spring-forward instant in CDT parses to correct UTC moment")
    func rssPubDateSpringForwardCDT() throws {
        // First wall-clock moment in CDT after the 2025 spring-forward transition
        // (Sun, 09 Mar 2025). 03:00:00 CDT (UTC-5) = 08:00:00 UTC on the same day.
        let xml = Self.rssXML(pubDate: "Sun, 09 Mar 2025 03:00:00 CDT")
        let feed = try service.parse(Data(xml.utf8))

        let date = try #require(feed.articles[0].publishedDate)
        let expected = try #require(
            Calendar(identifier: .gregorian).date(
                from: DateComponents(
                    timeZone: TimeZone(identifier: "UTC"),
                    year: 2025, month: 3, day: 9, hour: 8, minute: 0, second: 0
                )
            )
        )
        #expect(date == expected)
    }

    @Test("RSS pubDate at 2025 fall-back instant in CST parses to correct UTC moment, not China time")
    func rssPubDateFallBackCST() throws {
        // First wall-clock moment in CST after the 2025 fall-back transition
        // (Sun, 02 Nov 2025). 01:00:00 CST (UTC-6) = 07:00:00 UTC on the same day.
        //
        // This test is doubly important: the named-zone substitution table in
        // `RSSParsingService` routes `CST` to `+0800` (China Standard Time) as a
        // fallback. The zoned-format pass runs before the substitution pass, so
        // North American `CST` inputs are expected to resolve as Central Standard
        // Time via `zzz` and never reach the substitution table. A regression
        // that caused `CST` to drop through to the substitution table would
        // resolve this input to 17:00:00 UTC on 01 Nov 2025 instead, putting
        // the parsed instant 14 hours off the intended moment.
        let xml = Self.rssXML(pubDate: "Sun, 02 Nov 2025 01:00:00 CST")
        let feed = try service.parse(Data(xml.utf8))

        let date = try #require(feed.articles[0].publishedDate)
        let expected = try #require(
            Calendar(identifier: .gregorian).date(
                from: DateComponents(
                    timeZone: TimeZone(identifier: "UTC"),
                    year: 2025, month: 11, day: 2, hour: 7, minute: 0, second: 0
                )
            )
        )
        #expect(date == expected)
    }

    @Test("CDT and CST tokens at fall-back disambiguate to different UTC instants")
    func rssPubDateFallBackCentralTokenDisambiguation() throws {
        // The one-hour gap between the two occurrences of "01:00:00" on the 2025
        // fall-back date is entirely determined by the trailing zone token. If
        // a regression caused `CST` to resolve via the China-time substitution
        // table, the two instants would be separated by many hours instead of
        // exactly 3600 seconds and this assertion would immediately fail.
        let cdtFeed = try service.parse(
            Data(Self.rssXML(pubDate: "Sun, 02 Nov 2025 01:00:00 CDT").utf8)
        )
        let cstFeed = try service.parse(
            Data(Self.rssXML(pubDate: "Sun, 02 Nov 2025 01:00:00 CST").utf8)
        )
        let cdtDate = try #require(cdtFeed.articles[0].publishedDate)
        let cstDate = try #require(cstFeed.articles[0].publishedDate)
        #expect(cstDate.timeIntervalSince(cdtDate) == 3600)
    }

    @Test("RSS pubDate in non-existent spring-forward hour parses as fixed offset for Central zones")
    func rssPubDateInSpringForwardGapCentral() throws {
        // 02:30:00 on Sun, 09 Mar 2025 does not exist in America/Chicago: the
        // local clock jumps from 01:59:59 CST to 03:00:00 CDT. Pins the fixed-
        // offset interpretation against a future change that would reject
        // skipped-hour inputs as ambiguous.
        let cstFeed = try service.parse(
            Data(Self.rssXML(pubDate: "Sun, 09 Mar 2025 02:30:00 CST").utf8)
        )
        let cdtFeed = try service.parse(
            Data(Self.rssXML(pubDate: "Sun, 09 Mar 2025 02:30:00 CDT").utf8)
        )
        #expect(cstFeed.articles[0].publishedDate != nil)
        #expect(cdtFeed.articles[0].publishedDate != nil)
    }

    @Test("RSS pubDate at 2025 spring-forward instant in MDT parses to correct UTC moment")
    func rssPubDateSpringForwardMDT() throws {
        // First wall-clock moment in MDT after the 2025 spring-forward transition
        // (Sun, 09 Mar 2025). 03:00:00 MDT (UTC-6) = 09:00:00 UTC on the same day.
        // Note: Arizona stays on MST year-round, so the real-world semantics of
        // an `MDT` token are publisher-dependent. These tests pin the fixed-
        // offset interpretation that `DateFormatter`'s `zzz` specifier applies
        // regardless of the wall-clock date, matching the PDT/PST/EDT/EST/CDT/CST
        // behavior above.
        let xml = Self.rssXML(pubDate: "Sun, 09 Mar 2025 03:00:00 MDT")
        let feed = try service.parse(Data(xml.utf8))

        let date = try #require(feed.articles[0].publishedDate)
        let expected = try #require(
            Calendar(identifier: .gregorian).date(
                from: DateComponents(
                    timeZone: TimeZone(identifier: "UTC"),
                    year: 2025, month: 3, day: 9, hour: 9, minute: 0, second: 0
                )
            )
        )
        #expect(date == expected)
    }

    @Test("RSS pubDate at 2025 fall-back instant in MST parses to correct UTC moment")
    func rssPubDateFallBackMST() throws {
        // First wall-clock moment in MST after the 2025 fall-back transition
        // (Sun, 02 Nov 2025). 01:00:00 MST (UTC-7) = 08:00:00 UTC on the same day.
        let xml = Self.rssXML(pubDate: "Sun, 02 Nov 2025 01:00:00 MST")
        let feed = try service.parse(Data(xml.utf8))

        let date = try #require(feed.articles[0].publishedDate)
        let expected = try #require(
            Calendar(identifier: .gregorian).date(
                from: DateComponents(
                    timeZone: TimeZone(identifier: "UTC"),
                    year: 2025, month: 11, day: 2, hour: 8, minute: 0, second: 0
                )
            )
        )
        #expect(date == expected)
    }

    @Test("MDT and MST tokens at fall-back disambiguate to different UTC instants")
    func rssPubDateFallBackMountainTokenDisambiguation() throws {
        // The one-hour gap between the two occurrences of "01:00:00" on the 2025
        // fall-back date is entirely determined by the trailing zone token.
        let mdtFeed = try service.parse(
            Data(Self.rssXML(pubDate: "Sun, 02 Nov 2025 01:00:00 MDT").utf8)
        )
        let mstFeed = try service.parse(
            Data(Self.rssXML(pubDate: "Sun, 02 Nov 2025 01:00:00 MST").utf8)
        )
        let mdtDate = try #require(mdtFeed.articles[0].publishedDate)
        let mstDate = try #require(mstFeed.articles[0].publishedDate)
        #expect(mstDate.timeIntervalSince(mdtDate) == 3600)
    }

    @Test("RSS pubDate in non-existent spring-forward hour parses as fixed offset for Mountain zones")
    func rssPubDateInSpringForwardGapMountain() throws {
        // 02:30:00 on Sun, 09 Mar 2025 does not exist in America/Denver: the
        // local clock jumps from 01:59:59 MST to 03:00:00 MDT. Pins the fixed-
        // offset interpretation against a future change that would reject
        // skipped-hour inputs as ambiguous.
        let mstFeed = try service.parse(
            Data(Self.rssXML(pubDate: "Sun, 09 Mar 2025 02:30:00 MST").utf8)
        )
        let mdtFeed = try service.parse(
            Data(Self.rssXML(pubDate: "Sun, 09 Mar 2025 02:30:00 MDT").utf8)
        )
        #expect(mstFeed.articles[0].publishedDate != nil)
        #expect(mdtFeed.articles[0].publishedDate != nil)
    }

    @Test("RSS pubDate with named GMT zone parses to correct absolute UTC moment")
    func rssPubDateNamedGMT() throws {
        let xml = Self.rssXML(pubDate: "Mon, 06 Apr 2026 08:30:00 GMT")
        let feed = try service.parse(Data(xml.utf8))

        let date = try #require(feed.articles[0].publishedDate)
        let (_, _, _, hr, min, _) = Self.utcComponents(date)
        #expect(hr == 8)
        #expect(min == 30)
    }

    @Test("RSS pubDate without seconds parses correctly")
    func rssPubDateNoSeconds() throws {
        let xml = Self.rssXML(pubDate: "Mon, 06 Apr 2026 08:30 +0000")
        let feed = try service.parse(Data(xml.utf8))

        let date = try #require(feed.articles[0].publishedDate)
        let (_, _, _, hr, min, sec) = Self.utcComponents(date)
        #expect(hr == 8)
        #expect(min == 30)
        #expect(sec == 0)
    }

    @Test("RSS pubDate without weekday parses correctly")
    func rssPubDateNoWeekday() throws {
        let xml = Self.rssXML(pubDate: "6 Apr 2026 08:30:00 +0000")
        let feed = try service.parse(Data(xml.utf8))

        let date = try #require(feed.articles[0].publishedDate)
        let (y, m, d, hr, _, _) = Self.utcComponents(date)
        #expect(y == 2026)
        #expect(m == 4)
        #expect(d == 6)
        #expect(hr == 8)
    }

    @Test("Atom published date with colon-separated zone parses to correct absolute UTC moment")
    func atomPublishedColonZone() throws {
        // RFC 3339 / Atom-style colon-separated offset (-07:00) — historically a common
        // failure mode for naive RSS parsers; this test locks in correct parsing.
        let xml = Self.atomXML(published: "2026-04-06T08:30:00-07:00")
        let feed = try service.parse(Data(xml.utf8))

        let date = try #require(feed.articles[0].publishedDate)
        let (_, _, _, hr, min, _) = Self.utcComponents(date)
        #expect(hr == 15)
        #expect(min == 30)
    }

    @Test("Atom published date with fractional seconds and numeric zone parses correctly")
    func atomPublishedFractionalSeconds() throws {
        // Non-colon numeric offset (`+0000`) specifically exercises the DateFormatter
        // `yyyy-MM-dd'T'HH:mm:ss.SSSZ` fallback rather than being caught by
        // ISO8601Formatters.fractional (which requires a colon in the offset).
        let xml = Self.atomXML(published: "2026-04-06T08:30:00.123+0000")
        let feed = try service.parse(Data(xml.utf8))

        let date = try #require(feed.articles[0].publishedDate)
        let (_, _, _, hr, min, _) = Self.utcComponents(date)
        #expect(hr == 8)
        #expect(min == 30)
    }

    @Test("Atom published date with 'Z' literal zone parses as UTC")
    func atomPublishedZuluZone() throws {
        let xml = Self.atomXML(published: "2026-04-06T08:30:00Z")
        let feed = try service.parse(Data(xml.utf8))

        let date = try #require(feed.articles[0].publishedDate)
        let (_, _, _, hr, min, _) = Self.utcComponents(date)
        #expect(hr == 8)
        #expect(min == 30)
    }

    @Test("ISO 8601 with space separator and zone parses to correct absolute moment")
    func isoSpaceSeparatorZoned() throws {
        // Some SQL-flavored feeds emit "2026-04-06 08:30:00+0000" instead of the 'T' form.
        let xml = Self.rssXML(pubDate: "2026-04-06 08:30:00+0000")
        let feed = try service.parse(Data(xml.utf8))

        let date = try #require(feed.articles[0].publishedDate)
        let (y, m, d, hr, min, _) = Self.utcComponents(date)
        #expect(y == 2026)
        #expect(m == 4)
        #expect(d == 6)
        #expect(hr == 8)
        #expect(min == 30)
    }

    @Test("Zone-less RFC 822 date is interpreted as UTC (documented fallback)")
    func zonelessRFC822FallsBackToUTC() throws {
        // Previously this input produced `nil`, hiding the article's timestamp from the UI.
        // The fallback interprets zone-less dates as UTC and logs at `.debug` (see issue
        // #208 for the original fix and #214 for the log-level demotion).
        let xml = Self.rssXML(pubDate: "Mon, 06 Apr 2026 08:30:00")
        let feed = try service.parse(Data(xml.utf8))

        let date = try #require(feed.articles[0].publishedDate)
        let (y, m, d, hr, min, _) = Self.utcComponents(date)
        #expect(y == 2026)
        #expect(m == 4)
        #expect(d == 6)
        #expect(hr == 8)
        #expect(min == 30)
    }

    @Test("Zone-less ISO 8601 date is interpreted as UTC (documented fallback)")
    func zonelessISO8601FallsBackToUTC() throws {
        let xml = Self.atomXML(published: "2026-04-06T08:30:00")
        let feed = try service.parse(Data(xml.utf8))

        let date = try #require(feed.articles[0].publishedDate)
        let (_, _, _, hr, min, _) = Self.utcComponents(date)
        #expect(hr == 8)
        #expect(min == 30)
    }

    @Test("Zone-less date-only form is interpreted as midnight UTC")
    func zonelessDateOnlyFallsBackToUTC() throws {
        let xml = Self.rssXML(pubDate: "2026-04-06")
        let feed = try service.parse(Data(xml.utf8))

        let date = try #require(feed.articles[0].publishedDate)
        let (y, m, d, hr, min, sec) = Self.utcComponents(date)
        #expect(y == 2026)
        #expect(m == 4)
        #expect(d == 6)
        #expect(hr == 0)
        #expect(min == 0)
        #expect(sec == 0)
    }

    @Test("Unparseable date string produces nil publishedDate")
    func unparseableDateProducesNil() throws {
        let xml = Self.rssXML(pubDate: "not a date at all")
        let feed = try service.parse(Data(xml.utf8))

        #expect(feed.articles[0].publishedDate == nil)
    }

    @Test("Zoned input produces the same absolute moment regardless of device timezone")
    func zonedInputIsAbsoluteMoment() throws {
        // Regression guard: the absolute `Date` for a zoned input must match the expected
        // UTC moment exactly, so the cross-feed "Text(date, style: .relative)" display is
        // correct no matter where the user is located. See issue #208.
        let xml = Self.rssXML(pubDate: "Mon, 06 Apr 2026 08:30:00 -0700")
        let feed = try service.parse(Data(xml.utf8))

        let date = try #require(feed.articles[0].publishedDate)
        // 08:30 at -0700 corresponds to exactly 15:30:00 UTC.
        let expected = try #require(
            Calendar(identifier: .gregorian).date(
                from: DateComponents(
                    timeZone: TimeZone(identifier: "UTC"),
                    year: 2026, month: 4, day: 6, hour: 15, minute: 30, second: 0
                )
            )
        )
        #expect(date == expected)
    }

    @Test("Zoneless input is interpreted as UTC, not the device's local timezone")
    func zonelessInputIsUTCNotLocal() throws {
        // Regression guard: a zoneless input must be parsed as an absolute UTC moment,
        // not as a wall-clock time in the device's local zone. This is the single test
        // that would catch the dropped-`formatter.timeZone` regression on a non-UTC dev
        // machine. See issue #208.
        let xml = Self.rssXML(pubDate: "Mon, 06 Apr 2026 08:30:00")
        let feed = try service.parse(Data(xml.utf8))

        let date = try #require(feed.articles[0].publishedDate)
        let expected = try #require(
            Calendar(identifier: .gregorian).date(
                from: DateComponents(
                    timeZone: TimeZone(identifier: "UTC"),
                    year: 2026, month: 4, day: 6, hour: 8, minute: 30, second: 0
                )
            )
        )
        #expect(date == expected)
    }

    @Test("Two-digit year is rejected by the sanity check")
    func twoDigitYearIsRejected() throws {
        // `DateFormatter`'s `yyyy` is "year of era" and will happily parse `"26"` as
        // year 26 AD. The sanity check must reject the resulting date before it poisons
        // cross-feed sorting and article retention. See issue #208.
        let xml = Self.rssXML(pubDate: "Mon, 06 Apr 26 08:30:00 +0000")
        let feed = try service.parse(Data(xml.utf8))

        #expect(feed.articles[0].publishedDate == nil)
    }

    @Test("Future pubDate flows through the parser unchanged (no upper-bound clamping)")
    func futurePubDatePassesThroughParser() throws {
        // Pins the asymmetric sanity policy: the parser rejects only the year-1990
        // lower bound and allows all future dates through unchanged. The clamping
        // for sort/retention/display purposes happens at insert time in
        // `PersistentArticle.clampedSortDate(publishedDate:)`, NOT in the parser —
        // because the planned content-update detection feature compares pubDate
        // values across refreshes, so any mutation here would destroy that signal.
        //
        // This is the parser-side regression test for the Cloudflare bug. The
        // persistence-layer integration tests bypass the parser by constructing
        // `Article` directly via `TestFixtures.makeArticle`, so they cannot catch a
        // regression that re-introduces an upper bound in `RSSParsingService.sanityChecked`.
        let fourHoursFromNow = Date().addingTimeInterval(4 * 60 * 60)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        let pubDate = formatter.string(from: fourHoursFromNow)

        let xml = Self.rssXML(pubDate: pubDate)
        let feed = try service.parse(Data(xml.utf8))

        let parsed = try #require(feed.articles[0].publishedDate)
        // Within 1 second of the original (DateFormatter has second-level precision)
        #expect(abs(parsed.timeIntervalSince(fourHoursFromNow)) < 1.0)
        // Still in the future — the parser did not clamp.
        #expect(parsed > Date())
    }

    // MARK: - Date Parsing (Per-Format Coverage)

    // The tests below exercise each individual entry in `HoistedDateFormatters.zoned`
    // and `HoistedDateFormatters.zoneless` that was added in PR #212 but not yet
    // covered by a dedicated assertion. Every input is crafted so that earlier
    // formats in the parse chain (including `ISO8601DateFormatter`) fail to match,
    // forcing the parser to reach the specific entry under test. Deleting the
    // corresponding entry from the formats list must cause the matching test here
    // to fail. See GitHub issue #215.

    @Test("Zoned format 'EEE, dd MMM yyyy HH:mm zzz' is reachable (no seconds, named zone)")
    func zonedEEEDDMMMYYYYHHmmNamedZone() throws {
        // RFC 2822 permits omitting seconds; pairing that with a named non-`GMT` zone
        // reaches the `EEE, dd MMM yyyy HH:mm zzz` entry specifically. A `GMT` suffix
        // would be absorbed by the earlier numeric-offset `EEE, dd MMM yyyy HH:mm Z`
        // entry, since `DateFormatter`'s `Z` specifier with `en_US_POSIX` accepts the
        // literal `GMT`. `EST` is rejected by `Z` and accepted by `zzz`, so it
        // forces the formatter to fall through to the named-zone entry.
        // 08:30 EST = 13:30 UTC.
        let xml = Self.rssXML(pubDate: "Mon, 06 Apr 2026 08:30 EST")
        let feed = try service.parse(Data(xml.utf8))

        let date = try #require(feed.articles[0].publishedDate)
        let expected = try Self.utcDate(year: 2026, month: 4, day: 6, hour: 13, minute: 30)
        #expect(date == expected)
    }

    @Test("Zoned format 'yyyy-MM-dd HH:mm:ss zzz' is reachable (space separator, named zone)")
    func zonedYYYYMMDDSpaceNamedZone() throws {
        // SQL-flavored space separator combined with a named non-`GMT` zone. A `GMT`
        // suffix would be absorbed by the earlier `yyyy-MM-dd HH:mm:ssZ` entry, since
        // `DateFormatter`'s `Z` specifier with `en_US_POSIX` accepts the literal
        // `GMT` and tolerates leading whitespace before the zone token. `EST` is
        // rejected by `Z` and accepted by `zzz`, so it forces the formatter to fall
        // through to the named-zone entry.
        // 08:30 EST = 13:30 UTC.
        let xml = Self.rssXML(pubDate: "2026-04-06 08:30:00 EST")
        let feed = try service.parse(Data(xml.utf8))

        let date = try #require(feed.articles[0].publishedDate)
        let expected = try Self.utcDate(year: 2026, month: 4, day: 6, hour: 13, minute: 30)
        #expect(date == expected)
    }

    @Test("Zoneless format 'EEE, dd MMM yyyy HH:mm' is reachable (no seconds, no zone)")
    func zonelessEEEDDMMMYYYYHHmm() throws {
        // RFC 2822-ish input with a weekday, no seconds, and no zone. The preceding
        // zoneless entry (`EEE, dd MMM yyyy HH:mm:ss`) requires seconds and must
        // fail before this entry is tried.
        let xml = Self.rssXML(pubDate: "Mon, 06 Apr 2026 08:30")
        let feed = try service.parse(Data(xml.utf8))

        let date = try #require(feed.articles[0].publishedDate)
        let expected = try Self.utcDate(year: 2026, month: 4, day: 6, hour: 8, minute: 30)
        #expect(date == expected)
    }

    @Test("Zoneless format 'dd MMM yyyy HH:mm:ss' is reachable (no weekday, no zone)")
    func zonelessDDMMMYYYYHHmmss() throws {
        // No weekday, seconds present, no zone. Distinguishes this entry from the
        // `EEE, dd MMM yyyy HH:mm:ss` and `EEE, dd MMM yyyy HH:mm` entries that
        // precede it in the zoneless list.
        let xml = Self.rssXML(pubDate: "06 Apr 2026 08:30:00")
        let feed = try service.parse(Data(xml.utf8))

        let date = try #require(feed.articles[0].publishedDate)
        let expected = try Self.utcDate(year: 2026, month: 4, day: 6, hour: 8, minute: 30)
        #expect(date == expected)
    }

    @Test("Zoneless format 'yyyy-MM-dd'T'HH:mm:ss.SSS' is reachable (fractional seconds, no zone)")
    func zonelessYYYYMMDDTHHmmssFractional() throws {
        // `ISO8601DateFormatter` with `.withInternetDateTime` requires an explicit
        // zone, so a zoneless fractional-seconds input falls through every zoned
        // pass and lands on this zoneless entry.
        let xml = Self.atomXML(published: "2026-04-06T08:30:00.123")
        let feed = try service.parse(Data(xml.utf8))

        let date = try #require(feed.articles[0].publishedDate)
        let (y, mo, d, hr, mi, s) = Self.utcComponents(date)
        #expect(y == 2026)
        #expect(mo == 4)
        #expect(d == 6)
        #expect(hr == 8)
        #expect(mi == 30)
        // Asserting `s == 0` catches a regression where the formatter mis-reads the
        // fractional component into the seconds slot (e.g., interpreting `.123` such
        // that the resulting `Date` lands on `08:30:30.something`).
        #expect(s == 0)
    }

    @Test("Zoneless format 'yyyy-MM-dd HH:mm:ss' is reachable (space separator, no zone)")
    func zonelessYYYYMMDDSpace() throws {
        // SQL-flavored space separator without a zone. Distinguishes this entry
        // from the zone-bearing `yyyy-MM-dd HH:mm:ssZ` / `yyyy-MM-dd HH:mm:ss zzz`
        // zoned formats and from the ISO 8601 `'T'` zoneless formats that come
        // earlier in the zoneless list.
        let xml = Self.rssXML(pubDate: "2026-04-06 08:30:00")
        let feed = try service.parse(Data(xml.utf8))

        let date = try #require(feed.articles[0].publishedDate)
        let expected = try Self.utcDate(year: 2026, month: 4, day: 6, hour: 8, minute: 30)
        #expect(date == expected)
    }

    // MARK: - Date Parsing (Non-US Named Timezones)

    /// Builds the expected absolute UTC `Date` for the given UTC wall-clock components.
    /// Used by the named-timezone tests below to assert exact moment equality without
    /// per-test boilerplate.
    private static func utcDate(
        year: Int, month: Int, day: Int, hour: Int, minute: Int, second: Int = 0
    ) throws -> Date {
        try #require(
            Calendar(identifier: .gregorian).date(
                from: DateComponents(
                    timeZone: TimeZone(identifier: "UTC"),
                    year: year, month: month, day: day,
                    hour: hour, minute: minute, second: second
                )
            )
        )
    }

    @Test("RSS pubDate with named CET zone parses to correct absolute UTC moment")
    func rssPubDateNamedCET() throws {
        // 08:30 CET (UTC+1) = 07:30 UTC. Regression guard for issue #213: previously
        // returned nil because `DateFormatter`'s `zzz` with `en_US_POSIX` does not
        // recognize Central European Time.
        let xml = Self.rssXML(pubDate: "Mon, 06 Apr 2026 08:30:00 CET")
        let feed = try service.parse(Data(xml.utf8))

        let date = try #require(feed.articles[0].publishedDate)
        let expected = try Self.utcDate(year: 2026, month: 4, day: 6, hour: 7, minute: 30)
        #expect(date == expected)
    }

    @Test("RSS pubDate with named CEST zone parses to correct absolute UTC moment")
    func rssPubDateNamedCEST() throws {
        // 08:30 CEST (UTC+2) = 06:30 UTC. CEST is the daylight-saving form of CET.
        let xml = Self.rssXML(pubDate: "Mon, 06 Apr 2026 08:30:00 CEST")
        let feed = try service.parse(Data(xml.utf8))

        let date = try #require(feed.articles[0].publishedDate)
        let expected = try Self.utcDate(year: 2026, month: 4, day: 6, hour: 6, minute: 30)
        #expect(date == expected)
    }

    @Test("RSS pubDate with named BST zone parses as British Summer Time")
    func rssPubDateNamedBST() throws {
        // 08:30 BST (UTC+1, British Summer Time) = 07:30 UTC. BST is intentionally
        // resolved to British Summer Time rather than Bangladesh Standard Time; see the
        // RATIONALE in `RSSParsingService.namedZoneOffsets`.
        let xml = Self.rssXML(pubDate: "Mon, 06 Apr 2026 08:30:00 BST")
        let feed = try service.parse(Data(xml.utf8))

        let date = try #require(feed.articles[0].publishedDate)
        let expected = try Self.utcDate(year: 2026, month: 4, day: 6, hour: 7, minute: 30)
        #expect(date == expected)
    }

    @Test("RSS pubDate with named JST zone parses to correct absolute UTC moment")
    func rssPubDateNamedJST() throws {
        // 08:30 JST (UTC+9) = 23:30 UTC on the previous day.
        let xml = Self.rssXML(pubDate: "Mon, 06 Apr 2026 08:30:00 JST")
        let feed = try service.parse(Data(xml.utf8))

        let date = try #require(feed.articles[0].publishedDate)
        let expected = try Self.utcDate(year: 2026, month: 4, day: 5, hour: 23, minute: 30)
        #expect(date == expected)
    }

    @Test("RSS pubDate with named KST zone parses to correct absolute UTC moment")
    func rssPubDateNamedKST() throws {
        // 08:30 KST (UTC+9) = 23:30 UTC on the previous day. KST shares an offset with
        // JST; this test exists to lock in support for the abbreviation specifically.
        let xml = Self.rssXML(pubDate: "Mon, 06 Apr 2026 08:30:00 KST")
        let feed = try service.parse(Data(xml.utf8))

        let date = try #require(feed.articles[0].publishedDate)
        let expected = try Self.utcDate(year: 2026, month: 4, day: 5, hour: 23, minute: 30)
        #expect(date == expected)
    }

    @Test("RSS pubDate with named IST zone parses as India Standard Time")
    func rssPubDateNamedIST() throws {
        // 09:30 IST (UTC+5:30) = 04:00 UTC. IST is intentionally resolved to India
        // Standard Time rather than Irish or Israel time; see the RATIONALE in
        // `RSSParsingService.namedZoneOffsets`.
        let xml = Self.rssXML(pubDate: "Mon, 06 Apr 2026 09:30:00 IST")
        let feed = try service.parse(Data(xml.utf8))

        let date = try #require(feed.articles[0].publishedDate)
        let expected = try Self.utcDate(year: 2026, month: 4, day: 6, hour: 4, minute: 0)
        #expect(date == expected)
    }

    @Test("RSS pubDate with named AEST zone parses to correct absolute UTC moment")
    func rssPubDateNamedAEST() throws {
        // 18:30 AEST (UTC+10) = 08:30 UTC.
        let xml = Self.rssXML(pubDate: "Mon, 06 Apr 2026 18:30:00 AEST")
        let feed = try service.parse(Data(xml.utf8))

        let date = try #require(feed.articles[0].publishedDate)
        let expected = try Self.utcDate(year: 2026, month: 4, day: 6, hour: 8, minute: 30)
        #expect(date == expected)
    }

    @Test("RSS pubDate with named MSK zone parses to correct absolute UTC moment")
    func rssPubDateNamedMSK() throws {
        // 11:30 MSK (UTC+3, Moscow) = 08:30 UTC.
        let xml = Self.rssXML(pubDate: "Mon, 06 Apr 2026 11:30:00 MSK")
        let feed = try service.parse(Data(xml.utf8))

        let date = try #require(feed.articles[0].publishedDate)
        let expected = try Self.utcDate(year: 2026, month: 4, day: 6, hour: 8, minute: 30)
        #expect(date == expected)
    }

    @Test("RSS pubDate with named BRT zone parses to correct absolute UTC moment")
    func rssPubDateNamedBRT() throws {
        // 05:30 BRT (UTC-3, Brasília) = 08:30 UTC.
        let xml = Self.rssXML(pubDate: "Mon, 06 Apr 2026 05:30:00 BRT")
        let feed = try service.parse(Data(xml.utf8))

        let date = try #require(feed.articles[0].publishedDate)
        let expected = try Self.utcDate(year: 2026, month: 4, day: 6, hour: 8, minute: 30)
        #expect(date == expected)
    }

    @Test("RSS pubDate with single-digit day and named non-US zone parses correctly")
    func rssPubDateSingleDigitDayNamedZone() throws {
        // The single-digit-day RFC 822 variant must also benefit from the named-zone
        // substitution, since both the `dd` and `d` formats need to be retried against
        // the rewritten input.
        let xml = Self.rssXML(pubDate: "Mon, 6 Apr 2026 08:30:00 CET")
        let feed = try service.parse(Data(xml.utf8))

        let date = try #require(feed.articles[0].publishedDate)
        let expected = try Self.utcDate(year: 2026, month: 4, day: 6, hour: 7, minute: 30)
        #expect(date == expected)
    }

    @Test("RSS pubDate with lowercase named zone parses correctly")
    func rssPubDateLowercaseNamedZone() throws {
        // Some publishers emit timezone abbreviations in lowercase. The substitution
        // pass uppercases the trailing token before lookup so these still resolve.
        let xml = Self.rssXML(pubDate: "Mon, 06 Apr 2026 08:30:00 cet")
        let feed = try service.parse(Data(xml.utf8))

        let date = try #require(feed.articles[0].publishedDate)
        let expected = try Self.utcDate(year: 2026, month: 4, day: 6, hour: 7, minute: 30)
        #expect(date == expected)
    }

    @Test("RSS pubDate with unknown named zone returns nil instead of guessing")
    func rssPubDateUnknownNamedZoneReturnsNil() throws {
        // An unrecognized abbreviation must not silently fall through to the zoneless
        // UTC fallback (which would produce a wrong-by-N-hours date). The parser must
        // return nil so the article displays without a misleading timestamp.
        let xml = Self.rssXML(pubDate: "Mon, 06 Apr 2026 08:30:00 XYZ")
        let feed = try service.parse(Data(xml.utf8))

        #expect(feed.articles[0].publishedDate == nil)
    }

    @Test("RSS pubDate with named CST zone parses as US Central Standard Time, not China")
    func rssPubDateNamedCSTResolvesToUSCentral() throws {
        // Regression guard for a load-bearing assumption documented in the
        // `namedZoneOffsets` doc comment: `DateFormatter`'s `zzz` with `en_US_POSIX`
        // recognizes "CST" as US Central Standard Time (UTC-6), so the input is
        // matched by the explicit-zone pass *before* the named-zone substitution
        // table (which would resolve "CST" to China Standard Time, UTC+8) is ever
        // consulted. If `en_US_POSIX` ever stops recognizing CST, or if the parse
        // passes are reordered, US Central feeds would silently shift by 14 hours
        // — this test must fail in that case.
        //
        // 08:30 CST (UTC-6, US Central) = 14:30 UTC. China would be 00:30 UTC.
        let xml = Self.rssXML(pubDate: "Mon, 06 Apr 2026 08:30:00 CST")
        let feed = try service.parse(Data(xml.utf8))

        let date = try #require(feed.articles[0].publishedDate)
        let expected = try Self.utcDate(year: 2026, month: 4, day: 6, hour: 14, minute: 30)
        #expect(date == expected)
    }

    @Test("RSS pubDate with trailing whitespace after named zone parses correctly")
    func rssPubDateNamedZoneTrailingWhitespace() throws {
        // Regression guard: without input trimming, the trailing token of
        // `"...08:30:00 CET "` is the empty string after the final space, so the
        // named-zone lookup misses and the input falls through to the zoneless
        // UTC fallback — silently producing a date that is 1 hour off. The
        // `substituteNamedZone` helper trims the input before tokenizing so feeds
        // emitting trailing whitespace still resolve to the correct moment.
        //
        // 08:30 CET (UTC+1) = 07:30 UTC.
        let xml = Self.rssXML(pubDate: "Mon, 06 Apr 2026 08:30:00 CET ")
        let feed = try service.parse(Data(xml.utf8))

        let date = try #require(feed.articles[0].publishedDate)
        let expected = try Self.utcDate(year: 2026, month: 4, day: 6, hour: 7, minute: 30)
        #expect(date == expected)
    }

    @Test("RSS pubDate with UT alias parses to UTC")
    func rssPubDateNamedZoneUTAlias() throws {
        // RFC 822 explicitly defines "UT" (no trailing C) as an alias for Universal
        // Time. Whether the substitution pass or `DateFormatter`'s `zzz` matches it
        // first, the resolved moment must be the literal wall-clock time interpreted
        // as UTC (08:30 UT = 08:30 UTC). This test documents the current behavior
        // and acts as a defense-in-depth guard against the table entry being
        // accidentally removed.
        let xml = Self.rssXML(pubDate: "Mon, 06 Apr 2026 08:30:00 UT")
        let feed = try service.parse(Data(xml.utf8))

        let date = try #require(feed.articles[0].publishedDate)
        let expected = try Self.utcDate(year: 2026, month: 4, day: 6, hour: 8, minute: 30)
        #expect(date == expected)
    }

    // MARK: - Date Parsing (Hoisted Formatter Stability)

    // The two tests below pin down the contract that motivated PR #241: hoisting the
    // per-call `DateFormatter` allocations into static `HoistedDateFormatters` entries
    // must not introduce any cross-call state leakage. They exercise the contract
    // behaviorally, without reaching into the private enum.

    @Test("Repeated parses of the same input return identical dates")
    func repeatedParsesAreStable() throws {
        // A "first call configures, second call sees stale state" regression in the
        // hoisted formatters would manifest as the second parse returning a different
        // (or nil) date. Two back-to-back parses are the cheapest way to catch that.
        let xml = Self.rssXML(pubDate: "Mon, 06 Apr 2026 08:30:00 PDT")
        let first = try service.parse(Data(xml.utf8)).articles[0].publishedDate
        let second = try service.parse(Data(xml.utf8)).articles[0].publishedDate

        #expect(first != nil)
        #expect(first == second)
    }

    @Test("parseDate is safe to call concurrently from multiple feeds")
    func parseDateConcurrentCallsAreThreadSafe() async throws {
        // PR #241 claims the hoisted formatters are safe to use from concurrent feed
        // refreshes without locking. This test makes that claim executable: it parses
        // a mix of formats from many concurrent Tasks and asserts every Task observed
        // the same dates. A regression that re-introduced mid-parse mutation would
        // typically surface here as a nil entry, a mismatched vector, or a TSan report.
        let inputs = [
            "Mon, 06 Apr 2026 08:30:00 -0700",
            "Mon, 06 Apr 2026 08:30:00 PDT",
            "Mon, 06 Apr 2026 08:30 EST",
            "2026-04-06 08:30:00",
            "2026-04-06T08:30:00.123Z",
        ]
        // RATIONALE: capture as a local `let` so the closure does not capture `self`,
        // which simplifies Sendable checking under Swift 6 strict concurrency.
        // `RSSParsingService` is a `Sendable` struct, so this copy is cheap and safe.
        let service = self.service
        let results = await withTaskGroup(of: [Date?].self) { group in
            for _ in 0..<32 {
                group.addTask {
                    inputs.map { input in
                        let xml = Self.rssXML(pubDate: input)
                        return (try? service.parse(Data(xml.utf8)))?.articles.first?.publishedDate
                    }
                }
            }
            return await group.reduce(into: [[Date?]]()) { $0.append($1) }
        }

        let reference = try #require(results.first)
        #expect(reference.count == inputs.count)
        for date in reference {
            #expect(date != nil)
        }
        for vector in results {
            #expect(vector == reference)
        }
    }

    /// Builds a minimal RSS feed containing one `<item>` per supplied `pubDate` string.
    /// Each item gets a unique guid so the parser keeps them as distinct articles in
    /// document order. Used by the multi-format integration test below to drive a
    /// single `parse(_:)` call across the full date-parser chain.
    private static func rssXML(pubDates: [String]) -> String {
        let items = pubDates.enumerated().map { index, pubDate in
            """
                <item>
                    <title>Item \(index)</title>
                    <link>https://example.com/item-\(index)</link>
                    <guid>item-\(index)</guid>
                    <pubDate>\(pubDate)</pubDate>
                </item>
            """
        }.joined(separator: "\n")
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0">
        <channel>
            <title>Multi-Format Date Test Feed</title>
            <link>https://example.com</link>
            <description>Feed</description>
        \(items)
        </channel>
        </rss>
        """
    }

    @Test("Single feed with many distinct date formats parses every item to the correct UTC moment")
    func multiFormatPerFeedParsesAllItems() throws {
        // Integration-style guard for the realistic refresh path that motivated PR #241:
        // a single `parse(_:)` call walks dozens of items, and the hoisted-formatter
        // refactor specifically targeted that hot loop. The single-item helpers used by
        // the rest of this section never exercise mid-parse iteration through the
        // formatter list, so a regression that corrupted state for subsequent items in
        // the same feed (e.g., a future "first call configures" mistake reintroduced at
        // a different layer) would slip past the existing repeated-parse and concurrent
        // tests. This test parses one feed whose items deliberately span every distinct
        // branch of the parser chain — ISO 8601 (with `Z`, with fractional seconds,
        // numeric offset), explicit-zone RFC 822 (numeric, US named, single-digit day),
        // named non-US zone via the substitution pass, SQL-style space separator with
        // numeric zone, and the zoneless RFC 822 / ISO 8601 fallbacks — and asserts
        // every parsed `publishedDate` matches the expected absolute UTC moment.
        //
        // The published dates below all encode the same wall-clock instant in their
        // respective zones so the assertion vector is uniform: 06 Apr 2026 15:30:00 UTC.
        // Items are listed in the same order the parser is expected to surface them.
        let cases: [(pubDate: String, label: String)] = [
            // ISO 8601 with `Z` literal — first parser in the chain.
            ("2026-04-06T15:30:00Z", "ISO 8601 Z"),
            // ISO 8601 with fractional seconds and numeric offset — second parser.
            ("2026-04-06T08:30:00.000-07:00", "ISO 8601 fractional"),
            // RFC 822 with numeric offset — most common explicit-zone format.
            ("Mon, 06 Apr 2026 08:30:00 -0700", "RFC 822 numeric"),
            // RFC 822 with US named zone — exercises `zzz` with `en_US_POSIX`.
            ("Mon, 06 Apr 2026 11:30:00 EDT", "RFC 822 named EDT"),
            // RFC 822 single-digit day variant.
            ("Mon, 6 Apr 2026 08:30:00 -0700", "RFC 822 single-digit day"),
            // Non-US named zone — exercises the substituteNamedZone preprocessing pass.
            ("Mon, 06 Apr 2026 16:30:00 CET", "named CET via substitution"),
            // Another non-US named zone (different offset) to ensure substitution does
            // not leak state across items.
            ("Mon, 06 Apr 2026 17:30:00 CEST", "named CEST via substitution"),
            // SQL-style space separator with numeric zone.
            ("2026-04-06 08:30:00-0700", "SQL space separator"),
            // Zoneless RFC 822 — falls through to the documented UTC fallback.
            ("Mon, 06 Apr 2026 15:30:00", "zoneless RFC 822"),
            // Zoneless ISO 8601 — falls through to the documented UTC fallback.
            ("2026-04-06T15:30:00", "zoneless ISO 8601"),
        ]

        let xml = Self.rssXML(pubDates: cases.map(\.pubDate))
        let feed = try service.parse(Data(xml.utf8))

        #expect(feed.articles.count == cases.count)

        let expected = try Self.utcDate(year: 2026, month: 4, day: 6, hour: 15, minute: 30)
        for (index, testCase) in cases.enumerated() {
            let date = try #require(
                feed.articles[index].publishedDate,
                "publishedDate was nil for item \(index) (\(testCase.label), input '\(testCase.pubDate)')"
            )
            #expect(
                date == expected,
                "item \(index) (\(testCase.label), input '\(testCase.pubDate)') parsed to \(date), expected \(expected)"
            )
        }
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
