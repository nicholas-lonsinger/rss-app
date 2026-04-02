import Testing
import Foundation
@testable import RSSApp

@Suite("EditFeedViewModel Tests")
struct EditFeedViewModelTests {

    @Test("saveFeed succeeds with changed URL")
    @MainActor
    func saveFeedSuccess() async {
        let feed = TestFixtures.makeSubscribedFeed(
            title: "Old Feed",
            url: URL(string: "https://old.com/feed")!
        )
        let mockFetching = MockFeedFetchingService()
        mockFetching.feedToReturn = TestFixtures.makeFeed(
            title: "New Feed",
            feedDescription: "New description"
        )
        let mockStorage = MockFeedStorageService()
        mockStorage.feeds = [feed]

        let viewModel = EditFeedViewModel(feed: feed, feedFetching: mockFetching, feedStorage: mockStorage)
        viewModel.urlInput = "https://new.com/feed"
        await viewModel.saveFeed()

        #expect(viewModel.updatedFeed != nil)
        #expect(viewModel.updatedFeed?.url == URL(string: "https://new.com/feed"))
        #expect(viewModel.updatedFeed?.title == "New Feed")
        #expect(viewModel.updatedFeed?.lastFetchError == nil)
        #expect(viewModel.errorMessage == nil)
        #expect(mockStorage.feeds[0].url == URL(string: "https://new.com/feed"))
    }

    @Test("saveFeed dismisses without changes when URL unchanged")
    @MainActor
    func saveFeedUnchangedURL() async {
        let feed = TestFixtures.makeSubscribedFeed(url: URL(string: "https://example.com/feed")!)
        let mockFetching = MockFeedFetchingService()
        let mockStorage = MockFeedStorageService()
        mockStorage.feeds = [feed]

        let viewModel = EditFeedViewModel(feed: feed, feedFetching: mockFetching, feedStorage: mockStorage)
        // urlInput is pre-populated with feed.url
        await viewModel.saveFeed()

        #expect(viewModel.updatedFeed != nil)
        #expect(viewModel.errorMessage == nil)
    }

    @Test("saveFeed sets error for invalid URL")
    @MainActor
    func saveFeedInvalidURL() async {
        let feed = TestFixtures.makeSubscribedFeed()
        let viewModel = EditFeedViewModel(
            feed: feed,
            feedFetching: MockFeedFetchingService(),
            feedStorage: MockFeedStorageService()
        )
        viewModel.urlInput = ""
        await viewModel.saveFeed()

        #expect(viewModel.updatedFeed == nil)
        #expect(viewModel.errorMessage != nil)
    }

    @Test("saveFeed sets error for duplicate URL")
    @MainActor
    func saveFeedDuplicate() async {
        let feedA = TestFixtures.makeSubscribedFeed(
            id: UUID(),
            url: URL(string: "https://a.com/feed")!
        )
        let feedB = TestFixtures.makeSubscribedFeed(
            id: UUID(),
            url: URL(string: "https://b.com/feed")!
        )
        let mockStorage = MockFeedStorageService()
        mockStorage.feeds = [feedA, feedB]

        let viewModel = EditFeedViewModel(
            feed: feedA,
            feedFetching: MockFeedFetchingService(),
            feedStorage: mockStorage
        )
        viewModel.urlInput = "https://b.com/feed"
        await viewModel.saveFeed()

        #expect(viewModel.updatedFeed == nil)
        #expect(viewModel.errorMessage == "Another feed already uses this URL.")
    }

    @Test("saveFeed sets error on network failure")
    @MainActor
    func saveFeedNetworkError() async {
        let feed = TestFixtures.makeSubscribedFeed(url: URL(string: "https://old.com/feed")!)
        let mockFetching = MockFeedFetchingService()
        mockFetching.errorToThrow = FeedFetchingError.invalidResponse(statusCode: 404)
        let mockStorage = MockFeedStorageService()
        mockStorage.feeds = [feed]

        let viewModel = EditFeedViewModel(feed: feed, feedFetching: mockFetching, feedStorage: mockStorage)
        viewModel.urlInput = "https://new.com/feed"
        await viewModel.saveFeed()

        #expect(viewModel.updatedFeed == nil)
        #expect(viewModel.errorMessage == "Could not load feed. Check the URL and try again.")
    }

    @Test("saveFeed prepends https when scheme missing")
    @MainActor
    func saveFeedPrependsScheme() async {
        let feed = TestFixtures.makeSubscribedFeed(url: URL(string: "https://old.com/feed")!)
        let mockFetching = MockFeedFetchingService()
        mockFetching.feedToReturn = TestFixtures.makeFeed(title: "Feed")
        let mockStorage = MockFeedStorageService()
        mockStorage.feeds = [feed]

        let viewModel = EditFeedViewModel(feed: feed, feedFetching: mockFetching, feedStorage: mockStorage)
        viewModel.urlInput = "new.com/feed"
        await viewModel.saveFeed()

        #expect(viewModel.updatedFeed?.url == URL(string: "https://new.com/feed"))
    }

    @Test("urlInput is pre-populated from feed URL")
    @MainActor
    func urlInputPrePopulated() {
        let feed = TestFixtures.makeSubscribedFeed(url: URL(string: "https://example.com/feed")!)
        let viewModel = EditFeedViewModel(
            feed: feed,
            feedFetching: MockFeedFetchingService(),
            feedStorage: MockFeedStorageService()
        )

        #expect(viewModel.urlInput == "https://example.com/feed")
    }
}
