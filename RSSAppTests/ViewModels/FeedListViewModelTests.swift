import Testing
import Foundation
import SwiftData
@testable import RSSApp

@Suite("FeedListViewModel Tests")
struct FeedListViewModelTests {

    @Test("loadFeeds populates feeds from persistence")
    @MainActor
    func loadFeedsFromStorage() {
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [
            TestFixtures.makePersistentFeed(title: "Feed A"),
            TestFixtures.makePersistentFeed(title: "Feed B"),
        ]

        let viewModel = FeedListViewModel(persistence: mockPersistence)
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
        let viewModel = FeedListViewModel(persistence: mockPersistence)
        viewModel.loadFeeds()

        #expect(viewModel.feeds.isEmpty)
    }

    @Test("loadFeeds sets errorMessage on persistence failure")
    @MainActor
    func loadFeedsError() {
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.errorToThrow = NSError(domain: "test", code: 1)

        let viewModel = FeedListViewModel(persistence: mockPersistence)
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

        let viewModel = FeedListViewModel(persistence: mockPersistence)
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

        let viewModel = FeedListViewModel(persistence: mockPersistence)
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

        let viewModel = FeedListViewModel(persistence: mockPersistence)
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

        let viewModel = FeedListViewModel(persistence: mockPersistence)
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

        let viewModel = FeedListViewModel(
            persistence: mockPersistence,
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

        let viewModel = FeedListViewModel(
            persistence: mockPersistence,
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

        let viewModel = FeedListViewModel(persistence: mockPersistence)
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

        let viewModel = FeedListViewModel(persistence: mockPersistence)
        viewModel.loadFeeds()
        #expect(viewModel.unreadCount(for: feed) == 1)

        article.isRead = true
        viewModel.refreshUnreadCounts()
        #expect(viewModel.unreadCount(for: feed) == 0)
    }

    @Test("unreadCount returns zero for unknown feed")
    @MainActor
    func unreadCountReturnsZeroForUnknownFeed() {
        let mockPersistence = MockFeedPersistenceService()
        let viewModel = FeedListViewModel(persistence: mockPersistence)
        viewModel.loadFeeds()

        let unknownFeed = TestFixtures.makePersistentFeed(title: "Unknown")
        #expect(viewModel.unreadCount(for: unknownFeed) == 0)
    }

    @Test("refreshUnreadCounts defaults to zero on persistence error")
    @MainActor
    func refreshUnreadCountsDefaultsToZeroOnError() {
        let feed = TestFixtures.makePersistentFeed(title: "Feed A")
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]
        mockPersistence.articlesByFeedID = [
            feed.id: [TestFixtures.makePersistentArticle(articleID: "1", isRead: false)],
        ]

        let viewModel = FeedListViewModel(persistence: mockPersistence)
        viewModel.loadFeeds()
        #expect(viewModel.unreadCount(for: feed) == 1)

        mockPersistence.unreadCountError = NSError(domain: "test", code: 1)
        viewModel.refreshUnreadCounts()
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

        let viewModel = FeedListViewModel(persistence: mockPersistence)
        viewModel.loadFeeds()
        #expect(viewModel.unreadCount(for: feed1) == 1)
        #expect(viewModel.unreadCount(for: feed2) == 1)

        article.isRead = true
        viewModel.refreshUnreadCount(for: feed1)
        #expect(viewModel.unreadCount(for: feed1) == 0)
        #expect(viewModel.unreadCount(for: feed2) == 1)
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

        let viewModel = FeedListViewModel(persistence: mockPersistence)
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

        let viewModel = FeedListViewModel(persistence: mockPersistence, opmlService: mockOPML)
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

        let viewModel = FeedListViewModel(persistence: mockPersistence, opmlService: mockOPML)
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

        let viewModel = FeedListViewModel(persistence: mockPersistence, opmlService: mockOPML)
        viewModel.loadFeeds()
        viewModel.exportOPML()

        #expect(viewModel.opmlExportURL == nil)
        #expect(viewModel.importExportErrorMessage != nil)
    }

    // MARK: - Refresh

    @Test("refreshAllFeeds updates metadata from fetched feeds")
    @MainActor
    func refreshAllFeedsUpdatesMetadata() async {
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

        let viewModel = FeedListViewModel(persistence: mockPersistence, feedFetching: mockFetching, feedIconService: MockFeedIconService())
        viewModel.loadFeeds()
        await viewModel.refreshAllFeeds()

        #expect(viewModel.feeds[0].title == "New One")
        #expect(viewModel.feeds[0].feedDescription == "Desc One")
        #expect(viewModel.feeds[1].title == "New Two")
        #expect(viewModel.feeds[1].feedDescription == "Desc Two")
        #expect(viewModel.errorMessage == nil)
    }

    @Test("refreshAllFeeds preserves feed when fetch fails")
    @MainActor
    func refreshAllFeedsPreservesOnFailure() async {
        let url = URL(string: "https://fail.com/feed")!
        let feed = TestFixtures.makePersistentFeed(title: "Original", feedURL: url, feedDescription: "Original Desc")

        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]
        let mockFetching = MockFeedFetchingService()
        mockFetching.errorsByURL = [url: FeedFetchingError.invalidResponse(statusCode: 500)]

        let viewModel = FeedListViewModel(persistence: mockPersistence, feedFetching: mockFetching, feedIconService: MockFeedIconService())
        viewModel.loadFeeds()
        await viewModel.refreshAllFeeds()

        #expect(viewModel.errorMessage == "1 of 1 feed(s) could not be updated.")
        #expect(viewModel.importExportErrorMessage == nil)
    }

    @Test("refreshAllFeeds handles partial failures")
    @MainActor
    func refreshAllFeedsPartialFailure() async {
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

        let viewModel = FeedListViewModel(persistence: mockPersistence, feedFetching: mockFetching, feedIconService: MockFeedIconService())
        viewModel.loadFeeds()
        await viewModel.refreshAllFeeds()

        #expect(viewModel.feeds[0].title == "Updated")
        #expect(viewModel.feeds[0].feedDescription == "New Desc")
        #expect(viewModel.errorMessage == "1 of 2 feed(s) could not be updated.")
    }

    @Test("refreshAllFeeds is no-op when feeds is empty")
    @MainActor
    func refreshAllFeedsEmptyNoOp() async {
        let mockPersistence = MockFeedPersistenceService()
        let mockFetching = MockFeedFetchingService()

        let viewModel = FeedListViewModel(persistence: mockPersistence, feedFetching: mockFetching, feedIconService: MockFeedIconService())
        viewModel.loadFeeds()
        await viewModel.refreshAllFeeds()

        #expect(viewModel.feeds.isEmpty)
        #expect(viewModel.isRefreshing == false)
        #expect(viewModel.errorMessage == nil)
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

        let viewModel = FeedListViewModel(persistence: mockPersistence, feedFetching: mockFetching, feedIconService: MockFeedIconService())
        viewModel.loadFeeds()
        await viewModel.refreshAllFeeds()

        #expect(viewModel.isRefreshing == false)
    }

    @Test("refreshAllFeeds sets error state on failed feeds")
    @MainActor
    func refreshAllFeedsSetsErrorState() async {
        let url = URL(string: "https://fail.com/feed")!
        let feed = TestFixtures.makePersistentFeed(title: "Broken", feedURL: url)

        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]
        let mockFetching = MockFeedFetchingService()
        mockFetching.errorsByURL = [url: FeedFetchingError.invalidResponse(statusCode: 404)]

        let viewModel = FeedListViewModel(persistence: mockPersistence, feedFetching: mockFetching, feedIconService: MockFeedIconService())
        viewModel.loadFeeds()
        await viewModel.refreshAllFeeds()

        #expect(viewModel.feeds[0].lastFetchError == "HTTP 404")
        #expect(viewModel.feeds[0].lastFetchErrorDate != nil)
    }

    @Test("refreshAllFeeds clears error state on successful feeds")
    @MainActor
    func refreshAllFeedsClearsErrorState() async {
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

        let viewModel = FeedListViewModel(persistence: mockPersistence, feedFetching: mockFetching, feedIconService: MockFeedIconService())
        viewModel.loadFeeds()
        await viewModel.refreshAllFeeds()

        #expect(viewModel.feeds[0].lastFetchError == nil)
        #expect(viewModel.feeds[0].lastFetchErrorDate == nil)
        #expect(viewModel.feeds[0].title == "Fixed")
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

        let viewModel = FeedListViewModel(persistence: mockPersistence, opmlService: mockOPML)
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

        let viewModel = FeedListViewModel(persistence: mockPersistence, opmlService: mockOPML)
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

        let viewModel = FeedListViewModel(persistence: mockPersistence, opmlService: mockOPML)
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

        let viewModel = FeedListViewModel(persistence: mockPersistence, opmlService: mockOPML)
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

        let viewModel = FeedListViewModel(
            persistence: mockPersistence,
            opmlService: mockOPML,
            feedFetching: mockFetching,
            feedIconService: MockFeedIconService()
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

        let viewModel = FeedListViewModel(persistence: mockPersistence, opmlService: mockOPML)
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

        let viewModel = FeedListViewModel(persistence: mockPersistence, opmlService: mockOPML)
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

        let viewModel = FeedListViewModel(persistence: mockPersistence, opmlService: mockOPML)
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

        let viewModel = FeedListViewModel(persistence: mockPersistence, opmlService: mockOPML)
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

        let viewModel = FeedListViewModel(persistence: mockPersistence)
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

        let viewModel = FeedListViewModel(persistence: mockPersistence)
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

        let viewModel = FeedListViewModel(persistence: mockPersistence, opmlService: mockOPML)
        // Simulate stale error from a previous operation
        viewModel.importExportErrorMessage = "Previous error"
        viewModel.importOPML(from: Data())

        #expect(viewModel.importExportErrorMessage == nil)
        #expect(viewModel.opmlImportResult?.addedCount == 1)
    }

    @Test("exportOPML clears stale importExportErrorMessage before processing")
    @MainActor
    func exportOPMLClearsStaleError() {
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [TestFixtures.makePersistentFeed()]
        let mockOPML = MockOPMLService()
        mockOPML.dataToReturn = Data("opml-content".utf8)

        let viewModel = FeedListViewModel(persistence: mockPersistence, opmlService: mockOPML)
        viewModel.loadFeeds()
        // Simulate stale error from a previous operation
        viewModel.importExportErrorMessage = "Previous error"
        viewModel.exportOPML()

        #expect(viewModel.importExportErrorMessage == nil)
        #expect(viewModel.opmlExportURL != nil)
    }

    // MARK: - Icon Resolution During Refresh

    @Test("refreshAllFeeds resolves icons for fetched feeds")
    @MainActor
    func refreshAllFeedsResolvesIcons() async {
        let url = URL(string: "https://example.com/feed")!
        let feed = TestFixtures.makePersistentFeed(feedURL: url)

        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]
        let mockFetching = MockFeedFetchingService()
        mockFetching.feedsByURL = [url: TestFixtures.makeFeed()]
        let mockIconService = MockFeedIconService()

        let viewModel = FeedListViewModel(
            persistence: mockPersistence,
            feedFetching: mockFetching,
            feedIconService: mockIconService
        )
        viewModel.loadFeeds()
        await viewModel.refreshAllFeeds()

        // Allow fire-and-forget icon resolution tasks to complete
        for _ in 0..<10 { await Task.yield() }

        #expect(mockIconService.resolveAndCacheCallCount == 1)
    }

    @Test("refreshAllFeeds skips icon resolution when icon already cached")
    @MainActor
    func refreshAllFeedsSkipsIconWhenCached() async {
        let url = URL(string: "https://example.com/feed")!
        let feed = TestFixtures.makePersistentFeed(feedURL: url)

        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]
        let mockFetching = MockFeedFetchingService()
        mockFetching.feedsByURL = [url: TestFixtures.makeFeed()]
        let mockIconService = MockFeedIconService()
        mockIconService.cachedFileURL = URL(filePath: "/tmp/cached-icon.png")

        let viewModel = FeedListViewModel(
            persistence: mockPersistence,
            feedFetching: mockFetching,
            feedIconService: mockIconService
        )
        viewModel.loadFeeds()
        await viewModel.refreshAllFeeds()

        // Allow fire-and-forget icon resolution tasks to complete
        for _ in 0..<10 { await Task.yield() }

        #expect(mockIconService.resolveAndCacheCallCount == 0)
    }

    // MARK: - 304 Not Modified

    @Test("refreshAllFeeds handles 304 Not Modified")
    @MainActor
    func refreshAllFeeds304NotModified() async {
        let url = URL(string: "https://example.com/feed")!
        let feed = TestFixtures.makePersistentFeed(
            title: "Existing",
            feedURL: url,
            lastFetchError: "HTTP 500",
            lastFetchErrorDate: Date()
        )

        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]
        let mockFetching = MockFeedFetchingService()
        mockFetching.shouldReturn304 = true

        let viewModel = FeedListViewModel(persistence: mockPersistence, feedFetching: mockFetching, feedIconService: MockFeedIconService())
        viewModel.loadFeeds()
        await viewModel.refreshAllFeeds()

        // Title should not change (304 means no new data)
        #expect(viewModel.feeds[0].title == "Existing")
        // Error state should be cleared
        #expect(viewModel.feeds[0].lastFetchError == nil)
        #expect(viewModel.errorMessage == nil)
    }
}
