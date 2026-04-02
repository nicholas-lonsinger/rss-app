import Testing
import Foundation
@testable import RSSApp

@Suite("FeedViewModel Tests")
struct FeedViewModelTests {

    @Test("loadFeed populates articles on success")
    @MainActor
    func loadFeedSuccess() async {
        let feed = TestFixtures.makePersistentFeed(feedURL: URL(string: "https://example.com/feed")!)
        let mock = MockFeedFetchingService()
        mock.feedToReturn = TestFixtures.makeFeed(articles: [
            TestFixtures.makeArticle(id: "1", title: "Article 1"),
            TestFixtures.makeArticle(id: "2", title: "Article 2"),
        ])
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]

        let viewModel = FeedViewModel(feed: feed, feedFetching: mock, persistence: mockPersistence)
        await viewModel.loadFeed()

        #expect(viewModel.articles.count == 2)
        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.isLoading == false)
    }

    @Test("loadFeed sets errorMessage on failure when no cached articles")
    @MainActor
    func loadFeedFailure() async {
        let feed = TestFixtures.makePersistentFeed(feedURL: URL(string: "https://example.com/feed")!)
        let mock = MockFeedFetchingService()
        mock.errorToThrow = FeedFetchingError.invalidResponse(statusCode: 500)
        let mockPersistence = MockFeedPersistenceService()

        let viewModel = FeedViewModel(feed: feed, feedFetching: mock, persistence: mockPersistence)
        await viewModel.loadFeed()

        #expect(viewModel.articles.isEmpty)
        #expect(viewModel.errorMessage != nil)
        #expect(viewModel.isLoading == false)
    }

    @Test("isLoading is false after loadFeed completes")
    @MainActor
    func isLoadingAfterCompletion() async {
        let feed = TestFixtures.makePersistentFeed(feedURL: URL(string: "https://example.com/feed")!)
        let mock = MockFeedFetchingService()
        mock.feedToReturn = TestFixtures.makeFeed()
        let mockPersistence = MockFeedPersistenceService()

        let viewModel = FeedViewModel(feed: feed, feedFetching: mock, persistence: mockPersistence)
        #expect(viewModel.isLoading == false)

        await viewModel.loadFeed()
        #expect(viewModel.isLoading == false)
    }

    @Test("feedTitle defaults to feed's title")
    @MainActor
    func feedTitleDefault() {
        let feed = TestFixtures.makePersistentFeed(title: "My Feed")
        let viewModel = FeedViewModel(
            feed: feed,
            feedFetching: MockFeedFetchingService(),
            persistence: MockFeedPersistenceService()
        )
        #expect(viewModel.feedTitle == "My Feed")
    }

    @Test("feedTitle updates on successful load")
    @MainActor
    func feedTitleUpdatesOnSuccess() async {
        let feed = TestFixtures.makePersistentFeed(feedURL: URL(string: "https://example.com/feed")!)
        let mock = MockFeedFetchingService()
        mock.feedToReturn = TestFixtures.makeFeed(title: "Electrek")
        let mockPersistence = MockFeedPersistenceService()

        let viewModel = FeedViewModel(feed: feed, feedFetching: mock, persistence: mockPersistence)
        await viewModel.loadFeed()

        #expect(viewModel.feedTitle == "Electrek")
    }

    @Test("feedTitle unchanged on failure")
    @MainActor
    func feedTitleUnchangedOnFailure() async {
        let feed = TestFixtures.makePersistentFeed(title: "Original", feedURL: URL(string: "https://example.com/feed")!)
        let mock = MockFeedFetchingService()
        mock.errorToThrow = FeedFetchingError.invalidResponse(statusCode: 500)
        let mockPersistence = MockFeedPersistenceService()

        let viewModel = FeedViewModel(feed: feed, feedFetching: mock, persistence: mockPersistence)
        await viewModel.loadFeed()

        #expect(viewModel.feedTitle == "Original")
    }
}
