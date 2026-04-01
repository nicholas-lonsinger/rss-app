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

    // MARK: - Sample Atom XML

    static let sampleAtomXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
            <title type="text">Atom Test Feed</title>
            <subtitle type="text">A test Atom feed description</subtitle>
            <link rel="alternate" type="text/html" href="https://example.com" />
            <link rel="self" type="application/atom+xml" href="https://example.com/atom.xml" />
            <id>https://example.com/atom.xml</id>
            <updated>2026-04-01T12:00:00+00:00</updated>
            <entry>
                <author><name>Alice</name></author>
                <title type="html"><![CDATA[First Atom Entry]]></title>
                <link rel="alternate" type="text/html" href="https://example.com/entry-1" />
                <id>entry-1-id</id>
                <published>2026-04-01T10:00:00-04:00</published>
                <updated>2026-04-01T11:00:00-04:00</updated>
                <summary type="html"><![CDATA[<p>Short summary of first entry</p>]]></summary>
                <content type="html"><![CDATA[<p>Full content of the <b>first</b> entry with more detail.</p><img src="https://example.com/img1.jpg">]]></content>
            </entry>
            <entry>
                <author><name>Bob</name></author>
                <title type="html"><![CDATA[Second Atom Entry]]></title>
                <link rel="alternate" type="text/html" href="https://example.com/entry-2" />
                <id>entry-2-id</id>
                <published>2026-03-31T08:30:00+00:00</published>
                <summary type="html"><![CDATA[Summary only, no content element.]]></summary>
            </entry>
        </feed>
        """

    static let atomNoContentXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
            <title>Minimal Atom</title>
            <link rel="alternate" href="https://example.com" />
            <id>https://example.com/feed</id>
            <updated>2026-04-01T00:00:00Z</updated>
            <entry>
                <title>Summary Only</title>
                <link rel="alternate" href="https://example.com/summary-only" />
                <id>summary-only-id</id>
                <updated>2026-04-01T00:00:00Z</updated>
                <summary>Plain text summary with no HTML</summary>
            </entry>
        </feed>
        """

    // MARK: - Sample OPML XML

    static let sampleOPML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <opml version="2.0">
          <head><title>Test Subscriptions</title></head>
          <body>
            <outline text="Feed One" type="rss" xmlUrl="https://one.com/feed" htmlUrl="https://one.com" description="First feed"/>
            <outline text="Feed Two" type="rss" xmlUrl="https://two.com/feed" description="Second feed"/>
            <outline text="Feed Three" type="rss" xmlUrl="https://three.com/feed"/>
          </body>
        </opml>
        """

    static let nestedOPML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <opml version="2.0">
          <head><title>Nested Subscriptions</title></head>
          <body>
            <outline text="Tech" title="Tech">
              <outline text="Ars Technica" type="rss" xmlUrl="https://arstechnica.com/feed"/>
              <outline text="The Verge" type="rss" xmlUrl="https://theverge.com/feed"/>
            </outline>
            <outline text="Top Level Feed" type="rss" xmlUrl="https://top.com/feed"/>
          </body>
        </opml>
        """

    static let emptyBodyOPML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <opml version="2.0">
          <head><title>Empty</title></head>
          <body/>
        </opml>
        """

    static let malformedOPML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <opml version="2.0">
          <head><title>Broken
        """

    static let noBodyOPML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <opml version="2.0">
          <head><title>No Body</title></head>
        </opml>
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

    static func makeOPMLFeedEntry(
        title: String = "Test Feed",
        feedURL: URL = URL(string: "https://example.com/feed")!,
        siteURL: URL? = URL(string: "https://example.com"),
        description: String = "A test feed"
    ) -> OPMLFeedEntry {
        OPMLFeedEntry(
            title: title,
            feedURL: feedURL,
            siteURL: siteURL,
            description: description
        )
    }
}
