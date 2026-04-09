import Testing
import Foundation
@testable import RSSApp

@Suite("FeedRefreshService Tests")
struct FeedRefreshServiceTests {

    // MARK: - Helpers

    /// Builds a refresh service wired to a full set of mocks. All dependencies
    /// default to benign mocks; callers override only what they care about.
    @MainActor
    private static func makeService(
        persistence: FeedPersisting,
        feedFetching: FeedFetching = MockFeedFetchingService(),
        feedIconService: FeedIconResolving = MockFeedIconService(),
        thumbnailPrefetcher: ThumbnailPrefetching? = nil,
        articleRetention: ArticleRetaining = MockArticleRetentionService(),
        thumbnailService: ArticleThumbnailCaching = MockArticleThumbnailService(),
        networkMonitor: NetworkMonitoring = MockNetworkMonitorService()
    ) -> FeedRefreshService {
        FeedRefreshService(
            persistence: persistence,
            feedFetching: feedFetching,
            feedIconService: feedIconService,
            thumbnailPrefetcher: thumbnailPrefetcher ?? MockThumbnailPrefetchService(),
            articleRetention: articleRetention,
            thumbnailService: thumbnailService,
            networkMonitor: networkMonitor
        )
    }

    // MARK: - Success paths

    @Test("refreshAllFeeds updates metadata from fetched feeds")
    @MainActor
    func refreshUpdatesMetadata() async {
        let url1 = URL(string: "https://one.com/feed")!
        let url2 = URL(string: "https://two.com/feed")!
        let feed1 = TestFixtures.makePersistentFeed(title: "Old One", feedURL: url1, feedDescription: "")
        let feed2 = TestFixtures.makePersistentFeed(title: "Old Two", feedURL: url2, feedDescription: "")

        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed1, feed2]
        let mockFetching = MockFeedFetchingService()
        mockFetching.feedsByURL = [
            url1: TestFixtures.makeFeed(title: "New One", feedDescription: "Desc One"),
            url2: TestFixtures.makeFeed(title: "New Two", feedDescription: "Desc Two"),
        ]

        let service = Self.makeService(persistence: mockPersistence, feedFetching: mockFetching)
        let outcome = await service.refreshAllFeeds()

        let refreshed = try? mockPersistence.allFeeds()
        #expect(refreshed?[0].title == "New One")
        #expect(refreshed?[0].feedDescription == "Desc One")
        #expect(refreshed?[1].title == "New Two")
        #expect(refreshed?[1].feedDescription == "Desc Two")
        #expect(outcome == .completed(.init(totalFeeds: 2, failureCount: 0, saveDidFail: false, retentionCleanupFailed: false)))
    }

    @Test("refreshAllFeeds returns .skipped when feeds is empty")
    @MainActor
    func refreshEmptyIsSkipped() async {
        let mockPersistence = MockFeedPersistenceService()
        let service = Self.makeService(persistence: mockPersistence)

        let outcome = await service.refreshAllFeeds()

        #expect(outcome == .skipped)
        #expect(service.isRefreshing == false)
    }

    @Test("isRefreshing is false after refresh completes")
    @MainActor
    func isRefreshingFalseAfterComplete() async {
        let url = URL(string: "https://example.com/feed")!
        let feed = TestFixtures.makePersistentFeed(feedURL: url)

        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]
        let mockFetching = MockFeedFetchingService()
        mockFetching.feedsByURL = [url: TestFixtures.makeFeed()]

        let service = Self.makeService(persistence: mockPersistence, feedFetching: mockFetching)
        await service.refreshAllFeeds()

        #expect(service.isRefreshing == false)
    }

    // MARK: - Failure paths

    @Test("refreshAllFeeds preserves feed when fetch fails")
    @MainActor
    func refreshPreservesOnFailure() async {
        let url = URL(string: "https://fail.com/feed")!
        let feed = TestFixtures.makePersistentFeed(title: "Original", feedURL: url, feedDescription: "Original Desc")

        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]
        let mockFetching = MockFeedFetchingService()
        mockFetching.errorsByURL = [url: FeedFetchingError.invalidResponse(statusCode: 500)]

        let service = Self.makeService(persistence: mockPersistence, feedFetching: mockFetching)
        let outcome = await service.refreshAllFeeds()

        #expect(outcome == .completed(.init(totalFeeds: 1, failureCount: 1, saveDidFail: false, retentionCleanupFailed: false)))
    }

    @Test("refreshAllFeeds handles partial failures")
    @MainActor
    func refreshPartialFailure() async {
        let url1 = URL(string: "https://ok.com/feed")!
        let url2 = URL(string: "https://fail.com/feed")!
        let feed1 = TestFixtures.makePersistentFeed(title: "Will Update", feedURL: url1, feedDescription: "")
        let feed2 = TestFixtures.makePersistentFeed(title: "Will Fail", feedURL: url2, feedDescription: "Old")

        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed1, feed2]
        let mockFetching = MockFeedFetchingService()
        mockFetching.feedsByURL = [
            url1: TestFixtures.makeFeed(title: "Updated", feedDescription: "New Desc"),
        ]
        mockFetching.errorsByURL = [url2: FeedFetchingError.invalidResponse(statusCode: 404)]

        let service = Self.makeService(persistence: mockPersistence, feedFetching: mockFetching)
        let outcome = await service.refreshAllFeeds()

        let refreshed = try? mockPersistence.allFeeds()
        #expect(refreshed?[0].title == "Updated")
        #expect(refreshed?[0].feedDescription == "New Desc")
        #expect(outcome == .completed(.init(totalFeeds: 2, failureCount: 1, saveDidFail: false, retentionCleanupFailed: false)))
    }

    @Test("refreshAllFeeds sets error state on failed feeds")
    @MainActor
    func refreshSetsErrorState() async {
        let url = URL(string: "https://fail.com/feed")!
        let feed = TestFixtures.makePersistentFeed(title: "Broken", feedURL: url)

        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]
        let mockFetching = MockFeedFetchingService()
        mockFetching.errorsByURL = [url: FeedFetchingError.invalidResponse(statusCode: 404)]

        let service = Self.makeService(persistence: mockPersistence, feedFetching: mockFetching)
        await service.refreshAllFeeds()

        let refreshed = try? mockPersistence.allFeeds()
        #expect(refreshed?[0].lastFetchError == "HTTP 404")
        #expect(refreshed?[0].lastFetchErrorDate != nil)
    }

    @Test("refreshAllFeeds clears error state on successful feeds")
    @MainActor
    func refreshClearsErrorState() async {
        let url = URL(string: "https://recovered.com/feed")!
        let feed = TestFixtures.makePersistentFeed(
            title: "Was Broken",
            feedURL: url,
            lastFetchError: "HTTP 404",
            lastFetchErrorDate: Date()
        )

        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]
        let mockFetching = MockFeedFetchingService()
        mockFetching.feedsByURL = [url: TestFixtures.makeFeed(title: "Fixed")]

        let service = Self.makeService(persistence: mockPersistence, feedFetching: mockFetching)
        await service.refreshAllFeeds()

        let refreshed = try? mockPersistence.allFeeds()
        #expect(refreshed?[0].lastFetchError == nil)
        #expect(refreshed?[0].lastFetchErrorDate == nil)
        #expect(refreshed?[0].title == "Fixed")
    }

    // MARK: - 304 Not Modified

    @Test("refreshAllFeeds handles 304 Not Modified")
    @MainActor
    func refreshHandles304() async {
        let url = URL(string: "https://example.com/feed")!
        let feed = TestFixtures.makePersistentFeed(title: "Unchanged", feedURL: url)

        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]
        let mockFetching = MockFeedFetchingService()
        mockFetching.shouldReturn304 = true

        let service = Self.makeService(persistence: mockPersistence, feedFetching: mockFetching)
        let outcome = await service.refreshAllFeeds()

        #expect(outcome == .completed(.init(totalFeeds: 1, failureCount: 0, saveDidFail: false, retentionCleanupFailed: false)))
    }

    // MARK: - Metadata / upsert / cache-header ordering

    @Test("refreshAllFeeds continues upsert when metadata update fails")
    @MainActor
    func continuesUpsertWhenMetadataFails() async {
        let url = URL(string: "https://example.com/feed")!
        let feed = TestFixtures.makePersistentFeed(feedURL: url)

        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]
        mockPersistence.updateFeedMetadataError = NSError(domain: "test", code: 1)
        let mockFetching = MockFeedFetchingService()
        // Feed must carry at least one article so the upsert side effect
        // (populating articlesByFeedID) is observable. Without articles, a
        // skipped upsert and a successful-but-empty upsert would be
        // indistinguishable from outside.
        mockFetching.feedsByURL = [
            url: TestFixtures.makeFeed(
                title: "New Title",
                articles: [TestFixtures.makeArticle(id: "a1")]
            )
        ]

        let service = Self.makeService(persistence: mockPersistence, feedFetching: mockFetching)
        let outcome = await service.refreshAllFeeds()

        // Metadata failure is cosmetic (not counted in failureCount). Upsert
        // should still have run: the side effect is that articlesByFeedID has
        // the fetched article persisted to the mock store.
        #expect(mockPersistence.articlesByFeedID[feed.id]?.count == 1)
        #expect(outcome == .completed(.init(totalFeeds: 1, failureCount: 0, saveDidFail: false, retentionCleanupFailed: false)))
    }

    @Test("refreshAllFeeds skips cache header update when upsert fails")
    @MainActor
    func skipsCacheHeadersWhenUpsertFails() async {
        let url = URL(string: "https://example.com/feed")!
        // Feed has no pre-existing etag/lastModified — if cache headers are
        // updated by the refresh, the fetched values would overwrite nil.
        let feed = TestFixtures.makePersistentFeed(feedURL: url)

        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]
        mockPersistence.upsertArticlesError = NSError(domain: "test", code: 1)
        let mockFetching = MockFeedFetchingService()
        mockFetching.feedsByURL = [url: TestFixtures.makeFeed()]
        // Mock fetcher wraps the feed with these cache headers; if the refresh
        // did not skip the updateFeedCacheHeaders call, feed.etag would end up
        // non-nil after the refresh.
        mockFetching.etagToReturn = "etag-123"
        mockFetching.lastModifiedToReturn = "Mon, 01 Jan 2025 00:00:00 GMT"

        let service = Self.makeService(persistence: mockPersistence, feedFetching: mockFetching)
        let outcome = await service.refreshAllFeeds()

        // Upsert failure is counted. Cache headers must NOT have been written
        // because a subsequent 304 would otherwise silently drop the articles.
        let refreshed = try? mockPersistence.allFeeds()
        #expect(refreshed?[0].etag == nil)
        #expect(refreshed?[0].lastModifiedHeader == nil)
        #expect(outcome == .completed(.init(totalFeeds: 1, failureCount: 1, saveDidFail: false, retentionCleanupFailed: false)))
    }

    // MARK: - Save / retention

    @Test("refreshAllFeeds reports save failure via outcome")
    @MainActor
    func reportsSaveFailure() async {
        let url = URL(string: "https://example.com/feed")!
        let feed = TestFixtures.makePersistentFeed(feedURL: url)

        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]
        mockPersistence.saveError = NSError(domain: "test", code: 1)
        let mockFetching = MockFeedFetchingService()
        mockFetching.feedsByURL = [url: TestFixtures.makeFeed()]

        let service = Self.makeService(persistence: mockPersistence, feedFetching: mockFetching)
        let outcome = await service.refreshAllFeeds()

        #expect(outcome == .completed(.init(totalFeeds: 1, failureCount: 0, saveDidFail: true, retentionCleanupFailed: false)))
    }

    @Test("refreshAllFeeds invokes article retention enforcement after refresh")
    @MainActor
    func invokesRetentionEnforcement() async {
        let url = URL(string: "https://example.com/feed")!
        let feed = TestFixtures.makePersistentFeed(feedURL: url)

        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]
        let mockFetching = MockFeedFetchingService()
        mockFetching.feedsByURL = [url: TestFixtures.makeFeed()]
        let mockRetention = MockArticleRetentionService()

        let service = Self.makeService(
            persistence: mockPersistence,
            feedFetching: mockFetching,
            articleRetention: mockRetention
        )
        await service.refreshAllFeeds()

        #expect(mockRetention.enforceCallCount == 1)
    }

    @Test("refreshAllFeeds reports retention failure via outcome")
    @MainActor
    func reportsRetentionFailure() async {
        let url = URL(string: "https://example.com/feed")!
        let feed = TestFixtures.makePersistentFeed(feedURL: url)

        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]
        let mockFetching = MockFeedFetchingService()
        mockFetching.feedsByURL = [url: TestFixtures.makeFeed()]
        let mockRetention = MockArticleRetentionService()
        mockRetention.enforceError = NSError(domain: "test", code: 1)

        let service = Self.makeService(
            persistence: mockPersistence,
            feedFetching: mockFetching,
            articleRetention: mockRetention
        )
        let outcome = await service.refreshAllFeeds()

        #expect(outcome == .completed(.init(totalFeeds: 1, failureCount: 0, saveDidFail: false, retentionCleanupFailed: true)))
    }

    // MARK: - Setup failure

    @Test("refreshAllFeeds returns .setupFailed when feeds cannot be loaded")
    @MainActor
    func refreshReturnsSetupFailedWhenLoadFails() async {
        // The persistence layer throws when listing feeds — a distinct failure
        // class from "save after refresh failed" and one that should NOT
        // surface as "Unable to save updated feeds." in the viewmodel.
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.errorToThrow = NSError(domain: "test", code: 1)

        let service = Self.makeService(persistence: mockPersistence)
        let outcome = await service.refreshAllFeeds()

        #expect(outcome == .setupFailed)
        #expect(service.isRefreshing == false)
    }

    // MARK: - Cancellation

    @Test("refreshAllFeeds returns .cancelled when the task group throws CancellationError")
    @MainActor
    func refreshReturnsCancelledOnTaskGroupCancellation() async {
        let url = URL(string: "https://example.com/feed")!
        let feed = TestFixtures.makePersistentFeed(feedURL: url)

        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]
        let mockFetching = MockFeedFetchingService()
        // Inject a CancellationError on the fetch — the enqueue closure
        // rethrows it, which cancels the task group and causes performRefresh
        // to return .cancelled rather than .completed with a false "no
        // failures" report.
        mockFetching.errorsByURL = [url: CancellationError()]

        let service = Self.makeService(persistence: mockPersistence, feedFetching: mockFetching)
        let outcome = await service.refreshAllFeeds()

        #expect(outcome == .cancelled(totalFeeds: 1))
    }

    // MARK: - Cosmetic persistence failures (not counted in failureCount)

    @Test("refreshAllFeeds does not count updateFeedCacheHeaders failure in failureCount")
    @MainActor
    func cacheHeaderFailureIsCosmetic() async {
        // Cache-header write failure is self-healing (the next refresh
        // re-fetches the content) and must NOT count as a user-visible
        // failure. This is a load-bearing invariant once the BG coordinator
        // gates success on `failureCount == 0` — counting cosmetic failures
        // here would train iOS to back off the BG schedule over transient
        // SwiftData hiccups that have no data-integrity impact.
        let url = URL(string: "https://example.com/feed")!
        let feed = TestFixtures.makePersistentFeed(feedURL: url)

        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]
        mockPersistence.updateFeedCacheHeadersError = NSError(domain: "test", code: 1)
        let mockFetching = MockFeedFetchingService()
        mockFetching.feedsByURL = [
            url: TestFixtures.makeFeed(title: "Updated Title")
        ]

        let service = Self.makeService(persistence: mockPersistence, feedFetching: mockFetching)
        let outcome = await service.refreshAllFeeds()

        // Metadata update still persisted (cosmetic failure downstream of
        // the successful upsert), upsert succeeded, failureCount unchanged.
        let refreshed = try? mockPersistence.allFeeds()
        #expect(refreshed?[0].title == "Updated Title")
        #expect(outcome == .completed(.init(totalFeeds: 1, failureCount: 0, saveDidFail: false, retentionCleanupFailed: false)))
    }

    // MARK: - Icon resolution

    @Test("refreshAllFeeds resolves icons for fetched feeds")
    @MainActor
    func resolvesIcons() async {
        let url = URL(string: "https://example.com/feed")!
        let feed = TestFixtures.makePersistentFeed(feedURL: url)

        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]
        let mockFetching = MockFeedFetchingService()
        mockFetching.feedsByURL = [url: TestFixtures.makeFeed()]
        let mockIconService = MockFeedIconService()

        let service = Self.makeService(
            persistence: mockPersistence,
            feedFetching: mockFetching,
            feedIconService: mockIconService
        )
        await service.refreshAllFeeds()

        // Allow fire-and-forget icon resolution tasks to complete
        for _ in 0..<10 { await Task.yield() }

        #expect(mockIconService.resolveAndCacheCallCount == 1)
    }

    @Test("refreshAllFeeds skips icon resolution when icon already cached")
    @MainActor
    func skipsIconResolutionWhenCached() async {
        let url = URL(string: "https://example.com/feed")!
        let feed = TestFixtures.makePersistentFeed(feedURL: url)

        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]
        let mockFetching = MockFeedFetchingService()
        mockFetching.feedsByURL = [url: TestFixtures.makeFeed()]
        let mockIconService = MockFeedIconService()
        mockIconService.cachedFileURL = URL(fileURLWithPath: "/tmp/icon.png")

        let service = Self.makeService(
            persistence: mockPersistence,
            feedFetching: mockFetching,
            feedIconService: mockIconService
        )
        await service.refreshAllFeeds()

        for _ in 0..<10 { await Task.yield() }

        #expect(mockIconService.resolveAndCacheCallCount == 0)
    }

    // MARK: - Thumbnail prefetch

    @Test("refreshAllFeeds invokes thumbnail prefetcher after refresh")
    @MainActor
    func invokesThumbnailPrefetcher() async {
        let url = URL(string: "https://example.com/feed")!
        let feed = TestFixtures.makePersistentFeed(feedURL: url)

        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]
        let mockFetching = MockFeedFetchingService()
        mockFetching.feedsByURL = [url: TestFixtures.makeFeed()]
        let mockPrefetcher = MockThumbnailPrefetchService()

        let service = Self.makeService(
            persistence: mockPersistence,
            feedFetching: mockFetching,
            thumbnailPrefetcher: mockPrefetcher
        )
        await service.refreshAllFeeds()
        await service.awaitPendingWork()

        #expect(mockPrefetcher.prefetchCallCount == 1)
    }

    // MARK: - Network gating

    @Test("refreshAllFeeds skips thumbnail prefetcher when background downloads not allowed")
    @MainActor
    func thumbnailPrefetchSkippedWhenNetworkDisallowed() async {
        let url = URL(string: "https://example.com/feed")!
        let feed = TestFixtures.makePersistentFeed(feedURL: url)

        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]
        let mockFetching = MockFeedFetchingService()
        mockFetching.feedsByURL = [url: TestFixtures.makeFeed()]
        let mockPrefetcher = MockThumbnailPrefetchService()
        let mockNetwork = MockNetworkMonitorService()
        mockNetwork.backgroundDownloadAllowed = false

        let service = Self.makeService(
            persistence: mockPersistence,
            feedFetching: mockFetching,
            thumbnailPrefetcher: mockPrefetcher,
            networkMonitor: mockNetwork
        )
        await service.refreshAllFeeds()
        await service.awaitPendingWork()

        #expect(mockPrefetcher.prefetchCallCount == 0)
    }

    @Test("refreshAllFeeds skips icon resolution when background downloads not allowed")
    @MainActor
    func iconResolutionSkippedWhenNetworkDisallowed() async {
        let url = URL(string: "https://example.com/feed")!
        let feed = TestFixtures.makePersistentFeed(feedURL: url)

        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]
        let mockFetching = MockFeedFetchingService()
        mockFetching.feedsByURL = [url: TestFixtures.makeFeed()]
        let mockIconService = MockFeedIconService()
        let mockNetwork = MockNetworkMonitorService()
        mockNetwork.backgroundDownloadAllowed = false

        let service = Self.makeService(
            persistence: mockPersistence,
            feedFetching: mockFetching,
            feedIconService: mockIconService,
            networkMonitor: mockNetwork
        )
        await service.refreshAllFeeds()

        for _ in 0..<10 { await Task.yield() }

        #expect(mockIconService.resolveAndCacheCallCount == 0)
    }

    @Test("refreshAllFeeds skips icon resolution on 304 when background downloads not allowed")
    @MainActor
    func iconResolutionSkippedOn304WhenNetworkDisallowed() async {
        let url = URL(string: "https://example.com/feed")!
        let feed = TestFixtures.makePersistentFeed(feedURL: url)

        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]
        let mockFetching = MockFeedFetchingService()
        mockFetching.shouldReturn304 = true
        let mockIconService = MockFeedIconService()
        let mockNetwork = MockNetworkMonitorService()
        mockNetwork.backgroundDownloadAllowed = false

        let service = Self.makeService(
            persistence: mockPersistence,
            feedFetching: mockFetching,
            feedIconService: mockIconService,
            networkMonitor: mockNetwork
        )
        await service.refreshAllFeeds()

        for _ in 0..<10 { await Task.yield() }

        #expect(mockIconService.resolveAndCacheCallCount == 0)
    }

    @Test("refreshAllFeeds resolves icon on 304 when background downloads allowed")
    @MainActor
    func iconResolutionRunsOn304WhenNetworkAllowed() async {
        let url = URL(string: "https://example.com/feed")!
        let feed = TestFixtures.makePersistentFeed(feedURL: url)

        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]
        let mockFetching = MockFeedFetchingService()
        mockFetching.shouldReturn304 = true
        let mockIconService = MockFeedIconService()
        let mockNetwork = MockNetworkMonitorService()
        mockNetwork.backgroundDownloadAllowed = true

        let service = Self.makeService(
            persistence: mockPersistence,
            feedFetching: mockFetching,
            feedIconService: mockIconService,
            networkMonitor: mockNetwork
        )
        await service.refreshAllFeeds()

        for _ in 0..<10 { await Task.yield() }

        #expect(mockIconService.resolveAndCacheCallCount == 1)
    }

    @Test("refreshAllFeeds still refreshes feed content when background downloads not allowed")
    @MainActor
    func refreshContinuesWhenNetworkDisallowed() async {
        let url = URL(string: "https://example.com/feed")!
        let feed = TestFixtures.makePersistentFeed(title: "Feed", feedURL: url)

        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]
        let mockFetching = MockFeedFetchingService()
        mockFetching.feedsByURL = [url: TestFixtures.makeFeed(title: "Updated")]
        let mockNetwork = MockNetworkMonitorService()
        mockNetwork.backgroundDownloadAllowed = false

        let service = Self.makeService(
            persistence: mockPersistence,
            feedFetching: mockFetching,
            networkMonitor: mockNetwork
        )
        let outcome = await service.refreshAllFeeds()

        let refreshed = try? mockPersistence.allFeeds()
        #expect(refreshed?[0].title == "Updated")
        #expect(outcome == .completed(.init(totalFeeds: 1, failureCount: 0, saveDidFail: false, retentionCleanupFailed: false)))
    }

    // MARK: - cancelBackgroundDownloadTasksIfDisallowed

    @Test("cancelBackgroundDownloadTasksIfDisallowed cancels prefetch task when downloads are disallowed")
    @MainActor
    func cancelBackgroundDownloadTasksCancelsPrefetchWhenDisallowed() async {
        let url = URL(string: "https://example.com/feed")!
        let feed = TestFixtures.makePersistentFeed(feedURL: url)

        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]
        let mockFetching = MockFeedFetchingService()
        mockFetching.feedsByURL = [url: TestFixtures.makeFeed()]

        // A slow prefetcher that we can check for cancellation
        let slowPrefetcher = SlowCancellationPrefetchService()
        let mockNetwork = MockNetworkMonitorService()
        mockNetwork.backgroundDownloadAllowed = true

        let service = Self.makeService(
            persistence: mockPersistence,
            feedFetching: mockFetching,
            thumbnailPrefetcher: slowPrefetcher,
            networkMonitor: mockNetwork
        )

        // Kick off a refresh so the thumbnailPrefetchTask gets set
        await service.refreshAllFeeds()

        // Now flip the network to disallowed and call the cancel method
        mockNetwork.backgroundDownloadAllowed = false
        service.cancelBackgroundDownloadTasksIfDisallowed()

        // Yield to let the cancellation handler's Task { @MainActor } hop execute
        for _ in 0..<20 { await Task.yield() }

        // The prefetch task should have been cancelled
        #expect(slowPrefetcher.wasCancelled)
    }

    @Test("cancelBackgroundDownloadTasksIfDisallowed does nothing when downloads are still allowed")
    @MainActor
    func cancelBackgroundDownloadTasksNoopWhenAllowed() async {
        let url = URL(string: "https://example.com/feed")!
        let feed = TestFixtures.makePersistentFeed(feedURL: url)

        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]
        let mockFetching = MockFeedFetchingService()
        mockFetching.feedsByURL = [url: TestFixtures.makeFeed()]

        let slowPrefetcher = SlowCancellationPrefetchService()
        let mockNetwork = MockNetworkMonitorService()
        mockNetwork.backgroundDownloadAllowed = true

        let service = Self.makeService(
            persistence: mockPersistence,
            feedFetching: mockFetching,
            thumbnailPrefetcher: slowPrefetcher,
            networkMonitor: mockNetwork
        )

        await service.refreshAllFeeds()

        // Downloads still allowed — cancel should be a no-op
        service.cancelBackgroundDownloadTasksIfDisallowed()

        for _ in 0..<20 { await Task.yield() }

        #expect(!slowPrefetcher.wasCancelled)
    }

    @Test("wifiOnly setting notification triggers cancel of in-flight prefetch task")
    @MainActor
    func wifiOnlySettingNotificationTriggersCancel() async {
        let url = URL(string: "https://example.com/feed")!
        let feed = TestFixtures.makePersistentFeed(feedURL: url)

        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]
        let mockFetching = MockFeedFetchingService()
        mockFetching.feedsByURL = [url: TestFixtures.makeFeed()]

        let slowPrefetcher = SlowCancellationPrefetchService()
        let mockNetwork = MockNetworkMonitorService()
        mockNetwork.backgroundDownloadAllowed = true

        let service = Self.makeService(
            persistence: mockPersistence,
            feedFetching: mockFetching,
            thumbnailPrefetcher: slowPrefetcher,
            networkMonitor: mockNetwork
        )

        // Start refresh so the prefetch task is in-flight
        await service.refreshAllFeeds()

        // Flip to disallowed so the notification-triggered cancel will fire
        mockNetwork.backgroundDownloadAllowed = false

        // Post the notification that SettingsView toggle would fire via
        // BackgroundImageDownloadSettings.wifiOnly setter
        NotificationCenter.default.post(
            name: BackgroundImageDownloadSettings.wifiOnlyDidChangeNotification,
            object: nil
        )

        // Yield to allow the Task { @MainActor } inside the notification observer
        // and the cancellation handler to execute
        for _ in 0..<20 { await Task.yield() }

        #expect(slowPrefetcher.wasCancelled)
    }
}

// MARK: - SlowCancellationPrefetchService

/// A mock prefetcher that suspends indefinitely until cancelled. Used to verify
/// that `cancelBackgroundDownloadTasksIfDisallowed` actually cancels the task
/// rather than just clearing the reference.
///
/// `wasCancelled` is written from the `onCancel` handler (nonisolated context)
/// and read from the main actor after a sequence of `Task.yield()` calls that
/// ensure the cancellation has propagated. `nonisolated(unsafe)` is safe here
/// because:
///   1. The value is written exactly once in `onCancel`.
///   2. Test assertions always follow multiple `Task.yield()` calls that give
///      the runtime enough scheduling cycles to execute the cancel handler.
///   3. No concurrent reads happen; this is a strictly sequential test pattern.
@MainActor
private final class SlowCancellationPrefetchService: ThumbnailPrefetching {

    // RATIONALE: nonisolated(unsafe) so the onCancel handler can write from a
    // nonisolated context without a @MainActor hop. The single-write, read-after-
    // yield discipline in the tests makes this safe in practice.
    nonisolated(unsafe) private(set) var wasCancelled = false

    func prefetchThumbnails() async {
        // Suspend until cancelled
        await withTaskCancellationHandler {
            // Keep yielding until Task.isCancelled is true
            while !Task.isCancelled {
                await Task.yield()
            }
        } onCancel: { [weak self] in
            self?.wasCancelled = true
        }
    }
}
