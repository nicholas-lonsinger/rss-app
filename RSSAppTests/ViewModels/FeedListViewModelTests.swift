import Testing
import Foundation
@testable import RSSApp

@Suite("FeedListViewModel Tests")
struct FeedListViewModelTests {

    @Test("loadFeeds populates feeds from storage")
    @MainActor
    func loadFeedsFromStorage() {
        let mockStorage = MockFeedStorageService()
        mockStorage.feeds = [
            TestFixtures.makeSubscribedFeed(title: "Feed A"),
            TestFixtures.makeSubscribedFeed(title: "Feed B"),
        ]

        let viewModel = FeedListViewModel(feedStorage: mockStorage)
        viewModel.loadFeeds()

        #expect(viewModel.feeds.count == 2)
        #expect(viewModel.feeds[0].title == "Feed A")
        #expect(viewModel.feeds[1].title == "Feed B")
        #expect(viewModel.errorMessage == nil)
    }

    @Test("loadFeeds returns empty when storage is empty")
    @MainActor
    func loadFeedsEmpty() {
        let mockStorage = MockFeedStorageService()
        let viewModel = FeedListViewModel(feedStorage: mockStorage)
        viewModel.loadFeeds()

        #expect(viewModel.feeds.isEmpty)
    }

    @Test("loadFeeds sets errorMessage on storage failure")
    @MainActor
    func loadFeedsError() {
        let mockStorage = MockFeedStorageService()
        mockStorage.errorToThrow = NSError(domain: "test", code: 1)

        let viewModel = FeedListViewModel(feedStorage: mockStorage)
        viewModel.loadFeeds()

        #expect(viewModel.feeds.isEmpty)
        #expect(viewModel.errorMessage != nil)
    }

    @Test("removeFeed removes by feed object")
    @MainActor
    func removeFeedByObject() {
        let feed1 = TestFixtures.makeSubscribedFeed(title: "Keep")
        let feed2 = TestFixtures.makeSubscribedFeed(title: "Remove")
        let mockStorage = MockFeedStorageService()
        mockStorage.feeds = [feed1, feed2]

        let viewModel = FeedListViewModel(feedStorage: mockStorage)
        viewModel.loadFeeds()
        viewModel.removeFeed(feed2)

        #expect(viewModel.feeds.count == 1)
        #expect(viewModel.feeds[0].title == "Keep")
        #expect(mockStorage.feeds.count == 1)
    }

    @Test("removeFeed at IndexSet removes by index")
    @MainActor
    func removeFeedAtIndexSet() {
        let feed1 = TestFixtures.makeSubscribedFeed(title: "First")
        let feed2 = TestFixtures.makeSubscribedFeed(title: "Second")
        let feed3 = TestFixtures.makeSubscribedFeed(title: "Third")
        let mockStorage = MockFeedStorageService()
        mockStorage.feeds = [feed1, feed2, feed3]

        let viewModel = FeedListViewModel(feedStorage: mockStorage)
        viewModel.loadFeeds()
        viewModel.removeFeed(at: IndexSet(integer: 1))

        #expect(viewModel.feeds.count == 2)
        #expect(viewModel.feeds[0].title == "First")
        #expect(viewModel.feeds[1].title == "Third")
        #expect(mockStorage.feeds.count == 2)
    }

    @Test("removeFeed at multi-element IndexSet removes multiple feeds")
    @MainActor
    func removeFeedAtMultiElementIndexSet() {
        let feed1 = TestFixtures.makeSubscribedFeed(title: "First")
        let feed2 = TestFixtures.makeSubscribedFeed(title: "Second")
        let feed3 = TestFixtures.makeSubscribedFeed(title: "Third")
        let mockStorage = MockFeedStorageService()
        mockStorage.feeds = [feed1, feed2, feed3]

        let viewModel = FeedListViewModel(feedStorage: mockStorage)
        viewModel.loadFeeds()
        viewModel.removeFeed(at: IndexSet([0, 2]))

        #expect(viewModel.feeds.count == 1)
        #expect(viewModel.feeds[0].title == "Second")
        #expect(mockStorage.feeds.count == 1)
        #expect(mockStorage.feeds[0].title == "Second")
    }

    @Test("removeFeed rolls back on save failure")
    @MainActor
    func removeFeedSaveFailure() {
        let feed1 = TestFixtures.makeSubscribedFeed(title: "Feed")
        let mockStorage = MockFeedStorageService()
        mockStorage.feeds = [feed1]

        let viewModel = FeedListViewModel(feedStorage: mockStorage)
        viewModel.loadFeeds()

        mockStorage.errorToThrow = NSError(domain: "test", code: 1)
        viewModel.removeFeed(feed1)

        #expect(viewModel.feeds.count == 1)
        #expect(viewModel.errorMessage != nil)
    }

    @Test("removeFeed at IndexSet rolls back on save failure")
    @MainActor
    func removeFeedAtIndexSetSaveFailure() {
        let feed1 = TestFixtures.makeSubscribedFeed(title: "First")
        let feed2 = TestFixtures.makeSubscribedFeed(title: "Second")
        let mockStorage = MockFeedStorageService()
        mockStorage.feeds = [feed1, feed2]

        let viewModel = FeedListViewModel(feedStorage: mockStorage)
        viewModel.loadFeeds()

        mockStorage.errorToThrow = NSError(domain: "test", code: 1)
        viewModel.removeFeed(at: IndexSet(integer: 0))

        #expect(viewModel.feeds.count == 2)
        #expect(viewModel.feeds[0].title == "First")
        #expect(viewModel.errorMessage != nil)
    }

    // MARK: - OPML Import

    @Test("importOPML adds new feeds to empty list")
    @MainActor
    func importOPMLAddsNewFeeds() {
        let mockStorage = MockFeedStorageService()
        let mockOPML = MockOPMLService()
        mockOPML.entriesToReturn = [
            TestFixtures.makeOPMLFeedEntry(title: "Feed A", feedURL: URL(string: "https://a.com/feed")!),
            TestFixtures.makeOPMLFeedEntry(title: "Feed B", feedURL: URL(string: "https://b.com/feed")!),
        ]

        let viewModel = FeedListViewModel(feedStorage: mockStorage, opmlService: mockOPML)
        viewModel.importOPML(from: Data())

        #expect(viewModel.feeds.count == 2)
        #expect(viewModel.feeds[0].title == "Feed A")
        #expect(viewModel.feeds[1].title == "Feed B")
        #expect(mockStorage.feeds.count == 2)
    }

    @Test("importOPML skips duplicate feeds")
    @MainActor
    func importOPMLSkipsDuplicates() {
        let existingFeed = TestFixtures.makeSubscribedFeed(
            title: "Existing",
            url: URL(string: "https://existing.com/feed")!
        )
        let mockStorage = MockFeedStorageService()
        mockStorage.feeds = [existingFeed]

        let mockOPML = MockOPMLService()
        mockOPML.entriesToReturn = [
            TestFixtures.makeOPMLFeedEntry(title: "Existing Dupe", feedURL: URL(string: "https://existing.com/feed")!),
            TestFixtures.makeOPMLFeedEntry(title: "New Feed", feedURL: URL(string: "https://new.com/feed")!),
        ]

        let viewModel = FeedListViewModel(feedStorage: mockStorage, opmlService: mockOPML)
        viewModel.loadFeeds()
        viewModel.importOPML(from: Data())

        #expect(viewModel.feeds.count == 2)
        #expect(viewModel.feeds[0].title == "Existing")
        #expect(viewModel.feeds[1].title == "New Feed")
    }

    @Test("importOPML with all duplicates adds nothing")
    @MainActor
    func importOPMLAllDuplicates() {
        let feed = TestFixtures.makeSubscribedFeed(url: URL(string: "https://a.com/feed")!)
        let mockStorage = MockFeedStorageService()
        mockStorage.feeds = [feed]

        let mockOPML = MockOPMLService()
        mockOPML.entriesToReturn = [
            TestFixtures.makeOPMLFeedEntry(feedURL: URL(string: "https://a.com/feed")!),
        ]

        let viewModel = FeedListViewModel(feedStorage: mockStorage, opmlService: mockOPML)
        viewModel.loadFeeds()
        viewModel.importOPML(from: Data())

        #expect(viewModel.feeds.count == 1)
        #expect(viewModel.opmlImportResult?.addedCount == 0)
        #expect(viewModel.opmlImportResult?.skippedCount == 1)
    }

    @Test("importOPML skips intra-file duplicates")
    @MainActor
    func importOPMLSkipsIntraFileDuplicates() {
        let mockStorage = MockFeedStorageService()
        let mockOPML = MockOPMLService()
        mockOPML.entriesToReturn = [
            TestFixtures.makeOPMLFeedEntry(title: "Feed A", feedURL: URL(string: "https://a.com/feed")!),
            TestFixtures.makeOPMLFeedEntry(title: "Feed A Dupe", feedURL: URL(string: "https://a.com/feed")!),
        ]

        let viewModel = FeedListViewModel(feedStorage: mockStorage, opmlService: mockOPML)
        viewModel.importOPML(from: Data())

        #expect(viewModel.feeds.count == 1)
        #expect(viewModel.feeds[0].title == "Feed A")
        #expect(viewModel.opmlImportResult?.addedCount == 1)
        #expect(viewModel.opmlImportResult?.skippedCount == 1)
    }

    @Test("importOPML sets result with correct counts")
    @MainActor
    func importOPMLSetsResult() {
        let existing = TestFixtures.makeSubscribedFeed(url: URL(string: "https://existing.com/feed")!)
        let mockStorage = MockFeedStorageService()
        mockStorage.feeds = [existing]

        let mockOPML = MockOPMLService()
        mockOPML.entriesToReturn = [
            TestFixtures.makeOPMLFeedEntry(feedURL: URL(string: "https://existing.com/feed")!),
            TestFixtures.makeOPMLFeedEntry(feedURL: URL(string: "https://new1.com/feed")!),
            TestFixtures.makeOPMLFeedEntry(feedURL: URL(string: "https://new2.com/feed")!),
        ]

        let viewModel = FeedListViewModel(feedStorage: mockStorage, opmlService: mockOPML)
        viewModel.loadFeeds()
        viewModel.importOPML(from: Data())

        #expect(viewModel.opmlImportResult?.addedCount == 2)
        #expect(viewModel.opmlImportResult?.skippedCount == 1)
        #expect(viewModel.opmlImportResult?.totalInFile == 3)
        #expect(viewModel.errorMessage == nil)
    }

    @Test("importOPML saves merged list to storage")
    @MainActor
    func importOPMLSavesToStorage() {
        let existing = TestFixtures.makeSubscribedFeed(title: "Existing")
        let mockStorage = MockFeedStorageService()
        mockStorage.feeds = [existing]

        let mockOPML = MockOPMLService()
        mockOPML.entriesToReturn = [
            TestFixtures.makeOPMLFeedEntry(title: "New", feedURL: URL(string: "https://new.com/feed")!),
        ]

        let viewModel = FeedListViewModel(feedStorage: mockStorage, opmlService: mockOPML)
        viewModel.loadFeeds()
        viewModel.importOPML(from: Data())

        #expect(mockStorage.feeds.count == 2)
        #expect(mockStorage.feeds[0].title == "Existing")
        #expect(mockStorage.feeds[1].title == "New")
    }

    @Test("importOPML rolls back on save failure")
    @MainActor
    func importOPMLRollsBackOnSaveFailure() {
        let existing = TestFixtures.makeSubscribedFeed(title: "Existing")
        let mockStorage = MockFeedStorageService()
        mockStorage.feeds = [existing]

        let mockOPML = MockOPMLService()
        mockOPML.entriesToReturn = [
            TestFixtures.makeOPMLFeedEntry(title: "New", feedURL: URL(string: "https://new.com/feed")!),
        ]

        let viewModel = FeedListViewModel(feedStorage: mockStorage, opmlService: mockOPML)
        viewModel.loadFeeds()

        mockStorage.errorToThrow = NSError(domain: "test", code: 1)
        viewModel.importOPML(from: Data())

        #expect(viewModel.feeds.count == 1)
        #expect(viewModel.feeds[0].title == "Existing")
        #expect(viewModel.errorMessage != nil)
    }

    @Test("importOPML sets error on parse failure")
    @MainActor
    func importOPMLSetsErrorOnParseFailure() {
        let existing = TestFixtures.makeSubscribedFeed(title: "Existing")
        let mockStorage = MockFeedStorageService()
        mockStorage.feeds = [existing]

        let mockOPML = MockOPMLService()
        mockOPML.errorToThrow = NSError(domain: "test", code: 1)

        let viewModel = FeedListViewModel(feedStorage: mockStorage, opmlService: mockOPML)
        viewModel.loadFeeds()
        viewModel.importOPML(from: Data())

        #expect(viewModel.errorMessage != nil)
        #expect(viewModel.feeds.count == 1)
        #expect(viewModel.feeds[0].title == "Existing")
    }

    // MARK: - OPML Export

    @Test("exportOPML sets export URL")
    @MainActor
    func exportOPMLSetsURL() {
        let mockStorage = MockFeedStorageService()
        mockStorage.feeds = [
            TestFixtures.makeSubscribedFeed(title: "Feed A"),
            TestFixtures.makeSubscribedFeed(title: "Feed B"),
        ]
        let mockOPML = MockOPMLService()
        mockOPML.dataToReturn = Data("opml-content".utf8)

        let viewModel = FeedListViewModel(feedStorage: mockStorage, opmlService: mockOPML)
        viewModel.loadFeeds()
        viewModel.exportOPML()

        #expect(viewModel.opmlExportURL != nil)
        #expect(viewModel.errorMessage == nil)
    }

    @Test("exportOPML sets error on failure")
    @MainActor
    func exportOPMLSetsErrorOnFailure() {
        let mockStorage = MockFeedStorageService()
        mockStorage.feeds = [TestFixtures.makeSubscribedFeed()]
        let mockOPML = MockOPMLService()
        mockOPML.errorToThrow = NSError(domain: "test", code: 1)

        let viewModel = FeedListViewModel(feedStorage: mockStorage, opmlService: mockOPML)
        viewModel.loadFeeds()
        viewModel.exportOPML()

        #expect(viewModel.opmlExportURL == nil)
        #expect(viewModel.errorMessage != nil)
    }

    // MARK: - Refresh

    @Test("refreshAllFeeds updates metadata from fetched feeds")
    @MainActor
    func refreshAllFeedsUpdatesMetadata() async {
        let url1 = URL(string: "https://one.com/feed")!
        let url2 = URL(string: "https://two.com/feed")!
        let feed1 = TestFixtures.makeSubscribedFeed(title: "Old One", url: url1, feedDescription: "")
        let feed2 = TestFixtures.makeSubscribedFeed(title: "Old Two", url: url2, feedDescription: "")

        let mockStorage = MockFeedStorageService()
        mockStorage.feeds = [feed1, feed2]
        let mockFetching = MockFeedFetchingService()
        mockFetching.feedsByURL = [
            url1: TestFixtures.makeFeed(title: "New One", feedDescription: "Desc One"),
            url2: TestFixtures.makeFeed(title: "New Two", feedDescription: "Desc Two"),
        ]

        let viewModel = FeedListViewModel(feedStorage: mockStorage, feedFetching: mockFetching)
        viewModel.loadFeeds()
        await viewModel.refreshAllFeeds()

        #expect(viewModel.feeds[0].title == "New One")
        #expect(viewModel.feeds[0].feedDescription == "Desc One")
        #expect(viewModel.feeds[0].id == feed1.id)
        #expect(viewModel.feeds[0].addedDate == feed1.addedDate)
        #expect(viewModel.feeds[1].title == "New Two")
        #expect(viewModel.feeds[1].feedDescription == "Desc Two")
        #expect(viewModel.errorMessage == nil)
    }

    @Test("refreshAllFeeds preserves feed when fetch fails")
    @MainActor
    func refreshAllFeedsPreservesOnFailure() async {
        let url = URL(string: "https://fail.com/feed")!
        let feed = TestFixtures.makeSubscribedFeed(title: "Original", url: url, feedDescription: "Original Desc")

        let mockStorage = MockFeedStorageService()
        mockStorage.feeds = [feed]
        let mockFetching = MockFeedFetchingService()
        mockFetching.errorsByURL = [url: FeedFetchingError.invalidResponse(statusCode: 500)]

        let viewModel = FeedListViewModel(feedStorage: mockStorage, feedFetching: mockFetching)
        viewModel.loadFeeds()
        await viewModel.refreshAllFeeds()

        #expect(viewModel.feeds[0].title == "Original")
        #expect(viewModel.feeds[0].feedDescription == "Original Desc")
        #expect(viewModel.errorMessage == "1 of 1 feed(s) could not be updated.")
    }

    @Test("refreshAllFeeds handles partial failures")
    @MainActor
    func refreshAllFeedsPartialFailure() async {
        let url1 = URL(string: "https://ok.com/feed")!
        let url2 = URL(string: "https://fail.com/feed")!
        let feed1 = TestFixtures.makeSubscribedFeed(title: "Will Update", url: url1, feedDescription: "")
        let feed2 = TestFixtures.makeSubscribedFeed(title: "Will Fail", url: url2, feedDescription: "Old")

        let mockStorage = MockFeedStorageService()
        mockStorage.feeds = [feed1, feed2]
        let mockFetching = MockFeedFetchingService()
        mockFetching.feedsByURL = [
            url1: TestFixtures.makeFeed(title: "Updated", feedDescription: "New Desc"),
        ]
        mockFetching.errorsByURL = [url2: FeedFetchingError.invalidResponse(statusCode: 404)]

        let viewModel = FeedListViewModel(feedStorage: mockStorage, feedFetching: mockFetching)
        viewModel.loadFeeds()
        await viewModel.refreshAllFeeds()

        #expect(viewModel.feeds[0].title == "Updated")
        #expect(viewModel.feeds[0].feedDescription == "New Desc")
        #expect(viewModel.feeds[1].title == "Will Fail")
        #expect(viewModel.feeds[1].feedDescription == "Old")
        #expect(viewModel.errorMessage == "1 of 2 feed(s) could not be updated.")
    }

    @Test("refreshAllFeeds saves updated feeds to storage")
    @MainActor
    func refreshAllFeedsSavesToStorage() async {
        let url = URL(string: "https://example.com/feed")!
        let feed = TestFixtures.makeSubscribedFeed(title: "Old", url: url, feedDescription: "")

        let mockStorage = MockFeedStorageService()
        mockStorage.feeds = [feed]
        let mockFetching = MockFeedFetchingService()
        mockFetching.feedsByURL = [url: TestFixtures.makeFeed(title: "New", feedDescription: "Fresh")]

        let viewModel = FeedListViewModel(feedStorage: mockStorage, feedFetching: mockFetching)
        viewModel.loadFeeds()
        await viewModel.refreshAllFeeds()

        #expect(mockStorage.feeds[0].title == "New")
        #expect(mockStorage.feeds[0].feedDescription == "Fresh")
    }

    @Test("refreshAllFeeds is no-op when feeds is empty")
    @MainActor
    func refreshAllFeedsEmptyNoOp() async {
        let mockStorage = MockFeedStorageService()
        let mockFetching = MockFeedFetchingService()

        let viewModel = FeedListViewModel(feedStorage: mockStorage, feedFetching: mockFetching)
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
        let feed = TestFixtures.makeSubscribedFeed(url: url)

        let mockStorage = MockFeedStorageService()
        mockStorage.feeds = [feed]
        let mockFetching = MockFeedFetchingService()
        mockFetching.feedsByURL = [url: TestFixtures.makeFeed()]

        let viewModel = FeedListViewModel(feedStorage: mockStorage, feedFetching: mockFetching)
        viewModel.loadFeeds()
        await viewModel.refreshAllFeeds()

        #expect(viewModel.isRefreshing == false)
    }

    @Test("refreshAllFeeds rolls back on save failure")
    @MainActor
    func refreshAllFeedsRollsBackOnSaveFailure() async {
        let url = URL(string: "https://example.com/feed")!
        let feed = TestFixtures.makeSubscribedFeed(title: "Old", url: url, feedDescription: "Old Desc")

        let mockStorage = MockFeedStorageService()
        mockStorage.feeds = [feed]
        let mockFetching = MockFeedFetchingService()
        mockFetching.feedsByURL = [url: TestFixtures.makeFeed(title: "New", feedDescription: "New Desc")]

        let viewModel = FeedListViewModel(feedStorage: mockStorage, feedFetching: mockFetching)
        viewModel.loadFeeds()

        mockStorage.errorToThrow = NSError(domain: "test", code: 1)
        await viewModel.refreshAllFeeds()

        #expect(viewModel.feeds[0].title == "Old")
        #expect(viewModel.feeds[0].feedDescription == "Old Desc")
        #expect(viewModel.errorMessage == "Unable to save updated feeds.")
    }

    @Test("refreshAllFeeds skips save when metadata unchanged")
    @MainActor
    func refreshAllFeedsSkipsSaveWhenUnchanged() async {
        let url = URL(string: "https://example.com/feed")!
        let feed = TestFixtures.makeSubscribedFeed(title: "Same", url: url, feedDescription: "Same Desc")

        let mockStorage = MockFeedStorageService()
        mockStorage.feeds = [feed]
        let mockFetching = MockFeedFetchingService()
        mockFetching.feedsByURL = [url: TestFixtures.makeFeed(title: "Same", feedDescription: "Same Desc")]

        let viewModel = FeedListViewModel(feedStorage: mockStorage, feedFetching: mockFetching)
        viewModel.loadFeeds()

        // If saveFeeds were called, this error would trigger — proving it was skipped
        mockStorage.errorToThrow = NSError(domain: "test", code: 1)
        await viewModel.refreshAllFeeds()

        #expect(viewModel.feeds[0].title == "Same")
        #expect(viewModel.errorMessage == nil)
    }

    @Test("importOPMLAndRefresh adds feeds then refreshes metadata")
    @MainActor
    func importOPMLAndRefreshIntegration() async {
        let url1 = URL(string: "https://one.com/feed")!
        let url2 = URL(string: "https://two.com/feed")!

        let mockStorage = MockFeedStorageService()
        let mockOPML = MockOPMLService()
        mockOPML.entriesToReturn = [
            TestFixtures.makeOPMLFeedEntry(title: "OPML One", feedURL: url1, description: ""),
            TestFixtures.makeOPMLFeedEntry(title: "OPML Two", feedURL: url2, description: ""),
        ]
        let mockFetching = MockFeedFetchingService()
        mockFetching.feedsByURL = [
            url1: TestFixtures.makeFeed(title: "Real One", feedDescription: "Real Desc One"),
            url2: TestFixtures.makeFeed(title: "Real Two", feedDescription: "Real Desc Two"),
        ]

        let viewModel = FeedListViewModel(
            feedStorage: mockStorage,
            opmlService: mockOPML,
            feedFetching: mockFetching
        )
        await viewModel.importOPMLAndRefresh(from: Data())

        #expect(viewModel.feeds.count == 2)
        #expect(viewModel.feeds[0].title == "Real One")
        #expect(viewModel.feeds[0].feedDescription == "Real Desc One")
        #expect(viewModel.feeds[1].title == "Real Two")
        #expect(viewModel.feeds[1].feedDescription == "Real Desc Two")
        #expect(viewModel.opmlImportResult?.addedCount == 2)
    }
}
