import Testing
import Foundation
import SwiftData
@testable import RSSApp

@Suite("FeedPersistenceService Tests", .serialized)
struct FeedPersistenceServiceTests {

    @MainActor
    private func makeService() throws -> (SwiftDataFeedPersistenceService, ModelContainer) {
        try SwiftDataTestHelpers.makeTestPersistenceService()
    }

    // MARK: - Feed Operations

    @Test("allFeeds returns empty array initially")
    @MainActor
    func allFeedsEmpty() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feeds = try service.allFeeds()
        #expect(feeds.isEmpty)
    }

    @Test("addFeed persists a feed")
    @MainActor
    func addFeedPersists() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feed = TestFixtures.makePersistentFeed(title: "My Feed")

        try service.addFeed(feed)
        let feeds = try service.allFeeds()

        #expect(feeds.count == 1)
        #expect(feeds[0].title == "My Feed")
    }

    @Test("deleteFeed removes a feed")
    @MainActor
    func deleteFeedRemoves() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feed = TestFixtures.makePersistentFeed()

        try service.addFeed(feed)
        try service.deleteFeed(feed)
        let feeds = try service.allFeeds()

        #expect(feeds.isEmpty)
    }

    @Test("updateFeedMetadata updates title and description, clears error state")
    @MainActor
    func updateFeedMetadata() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feed = TestFixtures.makePersistentFeed(
            title: "Old Title",
            lastFetchError: "some error",
            lastFetchErrorDate: Date()
        )

        try service.addFeed(feed)
        try service.updateFeedMetadata(feed, title: "New Title", description: "New Desc")

        #expect(feed.title == "New Title")
        #expect(feed.feedDescription == "New Desc")
        #expect(feed.lastRefreshDate != nil)
        #expect(feed.lastFetchError == nil)
        #expect(feed.lastFetchErrorDate == nil)
    }

    @Test("updateFeedError sets error state")
    @MainActor
    func updateFeedError() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feed = TestFixtures.makePersistentFeed()

        try service.addFeed(feed)
        try service.updateFeedError(feed, error: "Network error")

        #expect(feed.lastFetchError == "Network error")
        #expect(feed.lastFetchErrorDate != nil)
    }

    @Test("updateFeedError with nil clears error state")
    @MainActor
    func updateFeedErrorClears() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feed = TestFixtures.makePersistentFeed(
            lastFetchError: "old error",
            lastFetchErrorDate: Date()
        )

        try service.addFeed(feed)
        try service.updateFeedError(feed, error: nil)

        #expect(feed.lastFetchError == nil)
        #expect(feed.lastFetchErrorDate == nil)
    }

    @Test("updateFeedURL changes URL and clears error state")
    @MainActor
    func updateFeedURL() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feed = TestFixtures.makePersistentFeed(
            lastFetchError: "error",
            lastFetchErrorDate: Date()
        )

        try service.addFeed(feed)
        let newURL = URL(string: "https://new.example.com/feed")!
        try service.updateFeedURL(feed, newURL: newURL)

        #expect(feed.feedURL == newURL)
        #expect(feed.lastFetchError == nil)
    }

    @Test("feedExists returns true for existing URL")
    @MainActor
    func feedExistsTrue() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let url = URL(string: "https://example.com/feed")!
        let feed = TestFixtures.makePersistentFeed(feedURL: url)

        try service.addFeed(feed)

        #expect(try service.feedExists(url: url))
    }

    @Test("feedExists returns false for unknown URL")
    @MainActor
    func feedExistsFalse() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let url = URL(string: "https://unknown.com/feed")!

        #expect(try !service.feedExists(url: url))
    }

    @Test("updateFeedCacheHeaders stores etag and lastModified")
    @MainActor
    func updateCacheHeaders() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feed = TestFixtures.makePersistentFeed()

        try service.addFeed(feed)
        try service.updateFeedCacheHeaders(feed, etag: "abc123", lastModified: "Mon, 01 Jan 2026 00:00:00 GMT")

        #expect(feed.etag == "abc123")
        #expect(feed.lastModifiedHeader == "Mon, 01 Jan 2026 00:00:00 GMT")
    }

    // MARK: - Article Operations

    @Test("upsertArticles inserts new articles")
    @MainActor
    func upsertArticlesInserts() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feed = TestFixtures.makePersistentFeed()
        try service.addFeed(feed)

        let articles = [
            TestFixtures.makeArticle(id: "a1", title: "Article 1"),
            TestFixtures.makeArticle(id: "a2", title: "Article 2"),
        ]

        try service.upsertArticles(articles, for: feed)
        let persisted = try service.articles(for: feed)

        #expect(persisted.count == 2)
    }

    @Test("upsertArticles skips existing articles preserving read status")
    @MainActor
    func upsertArticlesSkipsExisting() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feed = TestFixtures.makePersistentFeed()
        try service.addFeed(feed)

        let articles = [TestFixtures.makeArticle(id: "a1", title: "Original")]
        try service.upsertArticles(articles, for: feed)

        // Mark as read
        let persisted = try service.articles(for: feed)
        try service.markArticleRead(persisted[0], isRead: true)

        // Upsert same article again
        let updatedArticles = [TestFixtures.makeArticle(id: "a1", title: "Updated")]
        try service.upsertArticles(updatedArticles, for: feed)

        let afterUpsert = try service.articles(for: feed)
        #expect(afterUpsert.count == 1)
        #expect(afterUpsert[0].isRead == true)
    }

    @Test("markArticleRead toggles read status")
    @MainActor
    func markArticleRead() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feed = TestFixtures.makePersistentFeed()
        try service.addFeed(feed)
        try service.upsertArticles([TestFixtures.makeArticle(id: "a1")], for: feed)

        let articles = try service.articles(for: feed)
        #expect(articles[0].isRead == false)

        try service.markArticleRead(articles[0], isRead: true)
        #expect(articles[0].isRead == true)
        #expect(articles[0].readDate != nil)

        try service.markArticleRead(articles[0], isRead: false)
        #expect(articles[0].isRead == false)
        #expect(articles[0].readDate == nil)
    }

    @Test("unreadCount returns correct count")
    @MainActor
    func unreadCountCorrect() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feed = TestFixtures.makePersistentFeed()
        try service.addFeed(feed)

        let articles = [
            TestFixtures.makeArticle(id: "a1"),
            TestFixtures.makeArticle(id: "a2"),
            TestFixtures.makeArticle(id: "a3"),
        ]
        try service.upsertArticles(articles, for: feed)

        #expect(try service.unreadCount(for: feed) == 3)

        let persisted = try service.articles(for: feed)
        try service.markArticleRead(persisted[0], isRead: true)

        #expect(try service.unreadCount(for: feed) == 2)
    }

    // MARK: - Cross-Feed Article Queries

    @Test("allArticles returns articles from all feeds sorted by date descending")
    @MainActor
    func allArticlesAcrossFeeds() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feed1 = TestFixtures.makePersistentFeed(title: "Feed 1", feedURL: URL(string: "https://one.com/feed")!)
        let feed2 = TestFixtures.makePersistentFeed(title: "Feed 2", feedURL: URL(string: "https://two.com/feed")!)
        try service.addFeed(feed1)
        try service.addFeed(feed2)

        try service.upsertArticles([
            TestFixtures.makeArticle(id: "a1", publishedDate: Date(timeIntervalSince1970: 1_000_000)),
        ], for: feed1)
        try service.upsertArticles([
            TestFixtures.makeArticle(id: "a2", publishedDate: Date(timeIntervalSince1970: 2_000_000)),
        ], for: feed2)
        try service.save()

        let all = try service.allArticles()
        #expect(all.count == 2)
        #expect(all[0].articleID == "a2")
        #expect(all[1].articleID == "a1")
    }

    @Test("allUnreadArticles returns only unread articles across feeds")
    @MainActor
    func allUnreadArticlesFilters() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feed = TestFixtures.makePersistentFeed()
        try service.addFeed(feed)

        try service.upsertArticles([
            TestFixtures.makeArticle(id: "a1", publishedDate: Date(timeIntervalSince1970: 2_000_000)),
            TestFixtures.makeArticle(id: "a2", publishedDate: Date(timeIntervalSince1970: 1_000_000)),
        ], for: feed)
        try service.save()

        // articles(for:) sorts by publishedDate descending, so a1 is first
        let articles = try service.articles(for: feed)
        #expect(articles[0].articleID == "a1")
        try service.markArticleRead(articles[0], isRead: true)

        let unread = try service.allUnreadArticles()
        #expect(unread.count == 1)
        #expect(unread[0].articleID == "a2")
    }

    @Test("totalUnreadCount returns sum across all feeds")
    @MainActor
    func totalUnreadCountAcrossFeeds() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feed1 = TestFixtures.makePersistentFeed(title: "Feed 1", feedURL: URL(string: "https://one.com/feed")!)
        let feed2 = TestFixtures.makePersistentFeed(title: "Feed 2", feedURL: URL(string: "https://two.com/feed")!)
        try service.addFeed(feed1)
        try service.addFeed(feed2)

        try service.upsertArticles([
            TestFixtures.makeArticle(id: "a1"),
            TestFixtures.makeArticle(id: "a2"),
        ], for: feed1)
        try service.upsertArticles([
            TestFixtures.makeArticle(id: "a3"),
        ], for: feed2)
        try service.save()

        #expect(try service.totalUnreadCount() == 3)

        let articles = try service.articles(for: feed1)
        try service.markArticleRead(articles[0], isRead: true)

        #expect(try service.totalUnreadCount() == 2)
    }

    // MARK: - Paginated Article Queries

    @Test("allArticles(offset:limit:) returns correct page")
    @MainActor
    func allArticlesPaginated() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feed = TestFixtures.makePersistentFeed()
        try service.addFeed(feed)

        // Insert 5 articles with distinct dates
        for i in 0..<5 {
            try service.upsertArticles([
                TestFixtures.makeArticle(
                    id: "a\(i)",
                    publishedDate: Date(timeIntervalSince1970: Double(i) * 1_000_000)
                ),
            ], for: feed)
        }
        try service.save()

        // First page: offset 0, limit 2 (should get newest two: a4, a3)
        let page1 = try service.allArticles(offset: 0, limit: 2)
        #expect(page1.count == 2)
        #expect(page1[0].articleID == "a4")
        #expect(page1[1].articleID == "a3")

        // Second page: offset 2, limit 2 (should get a2, a1)
        let page2 = try service.allArticles(offset: 2, limit: 2)
        #expect(page2.count == 2)
        #expect(page2[0].articleID == "a2")
        #expect(page2[1].articleID == "a1")

        // Third page: offset 4, limit 2 (should get a0 only)
        let page3 = try service.allArticles(offset: 4, limit: 2)
        #expect(page3.count == 1)
        #expect(page3[0].articleID == "a0")
    }

    @Test("allUnreadArticles(offset:limit:) returns correct page of unread articles")
    @MainActor
    func allUnreadArticlesPaginated() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feed = TestFixtures.makePersistentFeed()
        try service.addFeed(feed)

        for i in 0..<4 {
            try service.upsertArticles([
                TestFixtures.makeArticle(
                    id: "a\(i)",
                    publishedDate: Date(timeIntervalSince1970: Double(i) * 1_000_000)
                ),
            ], for: feed)
        }
        try service.save()

        // Mark a3 (newest) as read
        let articles = try service.articles(for: feed)
        let newestArticle = articles.first { $0.articleID == "a3" }!
        try service.markArticleRead(newestArticle, isRead: true)

        // Page 1: offset 0, limit 2 — should skip a3 (read) and return a2, a1
        let page1 = try service.allUnreadArticles(offset: 0, limit: 2)
        #expect(page1.count == 2)
        #expect(page1[0].articleID == "a2")
        #expect(page1[1].articleID == "a1")

        // Page 2: offset 2, limit 2 — should return a0 only
        let page2 = try service.allUnreadArticles(offset: 2, limit: 2)
        #expect(page2.count == 1)
        #expect(page2[0].articleID == "a0")
    }

    @Test("articles(for:offset:limit:) returns correct page for a specific feed")
    @MainActor
    func articlesForFeedPaginated() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feed = TestFixtures.makePersistentFeed()
        try service.addFeed(feed)

        for i in 0..<3 {
            try service.upsertArticles([
                TestFixtures.makeArticle(
                    id: "a\(i)",
                    publishedDate: Date(timeIntervalSince1970: Double(i) * 1_000_000)
                ),
            ], for: feed)
        }
        try service.save()

        let page1 = try service.articles(for: feed, offset: 0, limit: 2)
        #expect(page1.count == 2)
        #expect(page1[0].articleID == "a2")

        let page2 = try service.articles(for: feed, offset: 2, limit: 2)
        #expect(page2.count == 1)
        #expect(page2[0].articleID == "a0")
    }

    @Test("paginated query with offset beyond data returns empty")
    @MainActor
    func paginatedOffsetBeyondData() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feed = TestFixtures.makePersistentFeed()
        try service.addFeed(feed)

        try service.upsertArticles([
            TestFixtures.makeArticle(id: "a1"),
        ], for: feed)
        try service.save()

        let page = try service.allArticles(offset: 10, limit: 5)
        #expect(page.isEmpty)
    }

    // MARK: - Content Cache

    @Test("cacheContent stores and retrieves article content")
    @MainActor
    func cacheContentRoundtrip() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feed = TestFixtures.makePersistentFeed()
        try service.addFeed(feed)
        try service.upsertArticles([TestFixtures.makeArticle(id: "a1")], for: feed)

        let articles = try service.articles(for: feed)
        let content = TestFixtures.makeArticleContent(title: "Extracted", htmlContent: "<p>Full</p>")

        try service.cacheContent(content, for: articles[0])

        let cached = try service.cachedContent(for: articles[0])
        #expect(cached != nil)
        #expect(cached?.title == "Extracted")
        #expect(cached?.htmlContent == "<p>Full</p>")
    }

    @Test("cacheContent updates existing content")
    @MainActor
    func cacheContentUpdates() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feed = TestFixtures.makePersistentFeed()
        try service.addFeed(feed)
        try service.upsertArticles([TestFixtures.makeArticle(id: "a1")], for: feed)

        let articles = try service.articles(for: feed)

        let content1 = TestFixtures.makeArticleContent(title: "First")
        try service.cacheContent(content1, for: articles[0])

        let content2 = TestFixtures.makeArticleContent(title: "Updated")
        try service.cacheContent(content2, for: articles[0])

        let cached = try service.cachedContent(for: articles[0])
        #expect(cached?.title == "Updated")
    }

    @Test("cachedContent returns nil when no content cached")
    @MainActor
    func cachedContentNil() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feed = TestFixtures.makePersistentFeed()
        try service.addFeed(feed)
        try service.upsertArticles([TestFixtures.makeArticle(id: "a1")], for: feed)

        let articles = try service.articles(for: feed)
        #expect(try service.cachedContent(for: articles[0]) == nil)
    }

    @Test("deleting feed cascades to articles and content")
    @MainActor
    func deleteFeedCascades() throws {
        let (service, container) = try makeService()
        let feed = TestFixtures.makePersistentFeed()
        try service.addFeed(feed)
        try service.upsertArticles([TestFixtures.makeArticle(id: "a1")], for: feed)

        let articles = try service.articles(for: feed)
        try service.cacheContent(TestFixtures.makeArticleContent(), for: articles[0])

        try service.deleteFeed(feed)

        let articleDescriptor = FetchDescriptor<PersistentArticle>()
        let contentDescriptor = FetchDescriptor<PersistentArticleContent>()
        #expect(try container.mainContext.fetchCount(articleDescriptor) == 0)
        #expect(try container.mainContext.fetchCount(contentDescriptor) == 0)
    }
}
