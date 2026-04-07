import Testing
import Foundation
@testable import RSSApp

@Suite("FeedListViewModel Network Gating Tests")
struct FeedListViewModelNetworkTests {

    // MARK: - Thumbnail Prefetch Gating

    @Test("refreshAllFeeds invokes thumbnail prefetcher when background downloads allowed")
    @MainActor
    func prefetchRunsWhenNetworkAllowed() async {
        let url = URL(string: "https://example.com/feed")!
        let feed = TestFixtures.makePersistentFeed(title: "Feed", feedURL: url)

        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]
        let mockFetching = MockFeedFetchingService()
        mockFetching.feedsByURL = [url: TestFixtures.makeFeed(title: "Updated")]
        let mockPrefetcher = MockThumbnailPrefetchService()
        let mockNetwork = MockNetworkMonitorService()
        mockNetwork.backgroundDownloadAllowed = true

        let viewModel = FeedListViewModel(
            persistence: mockPersistence,
            feedFetching: mockFetching,
            feedIconService: MockFeedIconService(),
            thumbnailPrefetcher: mockPrefetcher,
            networkMonitor: mockNetwork
        )
        viewModel.loadFeeds()

        await withCheckedContinuation { continuation in
            mockPrefetcher.prefetchContinuation = continuation
            Task {
                await viewModel.refreshAllFeeds()
            }
        }

        #expect(mockPrefetcher.prefetchCallCount == 1)
    }

    @Test("refreshAllFeeds skips thumbnail prefetcher when background downloads not allowed")
    @MainActor
    func prefetchSkippedWhenNetworkDisallowed() async {
        let url = URL(string: "https://example.com/feed")!
        let feed = TestFixtures.makePersistentFeed(title: "Feed", feedURL: url)

        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]
        let mockFetching = MockFeedFetchingService()
        mockFetching.feedsByURL = [url: TestFixtures.makeFeed(title: "Updated")]
        let mockPrefetcher = MockThumbnailPrefetchService()
        let mockNetwork = MockNetworkMonitorService()
        mockNetwork.backgroundDownloadAllowed = false

        let viewModel = FeedListViewModel(
            persistence: mockPersistence,
            feedFetching: mockFetching,
            feedIconService: MockFeedIconService(),
            thumbnailPrefetcher: mockPrefetcher,
            networkMonitor: mockNetwork
        )
        viewModel.loadFeeds()
        await viewModel.refreshAllFeeds()

        #expect(mockPrefetcher.prefetchCallCount == 0)
    }

    // MARK: - Icon Resolution Gating

    @Test("refreshAllFeeds resolves icons when background downloads allowed")
    @MainActor
    func iconResolutionRunsWhenNetworkAllowed() async {
        let url = URL(string: "https://example.com/feed")!
        let feed = TestFixtures.makePersistentFeed(feedURL: url)

        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]
        let mockFetching = MockFeedFetchingService()
        mockFetching.feedsByURL = [url: TestFixtures.makeFeed()]
        let mockIconService = MockFeedIconService()
        let mockNetwork = MockNetworkMonitorService()
        mockNetwork.backgroundDownloadAllowed = true

        let viewModel = FeedListViewModel(
            persistence: mockPersistence,
            feedFetching: mockFetching,
            feedIconService: mockIconService,
            networkMonitor: mockNetwork
        )
        viewModel.loadFeeds()
        await viewModel.refreshAllFeeds()

        // Allow fire-and-forget icon resolution tasks to complete
        for _ in 0..<10 { await Task.yield() }

        #expect(mockIconService.resolveAndCacheCallCount == 1)
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

        let viewModel = FeedListViewModel(
            persistence: mockPersistence,
            feedFetching: mockFetching,
            feedIconService: mockIconService,
            networkMonitor: mockNetwork
        )
        viewModel.loadFeeds()
        await viewModel.refreshAllFeeds()

        // Allow any potential fire-and-forget tasks to complete
        for _ in 0..<10 { await Task.yield() }

        #expect(mockIconService.resolveAndCacheCallCount == 0)
    }

    @Test("refreshAllFeeds skips icon resolution on 304 Not Modified when downloads not allowed")
    @MainActor
    func iconResolutionSkippedOn304WhenNetworkDisallowed() async {
        let url = URL(string: "https://example.com/feed")!
        let feed = TestFixtures.makePersistentFeed(title: "Existing", feedURL: url)

        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]
        let mockFetching = MockFeedFetchingService()
        mockFetching.shouldReturn304 = true
        let mockIconService = MockFeedIconService()
        let mockNetwork = MockNetworkMonitorService()
        mockNetwork.backgroundDownloadAllowed = false

        let viewModel = FeedListViewModel(
            persistence: mockPersistence,
            feedFetching: mockFetching,
            feedIconService: mockIconService,
            networkMonitor: mockNetwork
        )
        viewModel.loadFeeds()
        await viewModel.refreshAllFeeds()

        // Allow any potential fire-and-forget tasks to complete
        for _ in 0..<10 { await Task.yield() }

        #expect(mockIconService.resolveAndCacheCallCount == 0)
    }

    @Test("refreshAllFeeds resolves icon on 304 Not Modified when downloads allowed")
    @MainActor
    func iconResolutionRunsOn304WhenNetworkAllowed() async {
        let url = URL(string: "https://example.com/feed")!
        let feed = TestFixtures.makePersistentFeed(title: "Existing", feedURL: url)

        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]
        let mockFetching = MockFeedFetchingService()
        mockFetching.shouldReturn304 = true
        let mockIconService = MockFeedIconService()
        let mockNetwork = MockNetworkMonitorService()
        mockNetwork.backgroundDownloadAllowed = true

        let viewModel = FeedListViewModel(
            persistence: mockPersistence,
            feedFetching: mockFetching,
            feedIconService: mockIconService,
            networkMonitor: mockNetwork
        )
        viewModel.loadFeeds()
        await viewModel.refreshAllFeeds()

        // Allow fire-and-forget icon resolution tasks to complete
        for _ in 0..<10 { await Task.yield() }

        #expect(mockIconService.resolveAndCacheCallCount == 1)
    }

    // MARK: - Refresh Continues Regardless of Network

    @Test("refreshAllFeeds still refreshes feed content even when background downloads not allowed")
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

        let viewModel = FeedListViewModel(
            persistence: mockPersistence,
            feedFetching: mockFetching,
            feedIconService: MockFeedIconService(),
            networkMonitor: mockNetwork
        )
        viewModel.loadFeeds()
        await viewModel.refreshAllFeeds()

        // Feed metadata should still be updated
        #expect(viewModel.feeds[0].title == "Updated")
        #expect(viewModel.errorMessage == nil)
    }
}
