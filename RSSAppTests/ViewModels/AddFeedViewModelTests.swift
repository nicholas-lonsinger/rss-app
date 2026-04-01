import Testing
import Foundation
@testable import RSSApp

@Suite("AddFeedViewModel Tests")
struct AddFeedViewModelTests {

    @Test("addFeed succeeds with valid URL")
    @MainActor
    func addFeedSuccess() async {
        let mockFetching = MockFeedFetchingService()
        mockFetching.feedToReturn = TestFixtures.makeFeed(
            title: "My Feed",
            feedDescription: "A great feed"
        )
        let mockStorage = MockFeedStorageService()

        let viewModel = AddFeedViewModel(feedFetching: mockFetching, feedStorage: mockStorage)
        viewModel.urlInput = "https://example.com/feed"
        await viewModel.addFeed()

        #expect(viewModel.addedFeed != nil)
        #expect(viewModel.addedFeed?.title == "My Feed")
        #expect(viewModel.addedFeed?.feedDescription == "A great feed")
        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.isValidating == false)
        #expect(mockStorage.feeds.count == 1)
    }

    @Test("addFeed prepends https when scheme missing")
    @MainActor
    func addFeedPrependsScheme() async {
        let mockFetching = MockFeedFetchingService()
        mockFetching.feedToReturn = TestFixtures.makeFeed(title: "Feed")
        let mockStorage = MockFeedStorageService()

        let viewModel = AddFeedViewModel(feedFetching: mockFetching, feedStorage: mockStorage)
        viewModel.urlInput = "example.com/feed"
        await viewModel.addFeed()

        #expect(viewModel.addedFeed != nil)
        #expect(viewModel.addedFeed?.url == URL(string: "https://example.com/feed"))
    }

    @Test("addFeed sets error for invalid URL")
    @MainActor
    func addFeedInvalidURL() async {
        let mockFetching = MockFeedFetchingService()
        let mockStorage = MockFeedStorageService()

        let viewModel = AddFeedViewModel(feedFetching: mockFetching, feedStorage: mockStorage)
        viewModel.urlInput = ""
        await viewModel.addFeed()

        #expect(viewModel.addedFeed == nil)
        #expect(viewModel.errorMessage != nil)
        #expect(mockStorage.feeds.isEmpty)
    }

    @Test("addFeed sets error for duplicate URL")
    @MainActor
    func addFeedDuplicate() async {
        let mockFetching = MockFeedFetchingService()
        mockFetching.feedToReturn = TestFixtures.makeFeed()
        let mockStorage = MockFeedStorageService()
        mockStorage.feeds = [
            TestFixtures.makeSubscribedFeed(url: URL(string: "https://example.com/feed")!),
        ]

        let viewModel = AddFeedViewModel(feedFetching: mockFetching, feedStorage: mockStorage)
        viewModel.urlInput = "https://example.com/feed"
        await viewModel.addFeed()

        #expect(viewModel.addedFeed == nil)
        #expect(viewModel.errorMessage == "You are already subscribed to this feed.")
        #expect(mockStorage.feeds.count == 1)
    }

    @Test("addFeed sets error on network failure")
    @MainActor
    func addFeedNetworkError() async {
        let mockFetching = MockFeedFetchingService()
        mockFetching.errorToThrow = FeedFetchingError.invalidResponse(statusCode: 500)
        let mockStorage = MockFeedStorageService()

        let viewModel = AddFeedViewModel(feedFetching: mockFetching, feedStorage: mockStorage)
        viewModel.urlInput = "https://example.com/feed"
        await viewModel.addFeed()

        #expect(viewModel.addedFeed == nil)
        #expect(viewModel.errorMessage == "Could not load feed. Check the URL and try again.")
        #expect(viewModel.isValidating == false)
        #expect(mockStorage.feeds.isEmpty)
    }

    @Test("addFeed clears previous error on retry")
    @MainActor
    func addFeedClearsPreviousError() async {
        let mockFetching = MockFeedFetchingService()
        mockFetching.errorToThrow = FeedFetchingError.invalidResponse(statusCode: 500)
        let mockStorage = MockFeedStorageService()

        let viewModel = AddFeedViewModel(feedFetching: mockFetching, feedStorage: mockStorage)
        viewModel.urlInput = "https://example.com/feed"
        await viewModel.addFeed()
        #expect(viewModel.errorMessage != nil)

        mockFetching.errorToThrow = nil
        mockFetching.feedToReturn = TestFixtures.makeFeed()
        await viewModel.addFeed()

        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.addedFeed != nil)
    }
}
