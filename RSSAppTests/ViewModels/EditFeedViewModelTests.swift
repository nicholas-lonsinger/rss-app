import Testing
import Foundation
@testable import RSSApp

@Suite("EditFeedViewModel Tests")
struct EditFeedViewModelTests {

    @Test("saveFeed succeeds with changed URL")
    @MainActor
    func saveFeedSuccess() async {
        let feed = TestFixtures.makePersistentFeed(
            title: "Old Feed",
            feedURL: URL(string: "https://old.com/feed")!
        )
        let mockFetching = MockFeedFetchingService()
        mockFetching.feedToReturn = TestFixtures.makeFeed(
            title: "New Feed",
            feedDescription: "New description"
        )
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]

        let viewModel = EditFeedViewModel(feed: feed, feedFetching: mockFetching, persistence: mockPersistence)
        viewModel.urlInput = "https://new.com/feed"
        await viewModel.saveFeed()

        #expect(viewModel.didSave == true)
        #expect(feed.feedURL == URL(string: "https://new.com/feed"))
        #expect(feed.title == "New Feed")
        #expect(feed.lastFetchError == nil)
        #expect(viewModel.errorMessage == nil)
    }

    @Test("saveFeed dismisses without changes when URL unchanged")
    @MainActor
    func saveFeedUnchangedURL() async {
        let feed = TestFixtures.makePersistentFeed(feedURL: URL(string: "https://example.com/feed")!)
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]

        let viewModel = EditFeedViewModel(feed: feed, feedFetching: MockFeedFetchingService(), persistence: mockPersistence)
        await viewModel.saveFeed()

        #expect(viewModel.didSave == true)
        #expect(viewModel.errorMessage == nil)
    }

    @Test("saveFeed sets error for invalid URL")
    @MainActor
    func saveFeedInvalidURL() async {
        let feed = TestFixtures.makePersistentFeed()
        let viewModel = EditFeedViewModel(
            feed: feed,
            feedFetching: MockFeedFetchingService(),
            persistence: MockFeedPersistenceService()
        )
        viewModel.urlInput = ""
        await viewModel.saveFeed()

        #expect(viewModel.didSave == false)
        #expect(viewModel.errorMessage != nil)
    }

    @Test("saveFeed sets error for duplicate URL")
    @MainActor
    func saveFeedDuplicate() async {
        let feedA = TestFixtures.makePersistentFeed(feedURL: URL(string: "https://a.com/feed")!)
        let feedB = TestFixtures.makePersistentFeed(feedURL: URL(string: "https://b.com/feed")!)
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feedA, feedB]

        let viewModel = EditFeedViewModel(
            feed: feedA,
            feedFetching: MockFeedFetchingService(),
            persistence: mockPersistence
        )
        viewModel.urlInput = "https://b.com/feed"
        await viewModel.saveFeed()

        #expect(viewModel.didSave == false)
        #expect(viewModel.errorMessage == "Another feed already uses this URL.")
    }

    @Test("saveFeed sets error on network failure")
    @MainActor
    func saveFeedNetworkError() async {
        let feed = TestFixtures.makePersistentFeed(feedURL: URL(string: "https://old.com/feed")!)
        let mockFetching = MockFeedFetchingService()
        mockFetching.errorToThrow = FeedFetchingError.invalidResponse(statusCode: 404)
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]

        let viewModel = EditFeedViewModel(feed: feed, feedFetching: mockFetching, persistence: mockPersistence)
        viewModel.urlInput = "https://new.com/feed"
        await viewModel.saveFeed()

        #expect(viewModel.didSave == false)
        #expect(viewModel.errorMessage == "Could not load feed. Check the URL and try again.")
    }

    @Test("saveFeed prepends https when scheme missing")
    @MainActor
    func saveFeedPrependsScheme() async {
        let feed = TestFixtures.makePersistentFeed(feedURL: URL(string: "https://old.com/feed")!)
        let mockFetching = MockFeedFetchingService()
        mockFetching.feedToReturn = TestFixtures.makeFeed(title: "Feed")
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]

        let viewModel = EditFeedViewModel(feed: feed, feedFetching: mockFetching, persistence: mockPersistence)
        viewModel.urlInput = "new.com/feed"
        await viewModel.saveFeed()

        #expect(feed.feedURL == URL(string: "https://new.com/feed"))
    }

    @Test("urlInput is pre-populated from feed URL")
    @MainActor
    func urlInputPrePopulated() {
        let feed = TestFixtures.makePersistentFeed(feedURL: URL(string: "https://example.com/feed")!)
        let viewModel = EditFeedViewModel(
            feed: feed,
            feedFetching: MockFeedFetchingService(),
            persistence: MockFeedPersistenceService()
        )

        #expect(viewModel.urlInput == "https://example.com/feed")
    }
}
