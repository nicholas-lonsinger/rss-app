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
}
