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
        mockThumbnail.resolveResult = .cached

        let service = ThumbnailPrefetchService(persistence: persistence, thumbnailService: mockThumbnail)
        await service.prefetchThumbnails()

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
        let service = ThumbnailPrefetchService(persistence: persistence, thumbnailService: mockThumbnail)
        await service.prefetchThumbnails()

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
        let service = ThumbnailPrefetchService(persistence: persistence, thumbnailService: mockThumbnail)
        await service.prefetchThumbnails()

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
        mockThumbnail.resolveResult = .transientFailure

        let service = ThumbnailPrefetchService(persistence: persistence, thumbnailService: mockThumbnail)
        await service.prefetchThumbnails()

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
        let service = ThumbnailPrefetchService(persistence: persistence, thumbnailService: mockThumbnail)
        await service.prefetchThumbnails()

        #expect(mockThumbnail.resolveCallCount == 0)
    }

    @Test("prefetchThumbnails handles persistence query error gracefully")
    @MainActor
    func prefetchHandlesPersistenceQueryError() async {
        let persistence = MockFeedPersistenceService()
        persistence.errorToThrow = NSError(domain: "test", code: 1)

        let mockThumbnail = MockArticleThumbnailService()
        let service = ThumbnailPrefetchService(persistence: persistence, thumbnailService: mockThumbnail)
        await service.prefetchThumbnails()

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
        mockThumbnail.resolveResult = .cached

        let service = ThumbnailPrefetchService(persistence: persistence, thumbnailService: mockThumbnail)
        await service.prefetchThumbnails()

        #expect(article1.isThumbnailCached == true)
        #expect(article2.isThumbnailCached == true)
        #expect(article3.isThumbnailCached == true) // was already true
        // Only 2 articles needed downloads (article3 was already cached)
        #expect(mockThumbnail.resolveCallCount == 2)
    }

    // MARK: - Within-Cycle Transient Retry

    @Test("downloadWithRetry retries on transient failure then succeeds")
    @MainActor
    func retryThenSucceed() async {
        let persistence = MockFeedPersistenceService()
        let feed = TestFixtures.makePersistentFeed()
        let article = TestFixtures.makePersistentArticle(
            articleID: "retry-article",
            thumbnailURL: URL(string: "https://example.com/flaky.jpg")
        )
        persistence.feeds = [feed]
        persistence.articlesByFeedID = [feed.id: [article]]

        // Fail the first call, succeed on the second (retry)
        let mock = SequenceThumbnailMock(failCountBeforeSuccess: ["retry-article": 1])

        let service = ThumbnailPrefetchService(persistence: persistence, thumbnailService: mock)
        await service.prefetchThumbnails()

        // The article should be marked as cached (retry succeeded)
        #expect(article.isThumbnailCached == true)
        #expect(article.thumbnailRetryCount == 0)
        // resolve was called twice: first attempt failed, second succeeded
        #expect(mock.callCount(for: "retry-article") == 2)
    }

    @Test("downloadWithRetry exhausts all transient retries then fails")
    @MainActor
    func retryExhaustedThenFails() async {
        let persistence = MockFeedPersistenceService()
        let feed = TestFixtures.makePersistentFeed()
        let article = TestFixtures.makePersistentArticle(
            articleID: "always-fail",
            thumbnailURL: URL(string: "https://example.com/broken.jpg")
        )
        persistence.feeds = [feed]
        persistence.articlesByFeedID = [feed.id: [article]]

        // Fail more times than maxTransientRetries allows (never succeed)
        let totalAttempts = ThumbnailPrefetchConstants.maxTransientRetries + 1
        let mock = SequenceThumbnailMock(failCountBeforeSuccess: ["always-fail": totalAttempts])

        let service = ThumbnailPrefetchService(persistence: persistence, thumbnailService: mock)
        await service.prefetchThumbnails()

        // The article should NOT be cached and retry count incremented
        #expect(article.isThumbnailCached == false)
        #expect(article.thumbnailRetryCount == 1)
        // resolve was called maxTransientRetries + 1 times (initial + retries)
        #expect(mock.callCount(for: "always-fail") == totalAttempts)
    }

    @Test("downloadWithRetry succeeds on last allowed attempt")
    @MainActor
    func retrySucceedsOnLastAttempt() async {
        let persistence = MockFeedPersistenceService()
        let feed = TestFixtures.makePersistentFeed()
        let article = TestFixtures.makePersistentArticle(
            articleID: "last-chance",
            thumbnailURL: URL(string: "https://example.com/slow.jpg")
        )
        persistence.feeds = [feed]
        persistence.articlesByFeedID = [feed.id: [article]]

        // Fail exactly maxTransientRetries times, then succeed on the final attempt
        let mock = SequenceThumbnailMock(
            failCountBeforeSuccess: ["last-chance": ThumbnailPrefetchConstants.maxTransientRetries]
        )

        let service = ThumbnailPrefetchService(persistence: persistence, thumbnailService: mock)
        await service.prefetchThumbnails()

        // Should succeed on the last allowed attempt
        #expect(article.isThumbnailCached == true)
        #expect(article.thumbnailRetryCount == 0)
        // Called maxTransientRetries + 1 times total
        let expectedCalls = ThumbnailPrefetchConstants.maxTransientRetries + 1
        #expect(mock.callCount(for: "last-chance") == expectedCalls)
    }

    // MARK: - Permanent Failure Skips Retries

    @Test("downloadWithRetry does not retry on permanent failure")
    @MainActor
    func permanentFailureSkipsRetry() async {
        let persistence = MockFeedPersistenceService()
        let feed = TestFixtures.makePersistentFeed()
        let article = TestFixtures.makePersistentArticle(
            articleID: "perm-fail",
            thumbnailURL: URL(string: "https://example.com/gone.jpg")
        )
        persistence.feeds = [feed]
        persistence.articlesByFeedID = [feed.id: [article]]

        let mockThumbnail = MockArticleThumbnailService()
        mockThumbnail.resolveResult = .permanentFailure

        let service = ThumbnailPrefetchService(persistence: persistence, thumbnailService: mockThumbnail)
        await service.prefetchThumbnails()

        // Permanent failure should be called only once — no retries
        #expect(mockThumbnail.resolveCallCount == 1)
        #expect(article.isThumbnailCached == false)
        #expect(article.thumbnailRetryCount == 1)
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
        mockThumbnail.resolveResult = .transientFailure

        let service = ThumbnailPrefetchService(persistence: persistence, thumbnailService: mockThumbnail)
        await service.prefetchThumbnails()

        // Article has no image source — skipped without calling resolve or incrementing retry count
        #expect(article.isThumbnailCached == false)
        #expect(article.thumbnailRetryCount == 0)
        #expect(mockThumbnail.resolveCallCount == 0)
    }

    // MARK: - Cancellation Does Not Poison Retry Budget

    @Test("prefetchThumbnails treats cancellation as a non-penalizing outcome")
    @MainActor
    func prefetchCancellationDoesNotIncrementRetryCount() async {
        let persistence = MockFeedPersistenceService()
        let feed = TestFixtures.makePersistentFeed()
        let article = TestFixtures.makePersistentArticle(
            articleID: "cancelled-article",
            thumbnailURL: URL(string: "https://example.com/thumb.jpg")
        )
        persistence.feeds = [feed]
        persistence.articlesByFeedID = [feed.id: [article]]

        let mockThumbnail = MockArticleThumbnailService()
        mockThumbnail.throwCancellation = true

        let service = ThumbnailPrefetchService(persistence: persistence, thumbnailService: mockThumbnail)
        await service.prefetchThumbnails()

        // The resolve call was made (and threw CancellationError)
        #expect(mockThumbnail.resolveCallCount == 1)
        // Cancelled work must not be counted against the retry budget — try again next cycle.
        #expect(article.thumbnailRetryCount == 0)
        // And must not be marked as cached.
        #expect(article.isThumbnailCached == false)
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

        let service = ThumbnailPrefetchService(persistence: persistence, thumbnailService: selectiveMock)
        await service.prefetchThumbnails()

        #expect(successArticle.isThumbnailCached == true)
        #expect(failArticle.isThumbnailCached == false)
        #expect(failArticle.thumbnailRetryCount == 1)
    }
}

// MARK: - Selective Mock

/// A mock that succeeds for specific article IDs and returns permanent failure for all others.
private final class SelectiveThumbnailMock: ArticleThumbnailCaching, @unchecked Sendable {

    let successArticleIDs: Set<String>

    init(successArticleIDs: Set<String>) {
        self.successArticleIDs = successArticleIDs
    }

    func cacheThumbnail(from remoteURL: URL, articleID: String) async throws -> ThumbnailCacheResult {
        successArticleIDs.contains(articleID) ? .cached : .permanentFailure
    }

    func resolveAndCacheThumbnail(thumbnailURL: URL?, articleLink: URL?, articleID: String) async throws -> ThumbnailCacheResult {
        successArticleIDs.contains(articleID) ? .cached : .permanentFailure
    }

    func cachedThumbnailFileURL(for articleID: String) -> URL? {
        nil
    }

    func deleteCachedThumbnail(for articleID: String) {}
}

// MARK: - Sequence Mock

/// A mock that returns transient failure a configurable number of times per article ID before succeeding.
/// Used to test the within-cycle transient retry loop in `downloadWithRetry`.
// RATIONALE: @unchecked Sendable is safe because the mock is accessed from task group
// child tasks that run one-at-a-time per article ID, and the lock serializes counter access.
private final class SequenceThumbnailMock: ArticleThumbnailCaching, @unchecked Sendable {

    /// Number of times `resolveAndCacheThumbnail` must return `.transientFailure` before
    /// it returns `.cached` for each article. If the fail count equals or exceeds total calls,
    /// the article never succeeds.
    private let failCountBeforeSuccess: [String: Int]

    /// Per-article call counter, protected by a lock for concurrent task group access.
    private var callCounts: [String: Int] = [:]
    private let lock = NSLock()

    init(failCountBeforeSuccess: [String: Int]) {
        self.failCountBeforeSuccess = failCountBeforeSuccess
    }

    /// Returns the number of times `resolveAndCacheThumbnail` was called for the given article ID.
    func callCount(for articleID: String) -> Int {
        lock.withLock { callCounts[articleID, default: 0] }
    }

    func cacheThumbnail(from remoteURL: URL, articleID: String) async throws -> ThumbnailCacheResult {
        .transientFailure
    }

    func resolveAndCacheThumbnail(thumbnailURL: URL?, articleLink: URL?, articleID: String) async throws -> ThumbnailCacheResult {
        let currentCall: Int = lock.withLock {
            let count = callCounts[articleID, default: 0]
            callCounts[articleID] = count + 1
            return count
        }
        let failsNeeded = failCountBeforeSuccess[articleID, default: 0]
        return currentCall >= failsNeeded ? .cached : .transientFailure
    }

    func cachedThumbnailFileURL(for articleID: String) -> URL? {
        nil
    }

    func deleteCachedThumbnail(for articleID: String) {}
}
