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

    @Test("upsertArticles preserves thumbnail caching fields on existing articles")
    @MainActor
    func upsertArticlesPreservesThumbnailFields() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feed = TestFixtures.makePersistentFeed()
        try service.addFeed(feed)

        // Insert an article
        let articles = [TestFixtures.makeArticle(id: "thumb1", title: "Thumbnail Article")]
        try service.upsertArticles(articles, for: feed)

        // Set thumbnail state on the persisted article
        let persisted = try service.articles(for: feed)
        #expect(persisted.count == 1)
        try service.markThumbnailCached(persisted[0])
        try service.incrementThumbnailRetryCount(persisted[0])
        try service.incrementThumbnailRetryCount(persisted[0])
        try service.save()

        // Verify pre-conditions
        #expect(persisted[0].isThumbnailCached == true)
        #expect(persisted[0].thumbnailRetryCount == 2)

        // Upsert same article ID again with different title
        let updatedArticles = [TestFixtures.makeArticle(id: "thumb1", title: "Updated Title")]
        try service.upsertArticles(updatedArticles, for: feed)

        // Verify thumbnail fields are preserved (article was skipped, not overwritten)
        let afterUpsert = try service.articles(for: feed)
        #expect(afterUpsert.count == 1)
        #expect(afterUpsert[0].isThumbnailCached == true)
        #expect(afterUpsert[0].thumbnailRetryCount == 2)
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

    // MARK: - Thumbnail Tracking

    @Test("articlesNeedingThumbnails returns uncached articles under retry cap")
    @MainActor
    func articlesNeedingThumbnailsReturnsUncached() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feed = TestFixtures.makePersistentFeed()
        try service.addFeed(feed)
        try service.upsertArticles([
            TestFixtures.makeArticle(id: "uncached"),
            TestFixtures.makeArticle(id: "cached"),
        ], for: feed)

        let articles = try service.articles(for: feed)
        let cachedArticle = articles.first { $0.articleID == "cached" }!
        try service.markThumbnailCached(cachedArticle)
        try service.save()

        let needing = try service.articlesNeedingThumbnails(maxRetryCount: 3)
        #expect(needing.count == 1)
        #expect(needing[0].articleID == "uncached")
    }

    @Test("articlesNeedingThumbnails excludes articles at retry cap")
    @MainActor
    func articlesNeedingThumbnailsExcludesAtCap() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feed = TestFixtures.makePersistentFeed()
        try service.addFeed(feed)
        try service.upsertArticles([TestFixtures.makeArticle(id: "maxed")], for: feed)

        let articles = try service.articles(for: feed)
        let article = articles[0]
        for _ in 0..<3 {
            try service.incrementThumbnailRetryCount(article)
        }
        try service.save()

        let needing = try service.articlesNeedingThumbnails(maxRetryCount: 3)
        #expect(needing.isEmpty)
    }

    @Test("markThumbnailCached sets isThumbnailCached to true")
    @MainActor
    func markThumbnailCachedSetsFlag() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feed = TestFixtures.makePersistentFeed()
        try service.addFeed(feed)
        try service.upsertArticles([TestFixtures.makeArticle(id: "a1")], for: feed)

        let articles = try service.articles(for: feed)
        #expect(articles[0].isThumbnailCached == false)

        try service.markThumbnailCached(articles[0])
        try service.save()

        #expect(articles[0].isThumbnailCached == true)
    }

    @Test("incrementThumbnailRetryCount increases count by one")
    @MainActor
    func incrementThumbnailRetryCountIncreases() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feed = TestFixtures.makePersistentFeed()
        try service.addFeed(feed)
        try service.upsertArticles([TestFixtures.makeArticle(id: "a1")], for: feed)

        let articles = try service.articles(for: feed)
        #expect(articles[0].thumbnailRetryCount == 0)

        try service.incrementThumbnailRetryCount(articles[0])
        try service.save()

        #expect(articles[0].thumbnailRetryCount == 1)

        try service.incrementThumbnailRetryCount(articles[0])
        try service.save()

        #expect(articles[0].thumbnailRetryCount == 2)
    }

    // MARK: - Sort Order

    @Test("articles(for:offset:limit:ascending:true) returns oldest first")
    @MainActor
    func articlesForFeedAscending() throws {
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

        let ascending = try service.articles(for: feed, offset: 0, limit: 10, ascending: true)
        #expect(ascending[0].articleID == "a0")
        #expect(ascending[2].articleID == "a2")

        let descending = try service.articles(for: feed, offset: 0, limit: 10, ascending: false)
        #expect(descending[0].articleID == "a2")
        #expect(descending[2].articleID == "a0")
    }

    @Test("allArticles(offset:limit:ascending:true) returns oldest first")
    @MainActor
    func allArticlesAscending() throws {
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

        let ascending = try service.allArticles(offset: 0, limit: 10, ascending: true)
        #expect(ascending[0].articleID == "a0")
        #expect(ascending[2].articleID == "a2")
    }

    @Test("allUnreadArticles(offset:limit:ascending:true) returns oldest first")
    @MainActor
    func allUnreadArticlesAscending() throws {
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

        let ascending = try service.allUnreadArticles(offset: 0, limit: 10, ascending: true)
        #expect(ascending[0].articleID == "a0")
        #expect(ascending[2].articleID == "a2")
    }

    // MARK: - Unread Articles For Feed

    @Test("unreadArticles(for:offset:limit:ascending:) returns only unread articles for feed")
    @MainActor
    func unreadArticlesForFeed() throws {
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

        // Mark one as read
        let allArticles = try service.articles(for: feed)
        let middle = allArticles.first { $0.articleID == "a1" }!
        try service.markArticleRead(middle, isRead: true)

        let unread = try service.unreadArticles(for: feed, offset: 0, limit: 10, ascending: true)
        #expect(unread.count == 2)
        #expect(unread[0].articleID == "a0")
        #expect(unread[1].articleID == "a2")
    }

    // MARK: - Mark All Articles Read

    @Test("markAllArticlesRead(for:) marks all articles in feed as read")
    @MainActor
    func markAllArticlesReadForFeed() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feed1 = TestFixtures.makePersistentFeed(title: "Feed 1")
        let feed2 = TestFixtures.makePersistentFeed(title: "Feed 2")
        try service.addFeed(feed1)
        try service.addFeed(feed2)

        try service.upsertArticles([
            TestFixtures.makeArticle(id: "f1-a1"),
            TestFixtures.makeArticle(id: "f1-a2"),
        ], for: feed1)
        try service.upsertArticles([
            TestFixtures.makeArticle(id: "f2-a1"),
        ], for: feed2)
        try service.save()

        try service.markAllArticlesRead(for: feed1)

        let feed1Articles = try service.articles(for: feed1)
        let feed1AllRead = feed1Articles.allSatisfy(\.isRead)
        let feed1AllHaveReadDate = feed1Articles.allSatisfy { $0.readDate != nil }
        #expect(feed1AllRead)
        #expect(feed1AllHaveReadDate)

        // Feed 2 articles should be unaffected
        let feed2Articles = try service.articles(for: feed2)
        let feed2AllUnread = feed2Articles.allSatisfy { !$0.isRead }
        #expect(feed2AllUnread)
    }

    @Test("markAllArticlesRead() marks all articles across all feeds as read")
    @MainActor
    func markAllArticlesReadGlobal() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feed1 = TestFixtures.makePersistentFeed(title: "Feed 1")
        let feed2 = TestFixtures.makePersistentFeed(title: "Feed 2")
        try service.addFeed(feed1)
        try service.addFeed(feed2)

        try service.upsertArticles([
            TestFixtures.makeArticle(id: "f1-a1"),
        ], for: feed1)
        try service.upsertArticles([
            TestFixtures.makeArticle(id: "f2-a1"),
        ], for: feed2)
        try service.save()

        try service.markAllArticlesRead()

        let all = try service.allArticles()
        let allRead = all.allSatisfy(\.isRead)
        let allHaveReadDate = all.allSatisfy { $0.readDate != nil }
        #expect(allRead)
        #expect(allHaveReadDate)
        #expect(try service.totalUnreadCount() == 0)
    }

    @Test("markAllArticlesRead(for:) is no-op when all articles already read")
    @MainActor
    func markAllArticlesReadForFeedNoOp() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feed = TestFixtures.makePersistentFeed()
        try service.addFeed(feed)

        try service.upsertArticles([TestFixtures.makeArticle(id: "a1")], for: feed)
        try service.save()

        let articles = try service.articles(for: feed)
        try service.markArticleRead(articles[0], isRead: true)

        // Should not throw
        try service.markAllArticlesRead(for: feed)
        #expect(try service.unreadCount(for: feed) == 0)
    }

    // MARK: - Article Cleanup

    @Test("totalArticleCount returns zero initially")
    @MainActor
    func totalArticleCountEmpty() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        #expect(try service.totalArticleCount() == 0)
    }

    @Test("totalArticleCount returns correct count across feeds")
    @MainActor
    func totalArticleCountAcrossFeeds() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feed1 = TestFixtures.makePersistentFeed(title: "Feed 1")
        let feed2 = TestFixtures.makePersistentFeed(title: "Feed 2")
        try service.addFeed(feed1)
        try service.addFeed(feed2)

        try service.upsertArticles([
            TestFixtures.makeArticle(id: "f1-a1"),
            TestFixtures.makeArticle(id: "f1-a2"),
        ], for: feed1)
        try service.upsertArticles([
            TestFixtures.makeArticle(id: "f2-a1"),
        ], for: feed2)
        try service.save()

        #expect(try service.totalArticleCount() == 3)
    }

    @Test("oldestArticleIDsExceedingLimit returns empty when within limit")
    @MainActor
    func oldestArticleIDsWithinLimit() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feed = TestFixtures.makePersistentFeed()
        try service.addFeed(feed)

        try service.upsertArticles([
            TestFixtures.makeArticle(id: "a1", publishedDate: Date(timeIntervalSince1970: 1000)),
            TestFixtures.makeArticle(id: "a2", publishedDate: Date(timeIntervalSince1970: 2000)),
        ], for: feed)
        try service.save()

        let result = try service.oldestArticleIDsExceedingLimit(10)
        #expect(result.isEmpty)
    }

    @Test("oldestArticleIDsExceedingLimit returns oldest articles exceeding limit")
    @MainActor
    func oldestArticleIDsExceedingLimit() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feed = TestFixtures.makePersistentFeed()
        try service.addFeed(feed)

        try service.upsertArticles([
            TestFixtures.makeArticle(id: "oldest", publishedDate: Date(timeIntervalSince1970: 1000)),
            TestFixtures.makeArticle(id: "middle", publishedDate: Date(timeIntervalSince1970: 2000)),
            TestFixtures.makeArticle(id: "newest", publishedDate: Date(timeIntervalSince1970: 3000)),
        ], for: feed)
        try service.save()

        let result = try service.oldestArticleIDsExceedingLimit(1)
        #expect(result.count == 2)
        let ids = Set(result.map(\.articleID))
        #expect(ids.contains("oldest"))
        #expect(ids.contains("middle"))
    }

    @Test("oldestArticleIDsExceedingLimit includes isThumbnailCached flag")
    @MainActor
    func oldestArticleIDsIncludesThumbnailFlag() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feed = TestFixtures.makePersistentFeed()
        try service.addFeed(feed)

        try service.upsertArticles([
            TestFixtures.makeArticle(id: "cached-old", publishedDate: Date(timeIntervalSince1970: 1000)),
            TestFixtures.makeArticle(id: "uncached-old", publishedDate: Date(timeIntervalSince1970: 2000)),
            TestFixtures.makeArticle(id: "newest", publishedDate: Date(timeIntervalSince1970: 3000)),
        ], for: feed)

        let articles = try service.articles(for: feed)
        let cachedArticle = articles.first { $0.articleID == "cached-old" }!
        try service.markThumbnailCached(cachedArticle)
        try service.save()

        let result = try service.oldestArticleIDsExceedingLimit(1)
        let cachedResult = result.first { $0.articleID == "cached-old" }
        let uncachedResult = result.first { $0.articleID == "uncached-old" }
        #expect(cachedResult?.isThumbnailCached == true)
        #expect(uncachedResult?.isThumbnailCached == false)
    }

    @Test("deleteArticles removes specified articles")
    @MainActor
    func deleteArticlesByID() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feed = TestFixtures.makePersistentFeed()
        try service.addFeed(feed)

        try service.upsertArticles([
            TestFixtures.makeArticle(id: "keep"),
            TestFixtures.makeArticle(id: "delete-1"),
            TestFixtures.makeArticle(id: "delete-2"),
        ], for: feed)
        try service.save()

        try service.deleteArticles(withIDs: ["delete-1", "delete-2"])

        let remaining = try service.articles(for: feed)
        #expect(remaining.count == 1)
        #expect(remaining[0].articleID == "keep")
    }

    @Test("deleteArticles cascade-deletes associated content")
    @MainActor
    func deleteArticlesCascadesContent() throws {
        let (service, container) = try makeService()
        let feed = TestFixtures.makePersistentFeed()
        try service.addFeed(feed)

        try service.upsertArticles([
            TestFixtures.makeArticle(id: "with-content"),
        ], for: feed)
        let articles = try service.articles(for: feed)
        try service.cacheContent(TestFixtures.makeArticleContent(), for: articles[0])

        try service.deleteArticles(withIDs: ["with-content"])

        let contentDescriptor = FetchDescriptor<PersistentArticleContent>()
        #expect(try container.mainContext.fetchCount(contentDescriptor) == 0)
    }

    @Test("deleteArticles with empty set is no-op")
    @MainActor
    func deleteArticlesEmptySet() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feed = TestFixtures.makePersistentFeed()
        try service.addFeed(feed)

        try service.upsertArticles([
            TestFixtures.makeArticle(id: "a1"),
        ], for: feed)
        try service.save()

        try service.deleteArticles(withIDs: [])

        #expect(try service.totalArticleCount() == 1)
    }

    @Test("deleteArticles handles count exceeding batch size")
    @MainActor
    func deleteArticlesBatched() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feed = TestFixtures.makePersistentFeed()
        try service.addFeed(feed)

        // Create 600 articles to delete + 5 to keep (exceeds the 500 batch size)
        let deleteCount = 600
        let keepCount = 5
        var articles: [Article] = []
        for i in 0..<deleteCount {
            articles.append(TestFixtures.makeArticle(id: "delete-\(i)"))
        }
        for i in 0..<keepCount {
            articles.append(TestFixtures.makeArticle(id: "keep-\(i)"))
        }
        try service.upsertArticles(articles, for: feed)
        try service.save()

        let deleteIDs = Set((0..<deleteCount).map { "delete-\($0)" })
        try service.deleteArticles(withIDs: deleteIDs)

        let remaining = try service.articles(for: feed)
        #expect(remaining.count == keepCount)
        for i in 0..<keepCount {
            #expect(remaining.contains { $0.articleID == "keep-\(i)" })
        }
    }

    // MARK: - Saved Article Operations

    @Test("toggleArticleSaved saves an unsaved article")
    @MainActor
    func toggleArticleSavedSaves() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feed = TestFixtures.makePersistentFeed()
        try service.addFeed(feed)
        try service.upsertArticles([TestFixtures.makeArticle(id: "a1")], for: feed)
        try service.save()

        let articles = try service.articles(for: feed)
        let article = articles[0]
        #expect(!article.isSaved)
        #expect(article.savedDate == nil)

        try service.toggleArticleSaved(article)

        #expect(article.isSaved)
        #expect(article.savedDate != nil)
    }

    @Test("toggleArticleSaved unsaves a saved article")
    @MainActor
    func toggleArticleSavedUnsaves() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feed = TestFixtures.makePersistentFeed()
        try service.addFeed(feed)
        try service.upsertArticles([TestFixtures.makeArticle(id: "a1")], for: feed)
        try service.save()

        let articles = try service.articles(for: feed)
        let article = articles[0]
        try service.toggleArticleSaved(article)
        #expect(article.isSaved)

        try service.toggleArticleSaved(article)
        #expect(!article.isSaved)
        #expect(article.savedDate == nil)
    }

    @Test("allSavedArticles returns only saved articles sorted by savedDate descending")
    @MainActor
    func allSavedArticlesSortedBySavedDate() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feed = TestFixtures.makePersistentFeed()
        try service.addFeed(feed)
        try service.upsertArticles([
            TestFixtures.makeArticle(id: "a1"),
            TestFixtures.makeArticle(id: "a2"),
            TestFixtures.makeArticle(id: "a3"),
        ], for: feed)
        try service.save()

        let articles = try service.articles(for: feed)
        // Save a1 first, then a3 — a3 should appear first in results (most recently saved)
        let a1 = articles.first { $0.articleID == "a1" }!
        let a3 = articles.first { $0.articleID == "a3" }!
        try service.toggleArticleSaved(a1)
        try service.toggleArticleSaved(a3)

        let saved = try service.allSavedArticles(offset: 0, limit: 10)
        #expect(saved.count == 2)
        #expect(saved[0].articleID == "a3")
        #expect(saved[1].articleID == "a1")
    }

    @Test("allSavedArticles respects offset and limit")
    @MainActor
    func allSavedArticlesPagination() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feed = TestFixtures.makePersistentFeed()
        try service.addFeed(feed)
        try service.upsertArticles([
            TestFixtures.makeArticle(id: "a1"),
            TestFixtures.makeArticle(id: "a2"),
        ], for: feed)
        try service.save()

        let articles = try service.articles(for: feed)
        for article in articles {
            try service.toggleArticleSaved(article)
        }

        let page = try service.allSavedArticles(offset: 1, limit: 1)
        #expect(page.count == 1)
    }

    @Test("savedCount returns count of saved articles")
    @MainActor
    func savedCountReturnsCorrectCount() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feed = TestFixtures.makePersistentFeed()
        try service.addFeed(feed)
        try service.upsertArticles([
            TestFixtures.makeArticle(id: "a1"),
            TestFixtures.makeArticle(id: "a2"),
            TestFixtures.makeArticle(id: "a3"),
        ], for: feed)
        try service.save()

        #expect(try service.savedCount() == 0)

        let articles = try service.articles(for: feed)
        try service.toggleArticleSaved(articles[0])
        try service.toggleArticleSaved(articles[1])

        #expect(try service.savedCount() == 2)
    }

    @Test("savedCount decreases after unsaving an article")
    @MainActor
    func savedCountDecrementsAfterUnsave() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feed = TestFixtures.makePersistentFeed()
        try service.addFeed(feed)
        try service.upsertArticles([
            TestFixtures.makeArticle(id: "a1"),
            TestFixtures.makeArticle(id: "a2"),
        ], for: feed)
        try service.save()

        let articles = try service.articles(for: feed)
        try service.toggleArticleSaved(articles[0])
        try service.toggleArticleSaved(articles[1])
        #expect(try service.savedCount() == 2)

        // Unsave one article
        try service.toggleArticleSaved(articles[0])
        #expect(try service.savedCount() == 1)
    }

    @Test("allSavedArticles returns empty after unsaving all articles")
    @MainActor
    func allSavedArticlesEmptyAfterUnsave() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feed = TestFixtures.makePersistentFeed()
        try service.addFeed(feed)
        try service.upsertArticles([
            TestFixtures.makeArticle(id: "a1"),
            TestFixtures.makeArticle(id: "a2"),
        ], for: feed)
        try service.save()

        let articles = try service.articles(for: feed)
        // Save both
        try service.toggleArticleSaved(articles[0])
        try service.toggleArticleSaved(articles[1])
        #expect(try service.allSavedArticles(offset: 0, limit: 10).count == 2)

        // Unsave both
        try service.toggleArticleSaved(articles[0])
        try service.toggleArticleSaved(articles[1])
        #expect(try service.allSavedArticles(offset: 0, limit: 10).isEmpty)
    }

    @Test("oldestArticleIDsExceedingLimit excludes saved articles")
    @MainActor
    func oldestArticleIDsExcludesSaved() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feed = TestFixtures.makePersistentFeed()
        try service.addFeed(feed)
        // Create 3 articles, oldest first
        try service.upsertArticles([
            TestFixtures.makeArticle(id: "old", publishedDate: Date(timeIntervalSince1970: 1_000)),
            TestFixtures.makeArticle(id: "mid", publishedDate: Date(timeIntervalSince1970: 2_000)),
            TestFixtures.makeArticle(id: "new", publishedDate: Date(timeIntervalSince1970: 3_000)),
        ], for: feed)
        try service.save()

        // Save the oldest article — it should be exempt from cleanup
        let articles = try service.articles(for: feed)
        let oldest = articles.first { $0.articleID == "old" }!
        try service.toggleArticleSaved(oldest)

        // With a limit of 2, we have 3 articles total, 1 excess
        // The oldest unsaved article ("mid") should be selected for cleanup, not "old" (saved)
        let toDelete = try service.oldestArticleIDsExceedingLimit(2)
        #expect(toDelete.count == 1)
        #expect(toDelete[0].articleID == "mid")
    }

    @Test("oldestArticleIDsExceedingLimit caps at available unsaved articles when most are saved")
    @MainActor
    func oldestArticleIDsCapsAtAvailableUnsaved() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feed = TestFixtures.makePersistentFeed()
        try service.addFeed(feed)
        // Create 4 articles
        try service.upsertArticles([
            TestFixtures.makeArticle(id: "a1", publishedDate: Date(timeIntervalSince1970: 1_000)),
            TestFixtures.makeArticle(id: "a2", publishedDate: Date(timeIntervalSince1970: 2_000)),
            TestFixtures.makeArticle(id: "a3", publishedDate: Date(timeIntervalSince1970: 3_000)),
            TestFixtures.makeArticle(id: "a4", publishedDate: Date(timeIntervalSince1970: 4_000)),
        ], for: feed)
        try service.save()

        // Save 3 of the 4 articles — only 1 unsaved remains
        let articles = try service.articles(for: feed)
        for article in articles where article.articleID != "a2" {
            try service.toggleArticleSaved(article)
        }

        // Limit of 2 means 2 excess (4 total - 2 limit), but only 1 unsaved article exists
        // Should return only the 1 available unsaved article, not crash or return saved ones
        let toDelete = try service.oldestArticleIDsExceedingLimit(2)
        #expect(toDelete.count == 1)
        #expect(toDelete[0].articleID == "a2")
    }

    // MARK: - sortDate Behavior

    // The two tests below pin the cross-feed sort and retention behavior against
    // future-dated articles, the bug that motivated `sortDate`. Real-world feeds
    // (e.g., the Cloudflare blog) publish scheduled posts whose `pubDate` lies
    // hours in the future relative to the feed's `lastBuildDate`. Sorting by raw
    // `publishedDate` would pin those articles to the top of newest-first lists
    // and shield genuinely-old articles from retention. `sortDate` clamps any
    // future date to ingestion time at insert.

    @Test("allArticles uses clamped sortDate for future-dated articles, preserving original publishedDate")
    @MainActor
    func allArticlesClampsFutureDatedArticleSortDate() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feed = TestFixtures.makePersistentFeed()
        try service.addFeed(feed)

        // Reproduces the Cloudflare bug: a feed contains an article whose pubDate
        // is 4 hours in the future (a scheduled post). The bug was that this
        // article would sort by its 4-hour-future raw pubDate, pinning it to the
        // top of newest-first lists by an enormous margin. With sortDate, the
        // article is clamped to ingestion time and sorts as a freshly-ingested
        // article (its sortDate ≈ now), while the original publishedDate is
        // preserved verbatim for the planned content-update detection feature.
        let before = Date()
        try service.upsertArticles([
            TestFixtures.makeArticle(id: "cloudflare", publishedDate: Date().addingTimeInterval(4 * 60 * 60)),
            TestFixtures.makeArticle(id: "verge", publishedDate: Date().addingTimeInterval(-30)),
        ], for: feed)
        let after = Date()
        try service.save()

        let result = try service.allArticles()
        #expect(result.count == 2)

        let cloudflare = try #require(result.first { $0.articleID == "cloudflare" })
        let verge = try #require(result.first { $0.articleID == "verge" })

        // Load-bearing: publishedDate is preserved exactly as the publisher provided
        // it. A planned content-update detection feature compares pubDate values
        // across refreshes, so any mutation here would destroy that signal.
        #expect(cloudflare.publishedDate != nil)
        #expect(cloudflare.publishedDate! > Date()) // still 4 hours in the future, untouched

        // sortDate is clamped to ingestion time (somewhere between `before` and
        // `after`). It must NOT equal the raw 4-hour-future publishedDate.
        #expect(cloudflare.sortDate >= before)
        #expect(cloudflare.sortDate <= after)
        #expect(cloudflare.sortDate < cloudflare.publishedDate!)

        // verge's past pubDate passes through unchanged (min(past, now) == past).
        #expect(verge.sortDate == verge.publishedDate)
    }

    @Test("oldestArticleIDsExceedingLimit uses sortDate so future-dated articles are not deleted prematurely")
    @MainActor
    func oldestArticleIDsExceedingLimitUsesSortDate() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feed = TestFixtures.makePersistentFeed()
        try service.addFeed(feed)

        // Three articles by ingestion-clamped sortDate ordering:
        //   - "genuinely-old": publishedDate = 1970-epoch+1000 → sortDate = past
        //   - "recent-real":   publishedDate = -60s → sortDate = -60s
        //   - "future-claimed": publishedDate = +10h → sortDate ≈ now (clamped)
        // With limit=1 (excess=2), the two oldest by sortDate should be returned:
        // "genuinely-old" and "recent-real". "future-claimed" must NOT be returned
        // because its sortDate ≈ now is the freshest, even though its publishedDate
        // would otherwise sort it as the newest if we used the raw value.
        try service.upsertArticles([
            TestFixtures.makeArticle(id: "genuinely-old", publishedDate: Date(timeIntervalSince1970: 1000)),
            TestFixtures.makeArticle(id: "future-claimed", publishedDate: Date().addingTimeInterval(10 * 60 * 60)),
            TestFixtures.makeArticle(id: "recent-real", publishedDate: Date().addingTimeInterval(-60)),
        ], for: feed)
        try service.save()

        let result = try service.oldestArticleIDsExceedingLimit(1)
        #expect(result.count == 2)
        let ids = Set(result.map(\.articleID))
        #expect(ids.contains("genuinely-old"))
        #expect(ids.contains("recent-real"))
        #expect(!ids.contains("future-claimed"))
    }
}
