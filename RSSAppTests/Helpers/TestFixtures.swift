import Foundation
import SwiftData
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

    static let atomXHTMLContentXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
            <title>XHTML Feed</title>
            <link rel="alternate" href="https://example.com" />
            <id>https://example.com/xhtml-feed</id>
            <updated>2026-04-01T00:00:00Z</updated>
            <entry>
                <title>XHTML Entry</title>
                <link rel="alternate" href="https://example.com/xhtml-1" />
                <id>xhtml-entry-1</id>
                <published>2026-04-01T10:00:00Z</published>
                <content type="xhtml">
                    <div xmlns="http://www.w3.org/1999/xhtml">
                        <p>This is <b>bold</b> and <em>italic</em> text.</p>
                        <img src="https://example.com/xhtml-img.jpg" alt="test"/>
                    </div>
                </content>
            </entry>
            <entry>
                <title>XHTML Summary Entry</title>
                <link rel="alternate" href="https://example.com/xhtml-2" />
                <id>xhtml-entry-2</id>
                <published>2026-04-01T09:00:00Z</published>
                <summary type="xhtml">
                    <div xmlns="http://www.w3.org/1999/xhtml">
                        <p>Summary in XHTML format.</p>
                    </div>
                </summary>
            </entry>
            <entry>
                <title>XHTML Content With Summary Fallback</title>
                <link rel="alternate" href="https://example.com/xhtml-3" />
                <id>xhtml-entry-3</id>
                <published>2026-04-01T08:00:00Z</published>
                <summary type="xhtml">
                    <div xmlns="http://www.w3.org/1999/xhtml">
                        <p>Should be ignored.</p>
                    </div>
                </summary>
                <content type="xhtml">
                    <div xmlns="http://www.w3.org/1999/xhtml">
                        <p>Content wins over summary.</p>
                    </div>
                </content>
            </entry>
        </feed>
        """

    static let atomSelfLinkOnlyXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
            <title>Self Link Only Feed</title>
            <link rel="self" type="application/atom+xml" href="https://example.com/atom.xml" />
            <id>https://example.com/atom.xml</id>
            <updated>2026-04-01T00:00:00Z</updated>
            <entry>
                <title>Entry One</title>
                <link rel="alternate" href="https://example.com/entry-1" />
                <id>entry-1-id</id>
                <published>2026-04-01T10:00:00Z</published>
                <summary>An entry in a self-link-only feed</summary>
            </entry>
        </feed>
        """

    static let atomCategoriesXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
            <title>Categories Feed</title>
            <link rel="alternate" href="https://example.com" />
            <id>https://example.com/cat-feed</id>
            <updated>2026-04-01T00:00:00Z</updated>
            <entry>
                <title>Tagged Entry</title>
                <link rel="alternate" href="https://example.com/tagged" />
                <id>tagged-entry</id>
                <published>2026-04-01T10:00:00Z</published>
                <category term="swift" />
                <category term="ios" />
                <category term="development" />
                <summary>Entry with Atom categories</summary>
            </entry>
        </feed>
        """

    static let atomCategoryDoubleCountXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
            <title>Double Count Feed</title>
            <link rel="alternate" href="https://example.com" />
            <id>https://example.com/dc-feed</id>
            <updated>2026-04-01T00:00:00Z</updated>
            <entry>
                <title>Double Count Entry</title>
                <link rel="alternate" href="https://example.com/dc-entry" />
                <id>dc-entry-id</id>
                <published>2026-04-01T10:00:00Z</published>
                <category term="tech">Technology</category>
                <category term="swift">Swift Programming</category>
                <summary>Entry with category term and text content</summary>
            </entry>
        </feed>
        """

    static let rssCategoriesXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0">
        <channel>
            <title>RSS Categories Feed</title>
            <link>https://example.com</link>
            <description>Feed with categories</description>
            <item>
                <title>Tagged Item</title>
                <link>https://example.com/tagged-rss</link>
                <guid>tagged-rss-guid</guid>
                <category>technology</category>
                <category>programming</category>
                <description>Item with RSS categories</description>
            </item>
        </channel>
        </rss>
        """

    static let atomEnclosureLinkXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
            <title>Enclosure Feed</title>
            <link rel="alternate" href="https://example.com" />
            <id>https://example.com/enc-feed</id>
            <updated>2026-04-01T00:00:00Z</updated>
            <entry>
                <title>Entry With Enclosure</title>
                <link rel="alternate" href="https://example.com/enc-entry" />
                <link rel="enclosure" type="image/png" href="https://example.com/enclosure-img.png" />
                <id>enc-entry-id</id>
                <published>2026-04-01T10:00:00Z</published>
                <summary>Entry with Atom enclosure link</summary>
            </entry>
        </feed>
        """

    static let rssAuthorXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0">
        <channel>
            <title>Author Feed</title>
            <link>https://example.com</link>
            <description>Feed with authors</description>
            <item>
                <title>Authored Item</title>
                <link>https://example.com/authored</link>
                <guid>authored-guid</guid>
                <author>jane@example.com (Jane Doe)</author>
                <description>Article by Jane</description>
            </item>
        </channel>
        </rss>
        """

    static let rssLastBuildDateXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0">
        <channel>
            <title>Dated Feed</title>
            <link>https://example.com</link>
            <description>Feed with lastBuildDate</description>
            <lastBuildDate>Mon, 30 Mar 2026 12:00:00 +0000</lastBuildDate>
            <item>
                <title>An Item</title>
                <link>https://example.com/item</link>
                <description>Just an item</description>
            </item>
        </channel>
        </rss>
        """

    // MARK: - Channel Logo XML

    static let rssWithImageXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0">
        <channel>
            <title>Logo Feed</title>
            <link>https://example.com</link>
            <description>Feed with channel image</description>
            <image>
                <url>https://example.com/logo.png</url>
                <title>Logo Feed</title>
                <link>https://example.com</link>
            </image>
            <item>
                <title>An Item</title>
                <link>https://example.com/item</link>
                <description>Just an item</description>
            </item>
        </channel>
        </rss>
        """

    static let atomWithLogoXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
            <title>Atom Logo Feed</title>
            <link rel="alternate" href="https://example.com" />
            <id>https://example.com/feed</id>
            <updated>2026-04-01T00:00:00Z</updated>
            <logo>https://example.com/atom-logo.png</logo>
            <entry>
                <title>An Entry</title>
                <link rel="alternate" href="https://example.com/entry" />
                <id>entry-id</id>
                <published>2026-04-01T10:00:00Z</published>
                <summary>An entry</summary>
            </entry>
        </feed>
        """

    static let atomWithIconXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
            <title>Atom Icon Feed</title>
            <link rel="alternate" href="https://example.com" />
            <id>https://example.com/feed</id>
            <updated>2026-04-01T00:00:00Z</updated>
            <icon>https://example.com/favicon.ico</icon>
            <entry>
                <title>An Entry</title>
                <link rel="alternate" href="https://example.com/entry" />
                <id>entry-id</id>
                <published>2026-04-01T10:00:00Z</published>
                <summary>An entry</summary>
            </entry>
        </feed>
        """

    static let atomWithLogoAndIconXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
            <title>Atom Both Feed</title>
            <link rel="alternate" href="https://example.com" />
            <id>https://example.com/feed</id>
            <updated>2026-04-01T00:00:00Z</updated>
            <icon>https://example.com/favicon.ico</icon>
            <logo>https://example.com/atom-logo.png</logo>
            <entry>
                <title>An Entry</title>
                <link rel="alternate" href="https://example.com/entry" />
                <id>entry-id</id>
                <published>2026-04-01T10:00:00Z</published>
                <summary>An entry</summary>
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
        thumbnailURL: URL? = URL(string: "https://example.com/thumb.jpg"),
        author: String? = nil,
        categories: [String] = []
    ) -> Article {
        Article(
            id: id,
            title: title,
            link: link,
            articleDescription: articleDescription,
            snippet: snippet,
            publishedDate: publishedDate,
            thumbnailURL: thumbnailURL,
            author: author,
            categories: categories
        )
    }

    static func makeSubscribedFeed(
        id: UUID = UUID(),
        title: String = "Test Feed",
        url: URL = URL(string: "https://example.com/feed")!,
        feedDescription: String = "A test feed",
        addedDate: Date = Date(timeIntervalSince1970: 1_711_800_000),
        lastFetchError: String? = nil,
        lastFetchErrorDate: Date? = nil
    ) -> SubscribedFeed {
        SubscribedFeed(
            id: id,
            title: title,
            url: url,
            feedDescription: feedDescription,
            addedDate: addedDate,
            lastFetchError: lastFetchError,
            lastFetchErrorDate: lastFetchErrorDate
        )
    }

    static func makeFeed(
        title: String = "Test Feed",
        link: URL? = URL(string: "https://example.com"),
        feedDescription: String = "A test feed",
        articles: [Article] = [],
        lastUpdated: Date? = nil,
        imageURL: URL? = nil
    ) -> RSSFeed {
        RSSFeed(
            title: title,
            link: link,
            feedDescription: feedDescription,
            articles: articles,
            lastUpdated: lastUpdated,
            imageURL: imageURL
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

    // MARK: - Persistent Model Factories

    static func makePersistentFeed(
        id: UUID = UUID(),
        title: String = "Test Feed",
        feedURL: URL = URL(string: "https://example.com/feed")!,
        feedDescription: String = "A test feed",
        addedDate: Date = Date(timeIntervalSince1970: 1_711_800_000),
        iconURL: URL? = nil,
        lastFetchError: String? = nil,
        lastFetchErrorDate: Date? = nil
    ) -> PersistentFeed {
        PersistentFeed(
            id: id,
            title: title,
            feedURL: feedURL,
            feedDescription: feedDescription,
            addedDate: addedDate,
            iconURL: iconURL,
            lastFetchError: lastFetchError,
            lastFetchErrorDate: lastFetchErrorDate
        )
    }

    static func makePersistentArticle(
        articleID: String = "test-article-id",
        title: String = "Test Article",
        link: URL? = URL(string: "https://example.com/article"),
        articleDescription: String = "<p>Test description</p>",
        snippet: String = "Test description",
        publishedDate: Date? = Date(timeIntervalSince1970: 1_711_800_000),
        thumbnailURL: URL? = URL(string: "https://example.com/thumb.jpg"),
        author: String? = nil,
        categories: [String] = [],
        isRead: Bool = false,
        isSaved: Bool = false,
        savedDate: Date? = nil,
        isThumbnailCached: Bool = false,
        thumbnailRetryCount: Int = 0,
        sortDate: Date? = nil
    ) -> PersistentArticle {
        // Forward `sortDate` directly: the designated init defaults it to
        // `PersistentArticle.clampedSortDate(publishedDate:)`, which is the same
        // formula production uses via the `init(from: Article)` convenience init.
        // This guarantees the fixture cannot drift from production semantics — even
        // if a test passes a future `publishedDate`, the helper produces an article
        // whose `sortDate` is clamped to "now" exactly the way production would.
        PersistentArticle(
            articleID: articleID,
            title: title,
            link: link,
            articleDescription: articleDescription,
            snippet: snippet,
            publishedDate: publishedDate,
            thumbnailURL: thumbnailURL,
            author: author,
            categories: categories,
            isRead: isRead,
            isSaved: isSaved,
            savedDate: savedDate,
            isThumbnailCached: isThumbnailCached,
            thumbnailRetryCount: thumbnailRetryCount,
            sortDate: sortDate
        )
    }

    static func makeArticleContent(
        title: String = "Test Article",
        byline: String? = "Test Author",
        htmlContent: String = "<p>Test content</p>",
        textContent: String = "Test content"
    ) -> ArticleContent {
        ArticleContent(
            title: title,
            byline: byline,
            htmlContent: htmlContent,
            textContent: textContent
        )
    }
}
