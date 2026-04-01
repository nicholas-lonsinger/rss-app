import Foundation
@testable import RSSApp

enum TestFixtures {

    // MARK: - Sample RSS XML

    static let sampleRSSXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0" xmlns:media="http://search.yahoo.com/mrss/">
        <channel>
            <title>Test Feed</title>
            <link>https://example.com</link>
            <description>A test RSS feed</description>
            <item>
                <title>First Article</title>
                <link>https://example.com/article-1</link>
                <description><![CDATA[<p>This is the <b>first</b> article content.</p><img src="https://example.com/img1.jpg">]]></description>
                <guid>article-1-guid</guid>
                <pubDate>Mon, 30 Mar 2026 12:00:00 +0000</pubDate>
                <media:thumbnail url="https://example.com/thumb1.jpg" />
            </item>
            <item>
                <title>Second Article</title>
                <link>https://example.com/article-2</link>
                <description>Plain text description without HTML</description>
                <guid>article-2-guid</guid>
                <pubDate>Sun, 29 Mar 2026 10:30:00 +0000</pubDate>
                <enclosure url="https://example.com/enclosure.jpg" type="image/jpeg" length="12345" />
            </item>
            <item>
                <title>Third Article</title>
                <link>https://example.com/article-3</link>
                <description><![CDATA[<p>Article with image in body</p><img src="https://example.com/body-img.jpg"><p>More text</p>]]></description>
                <pubDate>Sat, 28 Mar 2026 08:00:00 +0000</pubDate>
            </item>
        </channel>
        </rss>
        """

    static let sampleRSSXMLNoImages = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0">
        <channel>
            <title>No Images Feed</title>
            <link>https://example.com</link>
            <description>Feed without images</description>
            <item>
                <title>Text Only</title>
                <link>https://example.com/text-only</link>
                <description>Just plain text here, no images at all.</description>
                <guid>text-only-guid</guid>
            </item>
        </channel>
        </rss>
        """

    static let malformedXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0">
        <channel>
            <title>Broken
            <item>
                <title>Unclosed
        """

    static let emptyChannelXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0">
        <channel>
            <title>Empty Feed</title>
            <link>https://example.com</link>
            <description>No items</description>
        </channel>
        </rss>
        """

    static let mediaContentXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0" xmlns:media="http://search.yahoo.com/mrss/">
        <channel>
            <title>Media Content Feed</title>
            <link>https://example.com</link>
            <description>Feed with media:content</description>
            <item>
                <title>Media Article</title>
                <link>https://example.com/media</link>
                <description>Has media content</description>
                <guid>media-guid</guid>
                <media:content url="https://example.com/media-img.jpg" medium="image" />
            </item>
        </channel>
        </rss>
        """

    static let thumbnailPriorityXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0" xmlns:media="http://search.yahoo.com/mrss/">
        <channel>
            <title>Priority Feed</title>
            <link>https://example.com</link>
            <description>Tests thumbnail priority</description>
            <item>
                <title>Priority Article</title>
                <link>https://example.com/priority</link>
                <description><![CDATA[<img src="https://example.com/body-img.jpg">]]></description>
                <guid>priority-guid</guid>
                <media:thumbnail url="https://example.com/thumb.jpg" />
                <enclosure url="https://example.com/enclosure.jpg" type="image/jpeg" length="100" />
            </item>
        </channel>
        </rss>
        """

    // MARK: - Factory Methods

    static func makeArticle(
        id: String = "test-id",
        title: String = "Test Article",
        link: URL? = URL(string: "https://example.com/article"),
        articleDescription: String = "<p>Test description</p>",
        snippet: String = "Test description",
        publishedDate: Date? = Date(timeIntervalSince1970: 1_711_800_000),
        thumbnailURL: URL? = URL(string: "https://example.com/thumb.jpg")
    ) -> Article {
        Article(
            id: id,
            title: title,
            link: link,
            articleDescription: articleDescription,
            snippet: snippet,
            publishedDate: publishedDate,
            thumbnailURL: thumbnailURL
        )
    }

    static func makeSubscribedFeed(
        id: UUID = UUID(),
        title: String = "Test Feed",
        url: URL = URL(string: "https://example.com/feed")!,
        feedDescription: String = "A test feed",
        addedDate: Date = Date(timeIntervalSince1970: 1_711_800_000)
    ) -> SubscribedFeed {
        SubscribedFeed(
            id: id,
            title: title,
            url: url,
            feedDescription: feedDescription,
            addedDate: addedDate
        )
    }

    static func makeFeed(
        title: String = "Test Feed",
        link: URL? = URL(string: "https://example.com"),
        feedDescription: String = "A test feed",
        articles: [Article] = []
    ) -> RSSFeed {
        RSSFeed(
            title: title,
            link: link,
            feedDescription: feedDescription,
            articles: articles
        )
    }
}
