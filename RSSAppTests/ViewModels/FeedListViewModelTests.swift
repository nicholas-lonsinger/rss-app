import Testing
import Foundation
import SwiftData
@testable import RSSApp

@Suite("FeedListViewModel Tests")
struct FeedListViewModelTests {

    /// Builds a view model wired to a fully-mocked `FeedRefreshService`.
    /// Tests that only touch load/remove/OPML/unread paths use this helper;
    /// tests that exercise refresh-specific behavior (icon cleanup,
    /// delegation-to-error-message translation) construct the service
    /// explicitly via `makeRefreshService` so they can override specific
    /// mocks.
    @MainActor
    private static func makeViewModel(
        persistence: FeedPersisting,
        opmlService: OPMLServing = MockOPMLService()
    ) -> FeedListViewModel {
        let mockIconService = MockFeedIconService()
        return FeedListViewModel(
            persistence: persistence,
            refreshService: Self.makeRefreshService(persistence: persistence, feedIconService: mockIconService),
            feedIconService: mockIconService,
            opmlService: opmlService
        )
    }

    /// Builds a fully-mocked `FeedRefreshService` for tests that need to
    /// exercise refresh behavior. Every dependency defaults to a mock so
    /// tests never accidentally spawn real network or disk I/O — e.g.,
    /// the default `FeedIconService()` would fetch from the feed URL's
    /// host, and the default `NetworkMonitorService()` would start a
    /// real `NWPathMonitor`.
    @MainActor
    private static func makeRefreshService(
        persistence: FeedPersisting,
        feedFetching: FeedFetching = MockFeedFetchingService(),
        feedIconService: FeedIconResolving = MockFeedIconService(),
        thumbnailPrefetcher: ThumbnailPrefetching = MockThumbnailPrefetchService(),
        articleRetention: ArticleRetaining = MockArticleRetentionService(),
        thumbnailService: ArticleThumbnailCaching = MockArticleThumbnailService(),
        networkMonitor: NetworkMonitoring = MockNetworkMonitorService()
    ) -> FeedRefreshService {
        FeedRefreshService(
            persistence: persistence,
            feedFetching: feedFetching,
            feedIconService: feedIconService,
            thumbnailPrefetcher: thumbnailPrefetcher,
            articleRetention: articleRetention,
            thumbnailService: thumbnailService,
            networkMonitor: networkMonitor
        )
    }

    @Test("loadFeeds populates feeds from persistence")
    @MainActor
    func loadFeedsFromStorage() {
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [
            TestFixtures.makePersistentFeed(title: "Feed A"),
            TestFixtures.makePersistentFeed(title: "Feed B"),
        ]

        let viewModel = Self.makeViewModel(persistence: mockPersistence)
        viewModel.loadFeeds()

        #expect(viewModel.feeds.count == 2)
        #expect(viewModel.feeds[0].title == "Feed A")
        #expect(viewModel.feeds[1].title == "Feed B")
        #expect(viewModel.errorMessage == nil)
    }

    @Test("loadFeeds returns empty when persistence is empty")
    @MainActor
    func loadFeedsEmpty() {
        let mockPersistence = MockFeedPersistenceService()
        let viewModel = Self.makeViewModel(persistence: mockPersistence)
        viewModel.loadFeeds()

        #expect(viewModel.feeds.isEmpty)
    }

    @Test("loadFeeds sets errorMessage on persistence failure")
    @MainActor
    func loadFeedsError() {
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.errorToThrow = NSError(domain: "test", code: 1)

        let viewModel = Self.makeViewModel(persistence: mockPersistence)
        viewModel.loadFeeds()

        #expect(viewModel.feeds.isEmpty)
        #expect(viewModel.errorMessage != nil)
    }

    @Test("removeFeed removes by feed object")
    @MainActor
    func removeFeedByObject() {
        let feed1 = TestFixtures.makePersistentFeed(title: "Keep")
        let feed2 = TestFixtures.makePersistentFeed(title: "Remove")
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed1, feed2]

        let viewModel = Self.makeViewModel(persistence: mockPersistence)
        viewModel.loadFeeds()
        viewModel.removeFeed(feed2)

        #expect(viewModel.feeds.count == 1)
        #expect(viewModel.feeds[0].title == "Keep")
    }

    @Test("removeFeed at IndexSet removes by index")
    @MainActor
    func removeFeedAtIndexSet() {
        let feed1 = TestFixtures.makePersistentFeed(title: "First")
        let feed2 = TestFixtures.makePersistentFeed(title: "Second")
        let feed3 = TestFixtures.makePersistentFeed(title: "Third")
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed1, feed2, feed3]

        let viewModel = Self.makeViewModel(persistence: mockPersistence)
        viewModel.loadFeeds()
        viewModel.removeFeed(at: IndexSet(integer: 1))

        #expect(viewModel.feeds.count == 2)
        #expect(viewModel.feeds[0].title == "First")
        #expect(viewModel.feeds[1].title == "Third")
    }

    @Test("removeFeed rolls back on persistence failure")
    @MainActor
    func removeFeedSaveFailure() {
        let feed1 = TestFixtures.makePersistentFeed(title: "Feed")
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed1]

        let viewModel = Self.makeViewModel(persistence: mockPersistence)
        viewModel.loadFeeds()

        mockPersistence.errorToThrow = NSError(domain: "test", code: 1)
        viewModel.removeFeed(feed1)

        #expect(viewModel.feeds.count == 1)
        #expect(viewModel.errorMessage != nil)
    }

    @Test("removeFeed at IndexSet rolls back on persistence failure")
    @MainActor
    func removeFeedAtIndexSetSaveFailure() {
        let feed1 = TestFixtures.makePersistentFeed(title: "First")
        let feed2 = TestFixtures.makePersistentFeed(title: "Second")
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed1, feed2]

        let viewModel = Self.makeViewModel(persistence: mockPersistence)
        viewModel.loadFeeds()

        mockPersistence.errorToThrow = NSError(domain: "test", code: 1)
        viewModel.removeFeed(at: IndexSet(integer: 0))

        #expect(viewModel.feeds.count == 2)
        #expect(viewModel.feeds[0].title == "First")
        #expect(viewModel.errorMessage != nil)
        #expect(viewModel.importExportErrorMessage == nil)
    }

    // MARK: - Icon Cache Cleanup

    @Test("removeFeed deletes cached icon")
    @MainActor
    func removeFeedDeletesCachedIcon() {
        let feed = TestFixtures.makePersistentFeed(title: "Remove Me")
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]
        let mockIconService = MockFeedIconService()
        let refreshService = FeedRefreshService(persistence: mockPersistence, feedIconService: mockIconService)

        let viewModel = FeedListViewModel(
            persistence: mockPersistence,
            refreshService: refreshService,
            feedIconService: mockIconService
        )
        viewModel.loadFeeds()
        viewModel.removeFeed(feed)

        #expect(mockIconService.deleteCallCount == 1)
    }

    @Test("removeFeed at IndexSet deletes cached icons for each removed feed")
    @MainActor
    func removeFeedAtIndexSetDeletesCachedIcons() {
        let feed1 = TestFixtures.makePersistentFeed(title: "First")
        let feed2 = TestFixtures.makePersistentFeed(title: "Second")
        let feed3 = TestFixtures.makePersistentFeed(title: "Third")
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed1, feed2, feed3]
        let mockIconService = MockFeedIconService()
        let refreshService = FeedRefreshService(persistence: mockPersistence, feedIconService: mockIconService)

        let viewModel = FeedListViewModel(
            persistence: mockPersistence,
            refreshService: refreshService,
            feedIconService: mockIconService
        )
        viewModel.loadFeeds()
        viewModel.removeFeed(at: IndexSet([0, 2]))

        #expect(mockIconService.deleteCallCount == 2)
    }

    // MARK: - Unread Counts

    @Test("loadFeeds populates unread counts")
    @MainActor
    func loadFeedsPopulatesUnreadCounts() {
        let feed = TestFixtures.makePersistentFeed(title: "Feed A")
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]
        mockPersistence.articlesByFeedID = [
            feed.id: [
                TestFixtures.makePersistentArticle(articleID: "1", isRead: false),
                TestFixtures.makePersistentArticle(articleID: "2", isRead: true),
                TestFixtures.makePersistentArticle(articleID: "3", isRead: false),
            ],
        ]

        let viewModel = Self.makeViewModel(persistence: mockPersistence)
        viewModel.loadFeeds()

        #expect(viewModel.unreadCount(for: feed) == 2)
    }

    @Test("refreshUnreadCounts updates counts after read status changes")
    @MainActor
    func refreshUnreadCountsUpdatesAfterRead() {
        let feed = TestFixtures.makePersistentFeed(title: "Feed A")
        let article = TestFixtures.makePersistentArticle(articleID: "1", isRead: false)
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]
        mockPersistence.articlesByFeedID = [feed.id: [article]]

        let viewModel = Self.makeViewModel(persistence: mockPersistence)
        viewModel.loadFeeds()
        #expect(viewModel.unreadCount(for: feed) == 1)

        article.isRead = true
        viewModel.refreshUnreadCounts()
        #expect(viewModel.unreadCount(for: feed) == 0)
        #expect(viewModel.errorMessage == nil)
    }

    @Test("unreadCount returns zero for unknown feed")
    @MainActor
    func unreadCountReturnsZeroForUnknownFeed() {
        let mockPersistence = MockFeedPersistenceService()
        let viewModel = Self.makeViewModel(persistence: mockPersistence)
        viewModel.loadFeeds()

        let unknownFeed = TestFixtures.makePersistentFeed(title: "Unknown")
        #expect(viewModel.unreadCount(for: unknownFeed) == 0)
    }

    @Test("refreshUnreadCounts preserves previous count on persistence error")
    @MainActor
    func refreshUnreadCountsPreservesPreviousCountOnError() {
        let feed = TestFixtures.makePersistentFeed(title: "Feed A")
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]
        mockPersistence.articlesByFeedID = [
            feed.id: [TestFixtures.makePersistentArticle(articleID: "1", isRead: false)],
        ]

        let viewModel = Self.makeViewModel(persistence: mockPersistence)
        viewModel.loadFeeds()
        #expect(viewModel.unreadCount(for: feed) == 1)

        mockPersistence.unreadCountError = NSError(domain: "test", code: 1)
        viewModel.refreshUnreadCounts()
        #expect(viewModel.unreadCount(for: feed) == 1)
    }

    @Test("refreshUnreadCounts falls back to zero when no previous count exists on error")
    @MainActor
    func refreshUnreadCountsFallsBackToZeroWhenNoPreviousCount() {
        let feed = TestFixtures.makePersistentFeed(title: "Feed A")
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]
        mockPersistence.unreadCountError = NSError(domain: "test", code: 1)

        let viewModel = Self.makeViewModel(persistence: mockPersistence)
        viewModel.loadFeeds()
        #expect(viewModel.unreadCount(for: feed) == 0)
    }

    @Test("refreshUnreadCount updates only the specified feed")
    @MainActor
    func refreshUnreadCountForSingleFeed() {
        let feed1 = TestFixtures.makePersistentFeed(title: "Feed A")
        let feed2 = TestFixtures.makePersistentFeed(title: "Feed B")
        let article = TestFixtures.makePersistentArticle(articleID: "1", isRead: false)
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed1, feed2]
        mockPersistence.articlesByFeedID = [
            feed1.id: [article],
            feed2.id: [TestFixtures.makePersistentArticle(articleID: "2", isRead: false)],
        ]

        let viewModel = Self.makeViewModel(persistence: mockPersistence)
        viewModel.loadFeeds()
        #expect(viewModel.unreadCount(for: feed1) == 1)
        #expect(viewModel.unreadCount(for: feed2) == 1)

        article.isRead = true
        viewModel.refreshUnreadCount(for: feed1)
        #expect(viewModel.unreadCount(for: feed1) == 0)
        #expect(viewModel.unreadCount(for: feed2) == 1)
    }

    @Test("refreshUnreadCount preserves previous count on persistence error for single feed")
    @MainActor
    func refreshUnreadCountPreservesPreviousCountOnError() {
        let feed = TestFixtures.makePersistentFeed(title: "Feed A")
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]
        mockPersistence.articlesByFeedID = [
            feed.id: [
                TestFixtures.makePersistentArticle(articleID: "1", isRead: false),
                TestFixtures.makePersistentArticle(articleID: "2", isRead: false),
            ],
        ]

        let viewModel = Self.makeViewModel(persistence: mockPersistence)
        viewModel.loadFeeds()
        #expect(viewModel.unreadCount(for: feed) == 2)

        mockPersistence.unreadCountError = NSError(domain: "test", code: 1)
        viewModel.refreshUnreadCount(for: feed)
        #expect(viewModel.unreadCount(for: feed) == 2)
    }

    @Test("refreshUnreadCount returns zero when no previous count exists on error for single feed")
    @MainActor
    func refreshUnreadCountFallsBackToZeroWhenNoPreviousCountForSingleFeed() {
        let feed = TestFixtures.makePersistentFeed(title: "Feed A")
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]
        mockPersistence.unreadCountError = NSError(domain: "test", code: 1)

        let viewModel = Self.makeViewModel(persistence: mockPersistence)
        // Do not call loadFeeds() — no previous count is established
        viewModel.refreshUnreadCount(for: feed)
        #expect(viewModel.unreadCount(for: feed) == 0)
    }

    @Test("refreshUnreadCounts updates successful feeds and preserves previous counts for failed feeds in mixed batch")
    @MainActor
    func refreshUnreadCountsMixedSuccessAndFailure() {
        let feedA = TestFixtures.makePersistentFeed(title: "Feed A")
        let feedB = TestFixtures.makePersistentFeed(title: "Feed B")
        let feedC = TestFixtures.makePersistentFeed(title: "Feed C")
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feedA, feedB, feedC]
        mockPersistence.articlesByFeedID = [
            feedA.id: [
                TestFixtures.makePersistentArticle(articleID: "a1", isRead: false),
                TestFixtures.makePersistentArticle(articleID: "a2", isRead: false),
            ],
            feedB.id: [
                TestFixtures.makePersistentArticle(articleID: "b1", isRead: false),
            ],
            feedC.id: [
                TestFixtures.makePersistentArticle(articleID: "c1", isRead: false),
                TestFixtures.makePersistentArticle(articleID: "c2", isRead: false),
                TestFixtures.makePersistentArticle(articleID: "c3", isRead: false),
            ],
        ]

        let viewModel = Self.makeViewModel(persistence: mockPersistence)
        viewModel.loadFeeds()

        // Establish initial counts: A=2, B=1, C=3
        #expect(viewModel.unreadCount(for: feedA) == 2)
        #expect(viewModel.unreadCount(for: feedB) == 1)
        #expect(viewModel.unreadCount(for: feedC) == 3)

        // Mark one article read in Feed A so the real count changes
        mockPersistence.articlesByFeedID[feedA.id]?[0].isRead = true

        // Inject per-feed errors: Feed B fails, A and C succeed
        mockPersistence.unreadCountErrorByFeedID[feedB.id] = NSError(domain: "test", code: 1)

        viewModel.refreshUnreadCounts()

        // Feed A: succeeded — should reflect the updated count (1 unread now)
        #expect(viewModel.unreadCount(for: feedA) == 1)
        // Feed B: failed — should preserve the previous count (1)
        #expect(viewModel.unreadCount(for: feedB) == 1)
        // Feed C: succeeded — should reflect the current count (3)
        #expect(viewModel.unreadCount(for: feedC) == 3)
        // Error message should be set because at least one feed failed
        #expect(viewModel.errorMessage == "Unable to update unread counts.")
    }

    @Test("refreshUnreadCounts sets errorMessage on persistence error")
    @MainActor
    func refreshUnreadCountsSetsErrorMessageOnError() {
        let feed = TestFixtures.makePersistentFeed(title: "Feed A")
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]
        mockPersistence.articlesByFeedID = [
            feed.id: [TestFixtures.makePersistentArticle(articleID: "1", isRead: false)],
        ]

        let viewModel = Self.makeViewModel(persistence: mockPersistence)
        viewModel.loadFeeds()
        #expect(viewModel.errorMessage == nil)

        mockPersistence.unreadCountError = NSError(domain: "test", code: 1)
        viewModel.refreshUnreadCounts()
        #expect(viewModel.errorMessage == "Unable to update unread counts.")
    }

    @Test("refreshUnreadCount sets errorMessage on persistence error for single feed")
    @MainActor
    func refreshUnreadCountSetsErrorMessageOnErrorForSingleFeed() {
        let feed = TestFixtures.makePersistentFeed(title: "Feed A")
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]
        mockPersistence.articlesByFeedID = [
            feed.id: [TestFixtures.makePersistentArticle(articleID: "1", isRead: false)],
        ]

        let viewModel = Self.makeViewModel(persistence: mockPersistence)
        viewModel.loadFeeds()
        #expect(viewModel.errorMessage == nil)

        mockPersistence.unreadCountError = NSError(domain: "test", code: 1)
        viewModel.refreshUnreadCount(for: feed)
        #expect(viewModel.errorMessage == "Unable to update unread count.")
    }

    @Test("loadFeeds surfaces refreshUnreadCounts errorMessage")
    @MainActor
    func loadFeedsSurfacesUnreadCountError() {
        let feed = TestFixtures.makePersistentFeed(title: "Feed A")
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]
        mockPersistence.unreadCountError = NSError(domain: "test", code: 1)

        let viewModel = Self.makeViewModel(persistence: mockPersistence)
        viewModel.loadFeeds()

        // loadFeeds clears errorMessage before calling refreshUnreadCounts,
        // so the unread count error should still be visible.
        #expect(viewModel.errorMessage == "Unable to update unread counts.")
    }

    @Test("refreshUnreadCounts clears errorMessage on success after previous error")
    @MainActor
    func refreshUnreadCountsClearsErrorOnSuccess() {
        let feed = TestFixtures.makePersistentFeed(title: "Feed A")
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]
        mockPersistence.articlesByFeedID = [
            feed.id: [TestFixtures.makePersistentArticle(articleID: "1", isRead: false)],
        ]

        let viewModel = Self.makeViewModel(persistence: mockPersistence)
        viewModel.loadFeeds()

        // Induce an error first
        mockPersistence.unreadCountError = NSError(domain: "test", code: 1)
        viewModel.refreshUnreadCounts()
        #expect(viewModel.errorMessage == "Unable to update unread counts.")

        // Clear the error and refresh again — errorMessage should clear
        mockPersistence.unreadCountError = nil
        viewModel.refreshUnreadCounts()
        #expect(viewModel.errorMessage == nil)
    }

    @Test("refreshUnreadCount clears errorMessage on success after previous error for single feed")
    @MainActor
    func refreshUnreadCountClearsErrorOnSuccessForSingleFeed() {
        let feed = TestFixtures.makePersistentFeed(title: "Feed A")
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]
        mockPersistence.articlesByFeedID = [
            feed.id: [TestFixtures.makePersistentArticle(articleID: "1", isRead: false)],
        ]

        let viewModel = Self.makeViewModel(persistence: mockPersistence)
        viewModel.loadFeeds()

        // Induce an error first
        mockPersistence.unreadCountError = NSError(domain: "test", code: 1)
        viewModel.refreshUnreadCount(for: feed)
        #expect(viewModel.errorMessage == "Unable to update unread count.")

        // Clear the error and refresh again — errorMessage should clear
        mockPersistence.unreadCountError = nil
        viewModel.refreshUnreadCount(for: feed)
        #expect(viewModel.errorMessage == nil)
    }

    @Test("removeFeed cleans up unread counts dictionary")
    @MainActor
    func removeFeedCleansUpUnreadCounts() {
        let feed1 = TestFixtures.makePersistentFeed(title: "Keep")
        let feed2 = TestFixtures.makePersistentFeed(title: "Remove")
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed1, feed2]
        mockPersistence.articlesByFeedID = [
            feed1.id: [TestFixtures.makePersistentArticle(articleID: "1", isRead: false)],
            feed2.id: [TestFixtures.makePersistentArticle(articleID: "2", isRead: false)],
        ]

        let viewModel = Self.makeViewModel(persistence: mockPersistence)
        viewModel.loadFeeds()
        #expect(viewModel.unreadCount(for: feed1) == 1)
        #expect(viewModel.unreadCount(for: feed2) == 1)

        viewModel.removeFeed(feed2)
        #expect(viewModel.unreadCount(for: feed1) == 1)
        #expect(viewModel.unreadCount(for: feed2) == 0)
    }

    // MARK: - OPML Import

    @Test("importOPML sets error on parse failure")
    @MainActor
    func importOPMLSetsErrorOnParseFailure() {
        let mockPersistence = MockFeedPersistenceService()
        let mockOPML = MockOPMLService()
        mockOPML.errorToThrow = NSError(domain: "test", code: 1)

        let viewModel = Self.makeViewModel(persistence: mockPersistence, opmlService: mockOPML)
        viewModel.importOPML(from: Data())

        #expect(viewModel.importExportErrorMessage != nil)
    }

    // MARK: - OPML Export

    @Test("exportOPML sets export URL")
    @MainActor
    func exportOPMLSetsURL() {
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [
            TestFixtures.makePersistentFeed(title: "Feed A"),
        ]
        let mockOPML = MockOPMLService()
        mockOPML.dataToReturn = Data("opml-content".utf8)

        let viewModel = Self.makeViewModel(persistence: mockPersistence, opmlService: mockOPML)
        viewModel.loadFeeds()
        viewModel.exportOPML()

        #expect(viewModel.opmlExportURL != nil)
        #expect(viewModel.importExportErrorMessage == nil)
    }

    @Test("exportOPML sets error on failure")
    @MainActor
    func exportOPMLSetsErrorOnFailure() {
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [TestFixtures.makePersistentFeed()]
        let mockOPML = MockOPMLService()
        mockOPML.errorToThrow = NSError(domain: "test", code: 1)

        let viewModel = Self.makeViewModel(persistence: mockPersistence, opmlService: mockOPML)
        viewModel.loadFeeds()
        viewModel.exportOPML()

        #expect(viewModel.opmlExportURL == nil)
        #expect(viewModel.importExportErrorMessage != nil)
    }


    // MARK: - OPML Import (Happy Paths)

    @Test("importOPML adds new feeds")
    @MainActor
    func importOPMLAddsNewFeeds() {
        let mockPersistence = MockFeedPersistenceService()
        let mockOPML = MockOPMLService()
        mockOPML.entriesToReturn = [
            TestFixtures.makeOPMLFeedEntry(title: "Feed A", feedURL: URL(string: "https://a.com/feed")!),
            TestFixtures.makeOPMLFeedEntry(title: "Feed B", feedURL: URL(string: "https://b.com/feed")!),
        ]

        let viewModel = Self.makeViewModel(persistence: mockPersistence, opmlService: mockOPML)
        viewModel.importOPML(from: Data())

        #expect(viewModel.feeds.count == 2)
        #expect(viewModel.opmlImportResult?.addedCount == 2)
        #expect(viewModel.opmlImportResult?.skippedCount == 0)
        #expect(viewModel.importExportErrorMessage == nil)
    }

    @Test("importOPML skips duplicate feeds")
    @MainActor
    func importOPMLSkipsDuplicates() {
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [
            TestFixtures.makePersistentFeed(title: "Existing", feedURL: URL(string: "https://existing.com/feed")!),
        ]

        let mockOPML = MockOPMLService()
        mockOPML.entriesToReturn = [
            TestFixtures.makeOPMLFeedEntry(title: "Existing Dupe", feedURL: URL(string: "https://existing.com/feed")!),
            TestFixtures.makeOPMLFeedEntry(title: "New Feed", feedURL: URL(string: "https://new.com/feed")!),
        ]

        let viewModel = Self.makeViewModel(persistence: mockPersistence, opmlService: mockOPML)
        viewModel.loadFeeds()
        viewModel.importOPML(from: Data())

        #expect(viewModel.feeds.count == 2)
        #expect(viewModel.opmlImportResult?.addedCount == 1)
        #expect(viewModel.opmlImportResult?.skippedCount == 1)
    }

    @Test("importOPML with all duplicates adds nothing")
    @MainActor
    func importOPMLAllDuplicates() {
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [
            TestFixtures.makePersistentFeed(feedURL: URL(string: "https://a.com/feed")!),
        ]

        let mockOPML = MockOPMLService()
        mockOPML.entriesToReturn = [
            TestFixtures.makeOPMLFeedEntry(feedURL: URL(string: "https://a.com/feed")!),
        ]

        let viewModel = Self.makeViewModel(persistence: mockPersistence, opmlService: mockOPML)
        viewModel.loadFeeds()
        viewModel.importOPML(from: Data())

        #expect(viewModel.feeds.count == 1)
        #expect(viewModel.opmlImportResult?.addedCount == 0)
        #expect(viewModel.opmlImportResult?.skippedCount == 1)
    }

    @Test("importOPML sets correct result counts")
    @MainActor
    func importOPMLSetsResultCounts() {
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [
            TestFixtures.makePersistentFeed(feedURL: URL(string: "https://existing.com/feed")!),
        ]

        let mockOPML = MockOPMLService()
        mockOPML.entriesToReturn = [
            TestFixtures.makeOPMLFeedEntry(feedURL: URL(string: "https://existing.com/feed")!),
            TestFixtures.makeOPMLFeedEntry(feedURL: URL(string: "https://new1.com/feed")!),
            TestFixtures.makeOPMLFeedEntry(feedURL: URL(string: "https://new2.com/feed")!),
        ]

        let viewModel = Self.makeViewModel(persistence: mockPersistence, opmlService: mockOPML)
        viewModel.loadFeeds()
        viewModel.importOPML(from: Data())

        #expect(viewModel.opmlImportResult?.addedCount == 2)
        #expect(viewModel.opmlImportResult?.skippedCount == 1)
    }

    @Test("importOPMLAndRefresh adds feeds then refreshes metadata")
    @MainActor
    func importOPMLAndRefreshIntegration() async {
        let url1 = URL(string: "https://one.com/feed")!
        let url2 = URL(string: "https://two.com/feed")!

        let mockPersistence = MockFeedPersistenceService()
        let mockOPML = MockOPMLService()
        mockOPML.entriesToReturn = [
            TestFixtures.makeOPMLFeedEntry(title: "OPML One", feedURL: url1, description: ""),
            TestFixtures.makeOPMLFeedEntry(title: "OPML Two", feedURL: url2, description: ""),
        ]
        let mockFetching = MockFeedFetchingService()
        mockFetching.feedsByURL = [
            url1: TestFixtures.makeFeed(title: "Real One", feedDescription: "Real Desc"),
            url2: TestFixtures.makeFeed(title: "Real Two", feedDescription: "Real Desc"),
        ]

        let mockIconService = MockFeedIconService()
        let refreshService = FeedRefreshService(
            persistence: mockPersistence,
            feedFetching: mockFetching,
            feedIconService: mockIconService,
            networkMonitor: MockNetworkMonitorService()
        )
        let viewModel = FeedListViewModel(
            persistence: mockPersistence,
            refreshService: refreshService,
            feedIconService: mockIconService,
            opmlService: mockOPML
        )
        await viewModel.importOPMLAndRefresh(from: Data())

        #expect(viewModel.feeds.count == 2)
        #expect(viewModel.opmlImportResult?.addedCount == 2)
    }

    @Test("importOPML deduplicates within the same file")
    @MainActor
    func importOPMLIntraFileDuplicates() {
        let mockPersistence = MockFeedPersistenceService()
        let mockOPML = MockOPMLService()
        mockOPML.entriesToReturn = [
            TestFixtures.makeOPMLFeedEntry(title: "Feed A", feedURL: URL(string: "https://a.com/feed")!),
            TestFixtures.makeOPMLFeedEntry(title: "Feed A Dupe", feedURL: URL(string: "https://a.com/feed")!),
            TestFixtures.makeOPMLFeedEntry(title: "Feed B", feedURL: URL(string: "https://b.com/feed")!),
        ]

        let viewModel = Self.makeViewModel(persistence: mockPersistence, opmlService: mockOPML)
        viewModel.importOPML(from: Data())

        // Two unique URLs in the file → two feeds added. The second appearance of
        // Feed A is not a pre-existing duplicate, so it is not counted as skipped.
        #expect(viewModel.feeds.count == 2)
        #expect(viewModel.opmlImportResult?.addedCount == 2)
        #expect(viewModel.opmlImportResult?.skippedCount == 0)
    }

    @Test("importOPML continues past persistence failures and reports partial progress")
    @MainActor
    func importOPMLPersistenceFailureMidImport() {
        let mockPersistence = MockFeedPersistenceService()
        // First addFeed succeeds, second and third fail
        mockPersistence.addFeedFailureAfterCount = 1
        let mockOPML = MockOPMLService()
        mockOPML.entriesToReturn = [
            TestFixtures.makeOPMLFeedEntry(title: "Feed A", feedURL: URL(string: "https://a.com/feed")!),
            TestFixtures.makeOPMLFeedEntry(title: "Feed B", feedURL: URL(string: "https://b.com/feed")!),
            TestFixtures.makeOPMLFeedEntry(title: "Feed C", feedURL: URL(string: "https://c.com/feed")!),
        ]

        let viewModel = Self.makeViewModel(persistence: mockPersistence, opmlService: mockOPML)
        viewModel.importOPML(from: Data())

        // First feed added successfully, remaining two failed — import continues
        #expect(viewModel.feeds.count == 1)
        #expect(viewModel.opmlImportResult?.addedCount == 1)
        #expect(viewModel.opmlImportResult?.failedCount == 2)
        #expect(viewModel.importExportErrorMessage == nil)
        #expect(viewModel.errorMessage == nil)
    }

    // MARK: - Error Isolation

    @Test("importOPML error does not set errorMessage")
    @MainActor
    func importOPMLErrorDoesNotSetErrorMessage() {
        let mockPersistence = MockFeedPersistenceService()
        let mockOPML = MockOPMLService()
        mockOPML.errorToThrow = NSError(domain: "test", code: 1)

        let viewModel = Self.makeViewModel(persistence: mockPersistence, opmlService: mockOPML)
        viewModel.importOPML(from: Data())

        #expect(viewModel.importExportErrorMessage != nil)
        #expect(viewModel.errorMessage == nil)
    }

    @Test("exportOPML error does not set errorMessage")
    @MainActor
    func exportOPMLErrorDoesNotSetErrorMessage() {
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [TestFixtures.makePersistentFeed()]
        let mockOPML = MockOPMLService()
        mockOPML.errorToThrow = NSError(domain: "test", code: 1)

        let viewModel = Self.makeViewModel(persistence: mockPersistence, opmlService: mockOPML)
        viewModel.loadFeeds()
        viewModel.exportOPML()

        #expect(viewModel.importExportErrorMessage != nil)
        #expect(viewModel.errorMessage == nil)
    }

    @Test("feed load error does not set importExportErrorMessage")
    @MainActor
    func feedLoadErrorDoesNotSetImportExportErrorMessage() {
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.errorToThrow = NSError(domain: "test", code: 1)

        let viewModel = Self.makeViewModel(persistence: mockPersistence)
        viewModel.loadFeeds()

        #expect(viewModel.errorMessage != nil)
        #expect(viewModel.importExportErrorMessage == nil)
    }

    @Test("feed removal error does not set importExportErrorMessage")
    @MainActor
    func feedRemovalErrorDoesNotSetImportExportErrorMessage() {
        let feed = TestFixtures.makePersistentFeed(title: "Feed")
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]

        let viewModel = Self.makeViewModel(persistence: mockPersistence)
        viewModel.loadFeeds()

        mockPersistence.errorToThrow = NSError(domain: "test", code: 1)
        viewModel.removeFeed(feed)

        #expect(viewModel.errorMessage != nil)
        #expect(viewModel.importExportErrorMessage == nil)
    }

    @Test("importOPML clears stale importExportErrorMessage before processing")
    @MainActor
    func importOPMLClearsStaleError() {
        let mockPersistence = MockFeedPersistenceService()
        let mockOPML = MockOPMLService()
        mockOPML.entriesToReturn = [
            TestFixtures.makeOPMLFeedEntry(title: "Feed A", feedURL: URL(string: "https://a.com/feed")!),
        ]

        let viewModel = Self.makeViewModel(persistence: mockPersistence, opmlService: mockOPML)
        // Simulate stale error from a previous operation
        viewModel.importExportErrorMessage = "Previous error"
        viewModel.importOPML(from: Data())

        #expect(viewModel.importExportErrorMessage == nil)
        #expect(viewModel.opmlImportResult?.addedCount == 1)
    }

    @Test("importOPML populates siteURL on new feed from OPML entry htmlUrl")
    @MainActor
    func importOPMLPopulatesSiteURL() {
        let mockPersistence = MockFeedPersistenceService()
        let mockOPML = MockOPMLService()
        let siteURL = URL(string: "https://example.com")!
        mockOPML.entriesToReturn = [
            OPMLFeedEntry(
                title: "Example Feed",
                feedURL: URL(string: "https://example.com/feed")!,
                siteURL: siteURL,
                description: ""
            ),
        ]

        let viewModel = Self.makeViewModel(persistence: mockPersistence, opmlService: mockOPML)
        viewModel.importOPML(from: Data())

        #expect(viewModel.feeds.count == 1)
        #expect(viewModel.feeds[0].siteURL == siteURL)
    }

    @Test("importOPML leaves siteURL nil when OPML entry has no htmlUrl")
    @MainActor
    func importOPMLLeavesSiteURLNilWhenAbsent() {
        let mockPersistence = MockFeedPersistenceService()
        let mockOPML = MockOPMLService()
        mockOPML.entriesToReturn = [
            OPMLFeedEntry(
                title: "No Site Feed",
                feedURL: URL(string: "https://example.com/feed")!,
                siteURL: nil,
                description: ""
            ),
        ]

        let viewModel = Self.makeViewModel(persistence: mockPersistence, opmlService: mockOPML)
        viewModel.importOPML(from: Data())

        #expect(viewModel.feeds.count == 1)
        #expect(viewModel.feeds[0].siteURL == nil)
    }

    @Test("exportOPML passes siteURL through toSubscribedFeed conversion")
    @MainActor
    func exportOPMLPassesSiteURL() {
        let siteURL = URL(string: "https://example.com")!
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [
            TestFixtures.makePersistentFeed(
                feedURL: URL(string: "https://example.com/feed")!,
                siteURL: siteURL
            ),
        ]
        let mockOPML = MockOPMLService()
        mockOPML.dataToReturn = Data("opml-output".utf8)

        let viewModel = Self.makeViewModel(persistence: mockPersistence, opmlService: mockOPML)
        viewModel.loadFeeds()
        viewModel.exportOPML()

        let generatedFeed = mockOPML.lastGeneratedGroupedFeeds?.first?.feed
        #expect(generatedFeed?.siteURL == siteURL)
    }

    @Test("importOPML from URL sets importExportErrorMessage on file read failure")
    @MainActor
    func importOPMLFromURLSetsImportExportErrorOnReadFailure() {
        let mockPersistence = MockFeedPersistenceService()
        let mockOPML = MockOPMLService()
        let nonexistentURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("nonexistent-\(UUID().uuidString).opml")

        let viewModel = Self.makeViewModel(persistence: mockPersistence, opmlService: mockOPML)
        viewModel.importOPML(from: nonexistentURL)

        #expect(viewModel.importExportErrorMessage == "Unable to read the selected file.")
        #expect(viewModel.errorMessage == nil)
    }

    @Test("importOPMLAndRefresh from URL sets importExportErrorMessage on file read failure")
    @MainActor
    func importOPMLAndRefreshFromURLSetsImportExportErrorOnReadFailure() async {
        let mockPersistence = MockFeedPersistenceService()
        let mockOPML = MockOPMLService()
        let nonexistentURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("nonexistent-\(UUID().uuidString).opml")

        let viewModel = Self.makeViewModel(persistence: mockPersistence, opmlService: mockOPML)
        await viewModel.importOPMLAndRefresh(from: nonexistentURL)

        #expect(viewModel.importExportErrorMessage == "Unable to read the selected file.")
        #expect(viewModel.errorMessage == nil)
    }

    @Test("exportOPML clears stale importExportErrorMessage before processing")
    @MainActor
    func exportOPMLClearsStaleError() {
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [TestFixtures.makePersistentFeed()]
        let mockOPML = MockOPMLService()
        mockOPML.dataToReturn = Data("opml-content".utf8)

        let viewModel = Self.makeViewModel(persistence: mockPersistence, opmlService: mockOPML)
        viewModel.loadFeeds()
        // Simulate stale error from a previous operation
        viewModel.importExportErrorMessage = "Previous error"
        viewModel.exportOPML()

        #expect(viewModel.importExportErrorMessage == nil)
        #expect(viewModel.opmlExportURL != nil)
    }

    // MARK: - OPML Import with Groups

    @Test("importOPML creates groups from OPML categories")
    @MainActor
    func importOPMLCreatesGroups() {
        let mockPersistence = MockFeedPersistenceService()
        let mockOPML = MockOPMLService()
        mockOPML.entriesToReturn = [
            OPMLFeedEntry(title: "Tech Feed", feedURL: URL(string: "https://tech.com/feed")!, siteURL: nil, description: "", groupName: "Tech"),
            OPMLFeedEntry(title: "News Feed", feedURL: URL(string: "https://news.com/feed")!, siteURL: nil, description: "", groupName: "News"),
        ]

        let viewModel = Self.makeViewModel(persistence: mockPersistence, opmlService: mockOPML)
        viewModel.importOPML(from: Data())

        #expect(viewModel.opmlImportResult?.addedCount == 2)
        #expect(viewModel.opmlImportResult?.groupsCreatedCount == 2)
        #expect(viewModel.opmlImportResult?.groupsReusedCount == 0)

        // Verify groups were created in persistence.
        #expect(mockPersistence.groups.count == 2)
        let groupNames = Set(mockPersistence.groups.map(\.name))
        #expect(groupNames == ["Tech", "News"])

        // Verify feeds were assigned to their groups.
        let techGroup = mockPersistence.groups.first { $0.name == "Tech" }!
        let techFeeds = mockPersistence.memberships.filter { $0.group?.id == techGroup.id }.compactMap(\.feed)
        #expect(techFeeds.count == 1)
        #expect(techFeeds[0].feedURL == URL(string: "https://tech.com/feed"))
    }

    @Test("importOPML reuses existing groups with matching names")
    @MainActor
    func importOPMLReusesExistingGroups() {
        let mockPersistence = MockFeedPersistenceService()
        let existingGroup = PersistentFeedGroup(name: "Tech", sortOrder: 0)
        mockPersistence.groups = [existingGroup]

        let mockOPML = MockOPMLService()
        mockOPML.entriesToReturn = [
            OPMLFeedEntry(title: "Tech Feed", feedURL: URL(string: "https://tech.com/feed")!, siteURL: nil, description: "", groupName: "Tech"),
        ]

        let viewModel = Self.makeViewModel(persistence: mockPersistence, opmlService: mockOPML)
        viewModel.importOPML(from: Data())

        #expect(viewModel.opmlImportResult?.addedCount == 1)
        #expect(viewModel.opmlImportResult?.groupsCreatedCount == 0)
        #expect(viewModel.opmlImportResult?.groupsReusedCount == 1)

        // No new group should have been created.
        #expect(mockPersistence.groups.count == 1)
        #expect(mockPersistence.groups[0].id == existingGroup.id)
    }

    @Test("importOPML assigns duplicate feed to group from OPML category")
    @MainActor
    func importOPMLAssignsDuplicateFeedToGroup() {
        let existingFeed = TestFixtures.makePersistentFeed(
            title: "Existing Feed",
            feedURL: URL(string: "https://existing.com/feed")!
        )
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [existingFeed]

        let mockOPML = MockOPMLService()
        mockOPML.entriesToReturn = [
            OPMLFeedEntry(title: "Existing Feed", feedURL: URL(string: "https://existing.com/feed")!, siteURL: nil, description: "", groupName: "My Group"),
        ]

        let viewModel = Self.makeViewModel(persistence: mockPersistence, opmlService: mockOPML)
        viewModel.importOPML(from: Data())

        // Feed was skipped (already exists) but group was created and feed assigned.
        #expect(viewModel.opmlImportResult?.addedCount == 0)
        #expect(viewModel.opmlImportResult?.skippedCount == 1)
        #expect(viewModel.opmlImportResult?.groupsCreatedCount == 1)

        // Verify the existing feed was assigned to the new group.
        #expect(mockPersistence.groups.count == 1)
        #expect(mockPersistence.memberships.count == 1)
        #expect(mockPersistence.memberships[0].feed?.id == existingFeed.id)
    }

    @Test("importOPML handles entries without groups correctly")
    @MainActor
    func importOPMLHandlesUngroupedEntries() {
        let mockPersistence = MockFeedPersistenceService()
        let mockOPML = MockOPMLService()
        mockOPML.entriesToReturn = [
            OPMLFeedEntry(title: "Grouped", feedURL: URL(string: "https://grouped.com/feed")!, siteURL: nil, description: "", groupName: "Tech"),
            OPMLFeedEntry(title: "Ungrouped", feedURL: URL(string: "https://ungrouped.com/feed")!, siteURL: nil, description: "", groupName: nil),
        ]

        let viewModel = Self.makeViewModel(persistence: mockPersistence, opmlService: mockOPML)
        viewModel.importOPML(from: Data())

        #expect(viewModel.opmlImportResult?.addedCount == 2)
        #expect(viewModel.opmlImportResult?.groupsCreatedCount == 1)

        // Only the grouped feed should have a membership.
        #expect(mockPersistence.memberships.count == 1)
        #expect(mockPersistence.memberships[0].feed?.feedURL == URL(string: "https://grouped.com/feed"))
    }

    @Test("importOPML assigns feed to multiple groups when duplicated in OPML")
    @MainActor
    func importOPMLMultiGroupAssignment() {
        let mockPersistence = MockFeedPersistenceService()
        let mockOPML = MockOPMLService()
        mockOPML.entriesToReturn = [
            OPMLFeedEntry(title: "Multi Feed", feedURL: URL(string: "https://multi.com/feed")!, siteURL: nil, description: "", groupName: "Tech"),
            OPMLFeedEntry(title: "Multi Feed", feedURL: URL(string: "https://multi.com/feed")!, siteURL: nil, description: "", groupName: "Favorites"),
        ]

        let viewModel = Self.makeViewModel(persistence: mockPersistence, opmlService: mockOPML)
        viewModel.importOPML(from: Data())

        // Feed added once; the second appearance is standard multi-group OPML structure,
        // not a duplicate — skippedCount must be 0.
        #expect(viewModel.opmlImportResult?.addedCount == 1)
        #expect(viewModel.opmlImportResult?.skippedCount == 0)
        #expect(viewModel.opmlImportResult?.groupsCreatedCount == 2)

        // Feed should be in both groups.
        #expect(mockPersistence.memberships.count == 2)
        let groupNames = Set(mockPersistence.memberships.compactMap { $0.group?.name })
        #expect(groupNames == ["Tech", "Favorites"])
    }

    @Test("importOPML does not count multi-group feed as duplicate — blank-slate import")
    @MainActor
    func importOPMLMultiGroupBlankSlateNoDuplicate() {
        // Reproduces the exact scenario from the issue: one new feed listed under
        // two groups in OPML, imported onto a blank subscription list. The import
        // summary must show 1 added, 0 skipped, 2 new groups — not the previously
        // misleading "1 new feed added, 1 duplicate skipped, 2 new groups created".
        let mockPersistence = MockFeedPersistenceService()
        let mockOPML = MockOPMLService()
        mockOPML.entriesToReturn = [
            TestFixtures.makeOPMLFeedEntry(
                title: "My Feed",
                feedURL: URL(string: "https://example.com/feed")!,
                groupName: "Tech"
            ),
            TestFixtures.makeOPMLFeedEntry(
                title: "My Feed",
                feedURL: URL(string: "https://example.com/feed")!,
                groupName: "Favorites"
            ),
        ]

        let viewModel = Self.makeViewModel(persistence: mockPersistence, opmlService: mockOPML)
        viewModel.importOPML(from: Data())

        #expect(viewModel.opmlImportResult?.addedCount == 1)
        #expect(viewModel.opmlImportResult?.skippedCount == 0)
        #expect(viewModel.opmlImportResult?.groupsCreatedCount == 2)
        // Feed must be assigned to both groups.
        #expect(mockPersistence.memberships.count == 2)
    }

    @Test("importOPML counts pre-existing feed as skipped exactly once when it appears under two groups")
    @MainActor
    func importOPMLPreExistingFeedInTwoGroupsCountsOnce() {
        // A feed that is already subscribed before import and appears under two
        // groups in the OPML file must count as exactly 1 skipped — not 2.
        let existingFeed = TestFixtures.makePersistentFeed(
            title: "Pre-existing Feed",
            feedURL: URL(string: "https://existing.com/feed")!
        )
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [existingFeed]

        let mockOPML = MockOPMLService()
        mockOPML.entriesToReturn = [
            TestFixtures.makeOPMLFeedEntry(
                title: "Pre-existing Feed",
                feedURL: URL(string: "https://existing.com/feed")!,
                groupName: "Group A"
            ),
            TestFixtures.makeOPMLFeedEntry(
                title: "Pre-existing Feed",
                feedURL: URL(string: "https://existing.com/feed")!,
                groupName: "Group B"
            ),
        ]

        let viewModel = Self.makeViewModel(persistence: mockPersistence, opmlService: mockOPML)
        viewModel.loadFeeds()
        viewModel.importOPML(from: Data())

        // Pre-existing feed must be counted as skipped exactly once, even though
        // it appears under two groups in the OPML file.
        #expect(viewModel.opmlImportResult?.addedCount == 0)
        #expect(viewModel.opmlImportResult?.skippedCount == 1)
        // Both group assignments must still proceed even though the feed is skipped.
        #expect(viewModel.opmlImportResult?.groupsCreatedCount == 2)
        #expect(mockPersistence.memberships.count == 2)
    }

    @Test("importOPML continues past group creation failure and still adds feed")
    @MainActor
    func importOPMLGroupCreationFailure() {
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.addGroupError = NSError(domain: "MockPersistence", code: 1)
        let mockOPML = MockOPMLService()
        mockOPML.entriesToReturn = [
            OPMLFeedEntry(title: "Feed A", feedURL: URL(string: "https://a.com/feed")!, siteURL: nil, description: "", groupName: "Tech"),
        ]

        let viewModel = Self.makeViewModel(persistence: mockPersistence, opmlService: mockOPML)
        viewModel.importOPML(from: Data())

        // Feed should be added even though group creation failed.
        #expect(viewModel.opmlImportResult?.addedCount == 1)
        #expect(viewModel.opmlImportResult?.failedCount == 0)
        #expect(viewModel.opmlImportResult?.groupsFailedCount == 1)
        #expect(mockPersistence.groups.isEmpty)
        #expect(mockPersistence.memberships.isEmpty)
    }

    @Test("importOPML continues past group membership failure")
    @MainActor
    func importOPMLGroupMembershipFailure() {
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.addFeedToGroupError = NSError(domain: "MockPersistence", code: 1)
        let mockOPML = MockOPMLService()
        mockOPML.entriesToReturn = [
            OPMLFeedEntry(title: "Feed A", feedURL: URL(string: "https://a.com/feed")!, siteURL: nil, description: "", groupName: "Tech"),
        ]

        let viewModel = Self.makeViewModel(persistence: mockPersistence, opmlService: mockOPML)
        viewModel.importOPML(from: Data())

        // Feed and group should be created, but membership assignment fails.
        #expect(viewModel.opmlImportResult?.addedCount == 1)
        #expect(viewModel.opmlImportResult?.failedCount == 0)
        #expect(viewModel.opmlImportResult?.groupsFailedCount == 1)
        #expect(mockPersistence.groups.count == 1)
        #expect(mockPersistence.memberships.isEmpty)
    }

    @Test("importOPML reports distinct error for allGroups pre-loop failure")
    @MainActor
    func importOPMLAllGroupsPreLoopFailure() {
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.groupError = NSError(domain: "MockPersistence", code: 1)
        let mockOPML = MockOPMLService()
        mockOPML.entriesToReturn = [
            TestFixtures.makeOPMLFeedEntry(title: "Feed A", feedURL: URL(string: "https://a.com/feed")!),
        ]

        let viewModel = Self.makeViewModel(persistence: mockPersistence, opmlService: mockOPML)
        viewModel.importOPML(from: Data())

        #expect(viewModel.importExportErrorMessage == "Unable to load existing groups. Import aborted.")
        #expect(viewModel.opmlImportResult == nil)
    }

    @Test("importOPML reports distinct error for allFeeds pre-loop failure")
    @MainActor
    func importOPMLAllFeedsPreLoopFailure() {
        let mockPersistence = MockFeedPersistenceService()
        // Make only the first allFeeds() call fail (the pre-loop cache lookup),
        // while the subsequent loadFeeds() call succeeds.
        mockPersistence.allFeedsFailureCount = 1
        let mockOPML = MockOPMLService()
        mockOPML.entriesToReturn = [
            TestFixtures.makeOPMLFeedEntry(title: "Feed A", feedURL: URL(string: "https://a.com/feed")!),
        ]

        let viewModel = Self.makeViewModel(persistence: mockPersistence, opmlService: mockOPML)
        viewModel.importOPML(from: Data())

        #expect(viewModel.importExportErrorMessage == "Unable to load existing feeds. Import aborted.")
        #expect(viewModel.opmlImportResult == nil)
    }

    @Test("importOPML with all feeds failing reports zero added")
    @MainActor
    func importOPMLAllFeedsFail() {
        let mockPersistence = MockFeedPersistenceService()
        // All addFeed calls fail (after 0 successful)
        mockPersistence.addFeedFailureAfterCount = 0
        let mockOPML = MockOPMLService()
        mockOPML.entriesToReturn = [
            TestFixtures.makeOPMLFeedEntry(title: "Feed A", feedURL: URL(string: "https://a.com/feed")!),
            TestFixtures.makeOPMLFeedEntry(title: "Feed B", feedURL: URL(string: "https://b.com/feed")!),
        ]

        let viewModel = Self.makeViewModel(persistence: mockPersistence, opmlService: mockOPML)
        viewModel.importOPML(from: Data())

        #expect(viewModel.opmlImportResult?.addedCount == 0)
        #expect(viewModel.opmlImportResult?.failedCount == 2)
        #expect(viewModel.importExportErrorMessage == nil)
    }

    // MARK: - OPML Export with Groups

    @Test("exportOPML uses grouped generation with group names from persistence")
    @MainActor
    func exportOPMLIncludesGroups() {
        let feed1 = TestFixtures.makePersistentFeed(title: "Feed A", feedURL: URL(string: "https://a.com/feed")!)
        let feed2 = TestFixtures.makePersistentFeed(title: "Feed B", feedURL: URL(string: "https://b.com/feed")!)
        let group = PersistentFeedGroup(name: "Tech", sortOrder: 0)

        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed1, feed2]
        mockPersistence.groups = [group]
        // Only feed1 is in the group.
        mockPersistence.memberships = [PersistentFeedGroupMembership(feed: feed1, group: group)]

        let mockOPML = MockOPMLService()
        mockOPML.dataToReturn = Data("opml-content".utf8)

        let viewModel = Self.makeViewModel(persistence: mockPersistence, opmlService: mockOPML)
        viewModel.loadFeeds()
        viewModel.exportOPML()

        #expect(viewModel.opmlExportURL != nil)

        // Verify the mock received grouped feeds with correct group names.
        let groupedFeeds = mockOPML.lastGeneratedGroupedFeeds
        #expect(groupedFeeds != nil)
        #expect(groupedFeeds?.count == 2)

        let feedAGrouped = groupedFeeds?.first { $0.feed.url == URL(string: "https://a.com/feed") }
        let feedBGrouped = groupedFeeds?.first { $0.feed.url == URL(string: "https://b.com/feed") }
        #expect(feedAGrouped?.groupNames == ["Tech"])
        #expect(feedBGrouped?.groupNames == [])
    }

    @Test("exportOPML sets error when allGroupMemberships throws")
    @MainActor
    func exportOPMLGroupMembershipsError() {
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [TestFixtures.makePersistentFeed()]
        mockPersistence.groupError = NSError(domain: "test", code: 1)

        let mockOPML = MockOPMLService()
        mockOPML.dataToReturn = Data("opml-content".utf8)

        let viewModel = Self.makeViewModel(persistence: mockPersistence, opmlService: mockOPML)
        viewModel.loadFeeds()
        viewModel.exportOPML()

        #expect(viewModel.opmlExportURL == nil)
        #expect(viewModel.importExportErrorMessage == "Unable to export feeds.")
        #expect(viewModel.errorMessage == nil)
    }

    // MARK: - Refresh Delegation — outcome → errorMessage translation
    //
    // These tests defend the `refreshAllFeeds()` switch that maps a
    // `FeedRefreshService.Outcome` into the viewmodel's `errorMessage`. The
    // underlying refresh pipeline is covered by FeedRefreshServiceTests; the
    // tests here pin:
    //   - exact user-facing strings (string format + interpolation)
    //   - priority ordering (save > failureCount > retention)
    //   - .setupFailed → distinct "load your feeds" message
    //   - .cancelled → no user-visible error (silent)
    // A refactor that reorders the switch arms, swaps loadFeeds() before or
    // after the outcome translation, or changes the exact strings will fail
    // these tests.

    @Test("refreshAllFeeds clears errorMessage on happy-path outcome")
    @MainActor
    func refreshHappyPathClearsErrorMessage() async {
        let url = URL(string: "https://example.com/feed")!
        let feed = TestFixtures.makePersistentFeed(feedURL: url)
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]
        let mockFetching = MockFeedFetchingService()
        mockFetching.feedsByURL = [url: TestFixtures.makeFeed()]

        let mockIconService = MockFeedIconService()
        let refreshService = Self.makeRefreshService(
            persistence: mockPersistence,
            feedFetching: mockFetching,
            feedIconService: mockIconService
        )
        let viewModel = FeedListViewModel(
            persistence: mockPersistence,
            refreshService: refreshService,
            feedIconService: mockIconService
        )
        viewModel.errorMessage = "stale error"
        await viewModel.refreshAllFeeds()

        #expect(viewModel.errorMessage == nil)
    }

    @Test("refreshAllFeeds surfaces exact fetch-failure message format")
    @MainActor
    func refreshFetchFailureExactMessage() async {
        let url = URL(string: "https://fail.com/feed")!
        let feed = TestFixtures.makePersistentFeed(feedURL: url)
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]
        let mockFetching = MockFeedFetchingService()
        mockFetching.errorsByURL = [url: FeedFetchingError.invalidResponse(statusCode: 500)]

        let mockIconService = MockFeedIconService()
        let refreshService = Self.makeRefreshService(
            persistence: mockPersistence,
            feedFetching: mockFetching,
            feedIconService: mockIconService
        )
        let viewModel = FeedListViewModel(
            persistence: mockPersistence,
            refreshService: refreshService,
            feedIconService: mockIconService
        )
        await viewModel.refreshAllFeeds()

        #expect(viewModel.errorMessage == "1 of 1 feed(s) could not be updated.")
    }

    @Test("refreshAllFeeds prioritizes save failure over fetch failure")
    @MainActor
    func refreshSaveFailureShadowsFetchFailure() async {
        // A refresh with BOTH a fetch failure AND a save failure should
        // surface the save message. Documents a non-obvious priority order
        // in the outcome-translation switch — a future refactor that flips
        // the branch order will fail this test.
        let url = URL(string: "https://fail.com/feed")!
        let feed = TestFixtures.makePersistentFeed(feedURL: url)
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]
        mockPersistence.saveError = NSError(domain: "test", code: 1)
        let mockFetching = MockFeedFetchingService()
        mockFetching.errorsByURL = [url: FeedFetchingError.invalidResponse(statusCode: 500)]

        let mockIconService = MockFeedIconService()
        let refreshService = Self.makeRefreshService(
            persistence: mockPersistence,
            feedFetching: mockFetching,
            feedIconService: mockIconService
        )
        let viewModel = FeedListViewModel(
            persistence: mockPersistence,
            refreshService: refreshService,
            feedIconService: mockIconService
        )
        await viewModel.refreshAllFeeds()

        #expect(viewModel.errorMessage == "Unable to save updated feeds.")
    }

    @Test("refreshAllFeeds surfaces retention failure message when no higher-priority failure exists")
    @MainActor
    func refreshRetentionFailureExactMessage() async {
        let url = URL(string: "https://example.com/feed")!
        let feed = TestFixtures.makePersistentFeed(feedURL: url)
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]
        let mockFetching = MockFeedFetchingService()
        mockFetching.feedsByURL = [url: TestFixtures.makeFeed()]
        let mockRetention = MockArticleRetentionService()
        mockRetention.enforceError = NSError(domain: "test", code: 1)

        let mockIconService = MockFeedIconService()
        let refreshService = Self.makeRefreshService(
            persistence: mockPersistence,
            feedFetching: mockFetching,
            feedIconService: mockIconService,
            articleRetention: mockRetention
        )
        let viewModel = FeedListViewModel(
            persistence: mockPersistence,
            refreshService: refreshService,
            feedIconService: mockIconService
        )
        await viewModel.refreshAllFeeds()

        #expect(viewModel.errorMessage == "Article cleanup could not complete.")
    }

    @Test("refreshAllFeeds surfaces setupFailed with distinct 'load your feeds' message")
    @MainActor
    func refreshSetupFailedExactMessage() async {
        // persistence.allFeeds() throws on the FIRST call (triggering
        // .setupFailed) but succeeds on the second (so loadFeeds() in the
        // viewmodel's post-refresh reload does NOT set its own
        // "Unable to load your feeds." error). This isolates the assertion
        // to the `.setupFailed` switch arm — a refactor that silently
        // dropped the arm would leave errorMessage nil and fail this test,
        // which is exactly the regression we want to catch.
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.allFeedsFailureCount = 1  // fail once, then succeed

        let mockIconService = MockFeedIconService()
        let refreshService = Self.makeRefreshService(
            persistence: mockPersistence,
            feedIconService: mockIconService
        )
        let viewModel = FeedListViewModel(
            persistence: mockPersistence,
            refreshService: refreshService,
            feedIconService: mockIconService
        )
        await viewModel.refreshAllFeeds()

        #expect(viewModel.errorMessage == "Unable to load your feeds.")
    }

    @Test("refreshAllFeeds error message denominator excludes auto-skipped feeds")
    @MainActor
    func refreshFetchFailureMessageExcludesSkippedFeeds() async {
        // When 1 feed fails and 1 feed is auto-skipped, the error message must
        // report "1 of 1 feed(s) could not be updated." (attempted only),
        // not "1 of 2 feed(s) could not be updated." (total including skipped).
        // Documents the `attempted = totalFeeds - skippedCount` denominator fix
        // so a future refactor back to `totalFeeds` fails this test.
        let failingURL = URL(string: "https://failing.com/feed")!
        let failingFeed = TestFixtures.makePersistentFeed(title: "Failing", feedURL: failingURL)

        let streakStart = Date(timeIntervalSinceNow: -(FeedRefreshService.autoSkipThreshold + 3600))
        let skippedFeed = TestFixtures.makePersistentFeed(
            title: "Skipped",
            feedURL: URL(string: "https://dead.com/feed")!,
            lastFetchError: "HTTP 404",
            firstFetchErrorDate: streakStart
        )

        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [failingFeed, skippedFeed]
        let mockFetching = MockFeedFetchingService()
        mockFetching.errorsByURL = [failingURL: FeedFetchingError.invalidResponse(statusCode: 503)]

        let mockIconService = MockFeedIconService()
        let refreshService = Self.makeRefreshService(
            persistence: mockPersistence,
            feedFetching: mockFetching,
            feedIconService: mockIconService
        )
        let viewModel = FeedListViewModel(
            persistence: mockPersistence,
            refreshService: refreshService,
            feedIconService: mockIconService
        )
        await viewModel.refreshAllFeeds()

        // Only 1 feed was attempted (the skipped feed was never fetched).
        #expect(viewModel.errorMessage == "1 of 1 feed(s) could not be updated.")
    }

    @Test("refreshAllFeeds leaves errorMessage nil on cancellation")
    @MainActor
    func refreshCancelledDoesNotSurfaceError() async {
        // Cancellation (BG task expiration, view teardown) must not set a
        // user-visible error — the next refresh picks up where this one
        // left off. Tested by injecting a CancellationError into the fetch
        // task group.
        let url = URL(string: "https://example.com/feed")!
        let feed = TestFixtures.makePersistentFeed(feedURL: url)
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]
        let mockFetching = MockFeedFetchingService()
        mockFetching.errorsByURL = [url: CancellationError()]

        let mockIconService = MockFeedIconService()
        let refreshService = Self.makeRefreshService(
            persistence: mockPersistence,
            feedFetching: mockFetching,
            feedIconService: mockIconService
        )
        let viewModel = FeedListViewModel(
            persistence: mockPersistence,
            refreshService: refreshService,
            feedIconService: mockIconService
        )
        await viewModel.refreshAllFeeds()

        #expect(viewModel.errorMessage == nil)
    }

    // MARK: - OPML Parse Skip Count

    @Test("importOPML propagates parseSkippedCount from parse result into OPMLImportResult")
    @MainActor
    func importOPMLPropagatesParseSkippedCount() {
        let mockPersistence = MockFeedPersistenceService()
        let mockOPML = MockOPMLService()
        // Simulate the parser returning 2 valid entries and reporting 3 skipped
        mockOPML.entriesToReturn = [
            TestFixtures.makeOPMLFeedEntry(title: "Feed A", feedURL: URL(string: "https://a.com/feed")!),
            TestFixtures.makeOPMLFeedEntry(title: "Feed B", feedURL: URL(string: "https://b.com/feed")!),
        ]
        mockOPML.parseSkippedCountToReturn = 3

        let viewModel = Self.makeViewModel(persistence: mockPersistence, opmlService: mockOPML)
        viewModel.importOPML(from: Data())

        #expect(viewModel.opmlImportResult?.addedCount == 2)
        #expect(viewModel.opmlImportResult?.parseSkippedCount == 3)
    }

    @Test("importOPML result has zero parseSkippedCount when no entries were skipped")
    @MainActor
    func importOPMLParseSkippedCountIsZeroWhenNoneSkipped() {
        let mockPersistence = MockFeedPersistenceService()
        let mockOPML = MockOPMLService()
        mockOPML.entriesToReturn = [
            TestFixtures.makeOPMLFeedEntry(title: "Feed A", feedURL: URL(string: "https://a.com/feed")!),
        ]
        mockOPML.parseSkippedCountToReturn = 0

        let viewModel = Self.makeViewModel(persistence: mockPersistence, opmlService: mockOPML)
        viewModel.importOPML(from: Data())

        #expect(viewModel.opmlImportResult?.parseSkippedCount == 0)
    }

    // MARK: - OPML Import sortOrder

    @Test("importOPML assigns incrementing sortOrder starting after existing feeds")
    @MainActor
    func importOPMLAssignsNextSortOrder() {
        let mockPersistence = MockFeedPersistenceService()
        // Pre-populate with an existing feed at sortOrder 5
        mockPersistence.feeds = [
            TestFixtures.makePersistentFeed(
                title: "Existing",
                feedURL: URL(string: "https://existing.com/feed")!,
                sortOrder: 5
            )
        ]
        let mockOPML = MockOPMLService()
        mockOPML.entriesToReturn = [
            TestFixtures.makeOPMLFeedEntry(title: "Import A", feedURL: URL(string: "https://a.com/feed")!),
            TestFixtures.makeOPMLFeedEntry(title: "Import B", feedURL: URL(string: "https://b.com/feed")!),
        ]

        let viewModel = Self.makeViewModel(persistence: mockPersistence, opmlService: mockOPML)
        viewModel.importOPML(from: Data())

        #expect(viewModel.opmlImportResult?.addedCount == 2)
        let importA = mockPersistence.feeds.first { $0.title == "Import A" }
        let importB = mockPersistence.feeds.first { $0.title == "Import B" }
        #expect(importA?.sortOrder == 6)
        #expect(importB?.sortOrder == 7)
    }

}
