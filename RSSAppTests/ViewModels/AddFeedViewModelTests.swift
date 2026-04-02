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
        let mockPersistence = MockFeedPersistenceService()

        let viewModel = AddFeedViewModel(feedFetching: mockFetching, persistence: mockPersistence)
        viewModel.urlInput = "https://example.com/feed"
        await viewModel.addFeed()

        #expect(viewModel.didAddFeed == true)
        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.isValidating == false)
        #expect(mockPersistence.feeds.count == 1)
        #expect(mockPersistence.feeds[0].title == "My Feed")
    }

    @Test("addFeed prepends https when scheme missing")
    @MainActor
    func addFeedPrependsScheme() async {
        let mockFetching = MockFeedFetchingService()
        mockFetching.feedToReturn = TestFixtures.makeFeed(title: "Feed")
        let mockPersistence = MockFeedPersistenceService()

        let viewModel = AddFeedViewModel(feedFetching: mockFetching, persistence: mockPersistence)
        viewModel.urlInput = "example.com/feed"
        await viewModel.addFeed()

        #expect(viewModel.didAddFeed == true)
        #expect(mockPersistence.feeds[0].feedURL == URL(string: "https://example.com/feed"))
    }

    @Test("addFeed rejects non-http schemes")
    @MainActor
    func addFeedRejectsNonHTTP() async {
        let mockPersistence = MockFeedPersistenceService()

        let viewModel = AddFeedViewModel(feedFetching: MockFeedFetchingService(), persistence: mockPersistence)
        viewModel.urlInput = "ftp://example.com/feed"
        await viewModel.addFeed()

        #expect(viewModel.didAddFeed == false)
        #expect(viewModel.errorMessage != nil)
        #expect(mockPersistence.feeds.isEmpty)
    }

    @Test("addFeed sets error for invalid URL")
    @MainActor
    func addFeedInvalidURL() async {
        let mockPersistence = MockFeedPersistenceService()

        let viewModel = AddFeedViewModel(feedFetching: MockFeedFetchingService(), persistence: mockPersistence)
        viewModel.urlInput = ""
        await viewModel.addFeed()

        #expect(viewModel.didAddFeed == false)
        #expect(viewModel.errorMessage != nil)
    }

    @Test("addFeed sets error for duplicate URL")
    @MainActor
    func addFeedDuplicate() async {
        let mockFetching = MockFeedFetchingService()
        mockFetching.feedToReturn = TestFixtures.makeFeed()
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [
            TestFixtures.makePersistentFeed(feedURL: URL(string: "https://example.com/feed")!),
        ]

        let viewModel = AddFeedViewModel(feedFetching: mockFetching, persistence: mockPersistence)
        viewModel.urlInput = "https://example.com/feed"
        await viewModel.addFeed()

        #expect(viewModel.didAddFeed == false)
        #expect(viewModel.errorMessage == "You are already subscribed to this feed.")
    }

    @Test("addFeed sets error on network failure")
    @MainActor
    func addFeedNetworkError() async {
        let mockFetching = MockFeedFetchingService()
        mockFetching.errorToThrow = FeedFetchingError.invalidResponse(statusCode: 500)
        let mockPersistence = MockFeedPersistenceService()

        let viewModel = AddFeedViewModel(feedFetching: mockFetching, persistence: mockPersistence)
        viewModel.urlInput = "https://example.com/feed"
        await viewModel.addFeed()

        #expect(viewModel.didAddFeed == false)
        #expect(viewModel.errorMessage == "Could not load feed. Check the URL and try again.")
        #expect(viewModel.isValidating == false)
    }

    @Test("addFeed sets error on persistence failure")
    @MainActor
    func addFeedPersistenceError() async {
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.errorToThrow = NSError(domain: "test", code: 1)

        let viewModel = AddFeedViewModel(feedFetching: MockFeedFetchingService(), persistence: mockPersistence)
        viewModel.urlInput = "https://example.com/feed"
        await viewModel.addFeed()

        #expect(viewModel.didAddFeed == false)
        #expect(viewModel.errorMessage != nil)
    }

    @Test("canSubmit returns false for empty input")
    @MainActor
    func canSubmitEmpty() {
        let viewModel = AddFeedViewModel(
            feedFetching: MockFeedFetchingService(),
            persistence: MockFeedPersistenceService()
        )
        viewModel.urlInput = ""
        #expect(viewModel.canSubmit == false)
    }

    @Test("canSubmit returns true for valid input")
    @MainActor
    func canSubmitValid() {
        let viewModel = AddFeedViewModel(
            feedFetching: MockFeedFetchingService(),
            persistence: MockFeedPersistenceService()
        )
        viewModel.urlInput = "https://example.com/feed"
        #expect(viewModel.canSubmit == true)
    }

    @Test("canSubmit returns false while validating")
    @MainActor
    func canSubmitWhileValidating() {
        let viewModel = AddFeedViewModel(
            feedFetching: MockFeedFetchingService(),
            persistence: MockFeedPersistenceService()
        )
        viewModel.urlInput = "https://example.com/feed"
        viewModel.isValidating = true
        #expect(viewModel.canSubmit == false)
    }

    @Test("addFeed is a no-op when already validating")
    @MainActor
    func addFeedReentrancyGuard() async {
        let mockFetching = MockFeedFetchingService()
        mockFetching.feedToReturn = TestFixtures.makeFeed()
        let mockPersistence = MockFeedPersistenceService()

        let viewModel = AddFeedViewModel(feedFetching: mockFetching, persistence: mockPersistence)
        viewModel.urlInput = "https://example.com/feed"
        viewModel.isValidating = true
        await viewModel.addFeed()

        #expect(viewModel.didAddFeed == false)
        #expect(mockPersistence.feeds.isEmpty)
    }

    @Test("addFeed detects duplicate when input omits scheme")
    @MainActor
    func addFeedDuplicateWithSchemeNormalization() async {
        let mockFetching = MockFeedFetchingService()
        mockFetching.feedToReturn = TestFixtures.makeFeed()
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [
            TestFixtures.makePersistentFeed(feedURL: URL(string: "https://example.com/feed")!),
        ]

        let viewModel = AddFeedViewModel(feedFetching: mockFetching, persistence: mockPersistence)
        viewModel.urlInput = "example.com/feed"
        await viewModel.addFeed()

        #expect(viewModel.didAddFeed == false)
        #expect(viewModel.errorMessage == "You are already subscribed to this feed.")
    }

    @Test("addFeed clears previous error on retry")
    @MainActor
    func addFeedClearsPreviousError() async {
        let mockFetching = MockFeedFetchingService()
        mockFetching.errorToThrow = FeedFetchingError.invalidResponse(statusCode: 500)
        let mockPersistence = MockFeedPersistenceService()

        let viewModel = AddFeedViewModel(feedFetching: mockFetching, persistence: mockPersistence)
        viewModel.urlInput = "https://example.com/feed"
        await viewModel.addFeed()
        #expect(viewModel.errorMessage != nil)

        mockFetching.errorToThrow = nil
        mockFetching.feedToReturn = TestFixtures.makeFeed()
        await viewModel.addFeed()

        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.didAddFeed == true)
    }
}
