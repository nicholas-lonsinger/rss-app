import Testing
import Foundation
@testable import RSSApp

@Suite("ThumbnailPrefetchService Tests")
struct ThumbnailPrefetchServiceTests {

    // MARK: - Basic Prefetch

    @Test("prefetchThumbnails caches thumbnails for articles needing them")
    @MainActor
    func prefetchCachesThumbnails() async {
        let persistence = MockFeedPersistenceService()
        let feed = TestFixtures.makePersistentFeed()
        let article = TestFixtures.makePersistentArticle(
            articleID: "article-1",
            thumbnailURL: URL(string: "https://example.com/thumb.jpg")
        )
        persistence.feeds = [feed]
        persistence.articlesByFeedID = [feed.id: [article]]

        let mockThumbnail = MockArticleThumbnailService()
        mockThumbnail.resolveResult = true

        let service = ThumbnailPrefetchService(thumbnailService: mockThumbnail)
        await service.prefetchThumbnails(persistence: persistence)

        #expect(article.isThumbnailCached == true)
        #expect(mockThumbnail.resolveCallCount == 1)
    }

    @Test("prefetchThumbnails skips articles already cached")
    @MainActor
    func prefetchSkipsAlreadyCached() async {
        let persistence = MockFeedPersistenceService()
        let feed = TestFixtures.makePersistentFeed()
        let article = TestFixtures.makePersistentArticle(
            articleID: "cached-article",
            thumbnailURL: URL(string: "https://example.com/thumb.jpg"),
            isThumbnailCached: true
        )
        persistence.feeds = [feed]
        persistence.articlesByFeedID = [feed.id: [article]]

        let mockThumbnail = MockArticleThumbnailService()
        let service = ThumbnailPrefetchService(thumbnailService: mockThumbnail)
        await service.prefetchThumbnails(persistence: persistence)

        #expect(mockThumbnail.resolveCallCount == 0)
    }

    @Test("prefetchThumbnails skips articles at retry cap")
    @MainActor
    func prefetchSkipsAtRetryCap() async {
        let persistence = MockFeedPersistenceService()
        let feed = TestFixtures.makePersistentFeed()
        let article = TestFixtures.makePersistentArticle(
            articleID: "maxed-article",
            thumbnailURL: URL(string: "https://example.com/broken.jpg")
        )
        article.thumbnailRetryCount = ThumbnailPrefetchConstants.maxRetryCount
        persistence.feeds = [feed]
        persistence.articlesByFeedID = [feed.id: [article]]

        let mockThumbnail = MockArticleThumbnailService()
        let service = ThumbnailPrefetchService(thumbnailService: mockThumbnail)
        await service.prefetchThumbnails(persistence: persistence)

        #expect(mockThumbnail.resolveCallCount == 0)
        #expect(article.isThumbnailCached == false)
    }

    // MARK: - Retry Count Increment

    @Test("prefetchThumbnails increments retry count on failure")
    @MainActor
    func prefetchIncrementsRetryCountOnFailure() async {
        let persistence = MockFeedPersistenceService()
        let feed = TestFixtures.makePersistentFeed()
        let article = TestFixtures.makePersistentArticle(
            articleID: "fail-article",
            thumbnailURL: URL(string: "https://example.com/broken.jpg")
        )
        persistence.feeds = [feed]
        persistence.articlesByFeedID = [feed.id: [article]]

        let mockThumbnail = MockArticleThumbnailService()
        mockThumbnail.resolveResult = false

        let service = ThumbnailPrefetchService(thumbnailService: mockThumbnail)
        await service.prefetchThumbnails(persistence: persistence)

        #expect(article.isThumbnailCached == false)
        #expect(article.thumbnailRetryCount == 1)
    }

    // MARK: - No-op Cases

    @Test("prefetchThumbnails is no-op when no articles need thumbnails")
    @MainActor
    func prefetchNoArticlesNeeded() async {
        let persistence = MockFeedPersistenceService()
        let feed = TestFixtures.makePersistentFeed()
        let article = TestFixtures.makePersistentArticle(
            articleID: "done-article",
            isThumbnailCached: true
        )
        persistence.feeds = [feed]
        persistence.articlesByFeedID = [feed.id: [article]]

        let mockThumbnail = MockArticleThumbnailService()
        let service = ThumbnailPrefetchService(thumbnailService: mockThumbnail)
        await service.prefetchThumbnails(persistence: persistence)

        #expect(mockThumbnail.resolveCallCount == 0)
    }

    @Test("prefetchThumbnails handles persistence query error gracefully")
    @MainActor
    func prefetchHandlesPersistenceQueryError() async {
        let persistence = MockFeedPersistenceService()
        persistence.errorToThrow = NSError(domain: "test", code: 1)

        let mockThumbnail = MockArticleThumbnailService()
        let service = ThumbnailPrefetchService(thumbnailService: mockThumbnail)
        await service.prefetchThumbnails(persistence: persistence)

        #expect(mockThumbnail.resolveCallCount == 0)
    }

    // MARK: - Multiple Articles

    @Test("prefetchThumbnails processes multiple articles across feeds")
    @MainActor
    func prefetchProcessesMultipleArticles() async {
        let persistence = MockFeedPersistenceService()
        let feed1 = TestFixtures.makePersistentFeed(title: "Feed 1")
        let feed2 = TestFixtures.makePersistentFeed(title: "Feed 2")
        let article1 = TestFixtures.makePersistentArticle(
            articleID: "a1",
            thumbnailURL: URL(string: "https://example.com/t1.jpg")
        )
        let article2 = TestFixtures.makePersistentArticle(
            articleID: "a2",
            thumbnailURL: URL(string: "https://example.com/t2.jpg")
        )
        let article3 = TestFixtures.makePersistentArticle(
            articleID: "a3",
            thumbnailURL: URL(string: "https://example.com/t3.jpg"),
            isThumbnailCached: true
        )
        persistence.feeds = [feed1, feed2]
        persistence.articlesByFeedID = [
            feed1.id: [article1, article3],
            feed2.id: [article2],
        ]

        let mockThumbnail = MockArticleThumbnailService()
        mockThumbnail.resolveResult = true

        let service = ThumbnailPrefetchService(thumbnailService: mockThumbnail)
        await service.prefetchThumbnails(persistence: persistence)

        #expect(article1.isThumbnailCached == true)
        #expect(article2.isThumbnailCached == true)
        #expect(article3.isThumbnailCached == true) // was already true
        // Only 2 articles needed downloads (article3 was already cached)
        #expect(mockThumbnail.resolveCallCount == 2)
    }

    // MARK: - Articles Without Image Sources

    @Test("prefetchThumbnails skips articles with no thumbnail URL and no link")
    @MainActor
    func prefetchSkipsArticlesWithNoImageSource() async {
        let persistence = MockFeedPersistenceService()
        let feed = TestFixtures.makePersistentFeed()
        let article = TestFixtures.makePersistentArticle(
            articleID: "no-source",
            link: nil,
            thumbnailURL: nil
        )
        persistence.feeds = [feed]
        persistence.articlesByFeedID = [feed.id: [article]]

        let mockThumbnail = MockArticleThumbnailService()
        mockThumbnail.resolveResult = false

        let service = ThumbnailPrefetchService(thumbnailService: mockThumbnail)
        await service.prefetchThumbnails(persistence: persistence)

        // Article has no image source — skipped without calling resolve or incrementing retry count
        #expect(article.isThumbnailCached == false)
        #expect(article.thumbnailRetryCount == 0)
        #expect(mockThumbnail.resolveCallCount == 0)
    }

    // MARK: - Mixed Success and Failure

    @Test("prefetchThumbnails handles mixed success and failure across articles")
    @MainActor
    func prefetchMixedResults() async {
        let persistence = MockFeedPersistenceService()
        let feed = TestFixtures.makePersistentFeed()
        let successArticle = TestFixtures.makePersistentArticle(
            articleID: "success-article",
            thumbnailURL: URL(string: "https://example.com/good.jpg")
        )
        let failArticle = TestFixtures.makePersistentArticle(
            articleID: "fail-article",
            thumbnailURL: URL(string: "https://example.com/bad.jpg")
        )
        persistence.feeds = [feed]
        persistence.articlesByFeedID = [feed.id: [successArticle, failArticle]]

        // Mock that alternates: first call succeeds, second fails
        let selectiveMock = SelectiveThumbnailMock(
            successArticleIDs: Set(["success-article"])
        )

        let service = ThumbnailPrefetchService(thumbnailService: selectiveMock)
        await service.prefetchThumbnails(persistence: persistence)

        #expect(successArticle.isThumbnailCached == true)
        #expect(failArticle.isThumbnailCached == false)
        #expect(failArticle.thumbnailRetryCount == 1)
    }
}

// MARK: - Selective Mock

/// A mock that succeeds for specific article IDs and fails for all others.
private final class SelectiveThumbnailMock: ArticleThumbnailCaching, @unchecked Sendable {

    let successArticleIDs: Set<String>

    init(successArticleIDs: Set<String>) {
        self.successArticleIDs = successArticleIDs
    }

    func cacheThumbnail(from remoteURL: URL, articleID: String) async -> Bool {
        successArticleIDs.contains(articleID)
    }

    func resolveAndCacheThumbnail(thumbnailURL: URL?, articleLink: URL?, articleID: String) async -> Bool {
        successArticleIDs.contains(articleID)
    }

    func cachedThumbnailFileURL(for articleID: String) -> URL? {
        nil
    }

    func deleteCachedThumbnail(for articleID: String) {}
}
