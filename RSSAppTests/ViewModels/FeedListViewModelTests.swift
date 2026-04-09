import Testing
import Foundation
import SwiftData
@testable import RSSApp

@Suite("FeedListViewModel Tests")
struct FeedListViewModelTests {

    /// Builds a view model wired to a real `FeedRefreshService` over the
    /// supplied mock persistence. Tests that exercise refresh-specific
    /// behavior (icon cleanup, delegation-to-error-message translation)
    /// construct the service explicitly so they can inject mocks into it;
    /// tests that only touch load/remove/OPML/unread paths rely on this
    /// helper and ignore the service's defaults.
    @MainActor
    private static func makeViewModel(
        persistence: FeedPersisting,
        opmlService: OPMLServing = OPMLService()
    ) -> FeedListViewModel {
        FeedListViewModel(
            persistence: persistence,
            refreshService: FeedRefreshService(persistence: persistence),
            opmlService: opmlService
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

        #expect(viewModel.feeds.count == 2)
        #expect(viewModel.opmlImportResult?.addedCount == 2)
        #expect(viewModel.opmlImportResult?.skippedCount == 1)
    }

    @Test("importOPML aborts early on persistence failure mid-import")
    @MainActor
    func importOPMLPersistenceFailureMidImport() {
        let mockPersistence = MockFeedPersistenceService()
        // First addFeed succeeds, second fails
        mockPersistence.addFeedFailureAfterCount = 1
        let mockOPML = MockOPMLService()
        mockOPML.entriesToReturn = [
            TestFixtures.makeOPMLFeedEntry(title: "Feed A", feedURL: URL(string: "https://a.com/feed")!),
            TestFixtures.makeOPMLFeedEntry(title: "Feed B", feedURL: URL(string: "https://b.com/feed")!),
            TestFixtures.makeOPMLFeedEntry(title: "Feed C", feedURL: URL(string: "https://c.com/feed")!),
        ]

        let viewModel = Self.makeViewModel(persistence: mockPersistence, opmlService: mockOPML)
        viewModel.importOPML(from: Data())

        // Only the first feed should have been added — import aborts on second
        #expect(viewModel.feeds.count == 1)
        #expect(viewModel.opmlImportResult == nil)
        #expect(viewModel.importExportErrorMessage != nil)
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

        let refreshService = FeedRefreshService(
            persistence: mockPersistence,
            feedFetching: mockFetching
        )
        let viewModel = FeedListViewModel(
            persistence: mockPersistence,
            refreshService: refreshService
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

        let refreshService = FeedRefreshService(
            persistence: mockPersistence,
            feedFetching: mockFetching
        )
        let viewModel = FeedListViewModel(
            persistence: mockPersistence,
            refreshService: refreshService
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

        let refreshService = FeedRefreshService(
            persistence: mockPersistence,
            feedFetching: mockFetching
        )
        let viewModel = FeedListViewModel(
            persistence: mockPersistence,
            refreshService: refreshService
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

        let refreshService = FeedRefreshService(
            persistence: mockPersistence,
            feedFetching: mockFetching,
            articleRetention: mockRetention
        )
        let viewModel = FeedListViewModel(
            persistence: mockPersistence,
            refreshService: refreshService
        )
        await viewModel.refreshAllFeeds()

        #expect(viewModel.errorMessage == "Article cleanup could not complete.")
    }

    @Test("refreshAllFeeds surfaces setupFailed with distinct 'load your feeds' message")
    @MainActor
    func refreshSetupFailedExactMessage() async {
        // persistence.allFeeds() throws → FeedRefreshService returns .setupFailed.
        // The viewmodel must translate this to "Unable to load your feeds."
        // (NOT "Unable to save updated feeds.", which is the save-failure path).
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.errorToThrow = NSError(domain: "test", code: 1)

        let refreshService = FeedRefreshService(persistence: mockPersistence)
        let viewModel = FeedListViewModel(
            persistence: mockPersistence,
            refreshService: refreshService
        )
        await viewModel.refreshAllFeeds()

        #expect(viewModel.errorMessage == "Unable to load your feeds.")
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

        let refreshService = FeedRefreshService(
            persistence: mockPersistence,
            feedFetching: mockFetching
        )
        let viewModel = FeedListViewModel(
            persistence: mockPersistence,
            refreshService: refreshService
        )
        await viewModel.refreshAllFeeds()

        #expect(viewModel.errorMessage == nil)
    }

}
