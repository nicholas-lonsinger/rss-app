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

    @Test("addFeed preserves existing feeds in storage")
    @MainActor
    func addFeedPreservesExisting() async {
        let mockFetching = MockFeedFetchingService()
        mockFetching.feedToReturn = TestFixtures.makeFeed(title: "New Feed")
        let mockStorage = MockFeedStorageService()
        mockStorage.feeds = [
            TestFixtures.makeSubscribedFeed(title: "Existing Feed", url: URL(string: "https://existing.com/feed")!),
        ]

        let viewModel = AddFeedViewModel(feedFetching: mockFetching, feedStorage: mockStorage)
        viewModel.urlInput = "https://example.com/feed"
        await viewModel.addFeed()

        #expect(mockStorage.feeds.count == 2)
        #expect(mockStorage.feeds[0].title == "Existing Feed")
        #expect(mockStorage.feeds[1].title == "New Feed")
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

    @Test("addFeed rejects non-http schemes")
    @MainActor
    func addFeedRejectsNonHTTP() async {
        let mockFetching = MockFeedFetchingService()
        let mockStorage = MockFeedStorageService()

        let viewModel = AddFeedViewModel(feedFetching: mockFetching, feedStorage: mockStorage)
        viewModel.urlInput = "ftp://example.com/feed"
        await viewModel.addFeed()

        #expect(viewModel.addedFeed == nil)
        #expect(viewModel.errorMessage != nil)
        #expect(mockStorage.feeds.isEmpty)
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

    @Test("addFeed sets error on storage load failure")
    @MainActor
    func addFeedStorageLoadError() async {
        let mockFetching = MockFeedFetchingService()
        let mockStorage = MockFeedStorageService()
        mockStorage.errorToThrow = NSError(domain: "test", code: 1)

        let viewModel = AddFeedViewModel(feedFetching: mockFetching, feedStorage: mockStorage)
        viewModel.urlInput = "https://example.com/feed"
        await viewModel.addFeed()

        #expect(viewModel.addedFeed == nil)
        #expect(viewModel.errorMessage != nil)
    }

    @Test("canSubmit returns false for empty input")
    @MainActor
    func canSubmitEmpty() {
        let viewModel = AddFeedViewModel(
            feedFetching: MockFeedFetchingService(),
            feedStorage: MockFeedStorageService()
        )
        viewModel.urlInput = ""
        #expect(viewModel.canSubmit == false)
    }

    @Test("canSubmit returns false for whitespace-only input")
    @MainActor
    func canSubmitWhitespace() {
        let viewModel = AddFeedViewModel(
            feedFetching: MockFeedFetchingService(),
            feedStorage: MockFeedStorageService()
        )
        viewModel.urlInput = "   \n  "
        #expect(viewModel.canSubmit == false)
    }

    @Test("canSubmit returns true for valid input")
    @MainActor
    func canSubmitValid() {
        let viewModel = AddFeedViewModel(
            feedFetching: MockFeedFetchingService(),
            feedStorage: MockFeedStorageService()
        )
        viewModel.urlInput = "https://example.com/feed"
        #expect(viewModel.canSubmit == true)
    }

    @Test("canSubmit returns false while validating")
    @MainActor
    func canSubmitWhileValidating() {
        let viewModel = AddFeedViewModel(
            feedFetching: MockFeedFetchingService(),
            feedStorage: MockFeedStorageService()
        )
        viewModel.urlInput = "https://example.com/feed"
        viewModel.isValidating = true
        #expect(viewModel.canSubmit == false)
    }

    @Test("addFeed detects duplicate when input omits scheme")
    @MainActor
    func addFeedDuplicateWithSchemeNormalization() async {
        let mockFetching = MockFeedFetchingService()
        mockFetching.feedToReturn = TestFixtures.makeFeed()
        let mockStorage = MockFeedStorageService()
        mockStorage.feeds = [
            TestFixtures.makeSubscribedFeed(url: URL(string: "https://example.com/feed")!),
        ]

        let viewModel = AddFeedViewModel(feedFetching: mockFetching, feedStorage: mockStorage)
        viewModel.urlInput = "example.com/feed"
        await viewModel.addFeed()

        #expect(viewModel.addedFeed == nil)
        #expect(viewModel.errorMessage == "You are already subscribed to this feed.")
        #expect(mockStorage.feeds.count == 1)
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
