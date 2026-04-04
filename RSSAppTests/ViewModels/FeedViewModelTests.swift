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

    // MARK: - Cache-First Loading

    @Test("loadFeed shows cached articles when network fails")
    @MainActor
    func loadFeedCachedArticlesOnNetworkFailure() async {
        let feed = TestFixtures.makePersistentFeed(feedURL: URL(string: "https://example.com/feed")!)
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]
        // Pre-populate cached articles
        let cachedArticles = [
            TestFixtures.makeArticle(id: "cached-1", title: "Cached Article"),
        ]
        try? mockPersistence.upsertArticles(cachedArticles, for: feed)

        let mock = MockFeedFetchingService()
        mock.errorToThrow = FeedFetchingError.invalidResponse(statusCode: 500)

        let viewModel = FeedViewModel(feed: feed, feedFetching: mock, persistence: mockPersistence)
        await viewModel.loadFeed()

        // Should show cached articles, NOT show error
        #expect(viewModel.articles.count == 1)
        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.isLoading == false)
    }

    @Test("loadFeed shows error only when no cached articles and network fails")
    @MainActor
    func loadFeedErrorWhenNoCachedArticles() async {
        let feed = TestFixtures.makePersistentFeed(feedURL: URL(string: "https://example.com/feed")!)
        let mockPersistence = MockFeedPersistenceService()
        let mock = MockFeedFetchingService()
        mock.errorToThrow = FeedFetchingError.invalidResponse(statusCode: 500)

        let viewModel = FeedViewModel(feed: feed, feedFetching: mock, persistence: mockPersistence)
        await viewModel.loadFeed()

        #expect(viewModel.articles.isEmpty)
        #expect(viewModel.errorMessage != nil)
    }

    // MARK: - Paginated Loading

    @Test("loadMoreArticles appends next page")
    @MainActor
    func loadMoreArticlesAppendsPage() async {
        let feed = TestFixtures.makePersistentFeed(feedURL: URL(string: "https://example.com/feed")!)
        let mock = MockFeedFetchingService()
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]

        // Create pageSize + 5 articles
        let totalCount = FeedViewModel.pageSize + 5
        let articles = (0..<totalCount).map { i in
            TestFixtures.makeArticle(
                id: "a\(i)",
                title: "Article \(i)",
                publishedDate: Date(timeIntervalSince1970: Double(totalCount - i) * 1_000_000)
            )
        }
        mock.feedToReturn = TestFixtures.makeFeed(articles: articles)

        let viewModel = FeedViewModel(feed: feed, feedFetching: mock, persistence: mockPersistence)
        await viewModel.loadFeed()

        // After loadFeed, should have first page
        #expect(viewModel.articles.count == FeedViewModel.pageSize)
        #expect(viewModel.hasMoreArticles == true)

        // Load next page
        viewModel.loadMoreArticles()

        #expect(viewModel.articles.count == totalCount)
        #expect(viewModel.hasMoreArticles == false)
    }

    @Test("loadMoreArticles is no-op when no more pages")
    @MainActor
    func loadMoreArticlesNoOp() async {
        let feed = TestFixtures.makePersistentFeed(feedURL: URL(string: "https://example.com/feed")!)
        let mock = MockFeedFetchingService()
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]

        // Create fewer articles than page size
        mock.feedToReturn = TestFixtures.makeFeed(articles: [
            TestFixtures.makeArticle(id: "1", title: "Article 1"),
        ])

        let viewModel = FeedViewModel(feed: feed, feedFetching: mock, persistence: mockPersistence)
        await viewModel.loadFeed()

        #expect(viewModel.articles.count == 1)
        #expect(viewModel.hasMoreArticles == false)

        // Should be no-op
        viewModel.loadMoreArticles()
        #expect(viewModel.articles.count == 1)
    }

    @Test("loadMoreArticles sets errorMessage on persistence failure")
    @MainActor
    func loadMoreArticlesPersistenceError() async {
        let feed = TestFixtures.makePersistentFeed(feedURL: URL(string: "https://example.com/feed")!)
        let mock = MockFeedFetchingService()
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]

        // Create enough articles for pagination
        let totalCount = FeedViewModel.pageSize + 5
        let articles = (0..<totalCount).map { i in
            TestFixtures.makeArticle(
                id: "a\(i)",
                title: "Article \(i)",
                publishedDate: Date(timeIntervalSince1970: Double(totalCount - i) * 1_000_000)
            )
        }
        mock.feedToReturn = TestFixtures.makeFeed(articles: articles)

        let viewModel = FeedViewModel(feed: feed, feedFetching: mock, persistence: mockPersistence)
        await viewModel.loadFeed()

        #expect(viewModel.hasMoreArticles == true)

        // Now inject error for the next page load
        mockPersistence.errorToThrow = NSError(domain: "test", code: 1)
        let articleCountBefore = viewModel.articles.count
        viewModel.loadMoreArticles()

        #expect(viewModel.errorMessage != nil)
        #expect(viewModel.articles.count == articleCountBefore)
        #expect(viewModel.hasMoreArticles == false)
    }

    @Test("loadFeed sets hasMoreArticles to false when cached articles fewer than page size")
    @MainActor
    func loadFeedCacheHasMoreArticlesFalse() async {
        let feed = TestFixtures.makePersistentFeed(feedURL: URL(string: "https://example.com/feed")!)
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]
        let cachedArticles = [
            TestFixtures.makeArticle(id: "cached-1", title: "Cached Article"),
        ]
        try? mockPersistence.upsertArticles(cachedArticles, for: feed)

        let mock = MockFeedFetchingService()
        mock.errorToThrow = FeedFetchingError.invalidResponse(statusCode: 500)

        let viewModel = FeedViewModel(feed: feed, feedFetching: mock, persistence: mockPersistence)
        await viewModel.loadFeed()

        #expect(viewModel.articles.count == 1)
        #expect(viewModel.hasMoreArticles == false)
    }

    // MARK: - Read Status

    @Test("markAsRead sets read status on unread article")
    @MainActor
    func markAsReadSetsStatus() {
        let feed = TestFixtures.makePersistentFeed()
        let article = TestFixtures.makePersistentArticle(isRead: false)
        let mockPersistence = MockFeedPersistenceService()

        let viewModel = FeedViewModel(feed: feed, feedFetching: MockFeedFetchingService(), persistence: mockPersistence)
        viewModel.markAsRead(article)

        #expect(article.isRead == true)
    }

    @Test("markAsRead is no-op for already read article")
    @MainActor
    func markAsReadNoOpForRead() {
        let feed = TestFixtures.makePersistentFeed()
        let article = TestFixtures.makePersistentArticle(isRead: true)
        let mockPersistence = MockFeedPersistenceService()

        let viewModel = FeedViewModel(feed: feed, feedFetching: MockFeedFetchingService(), persistence: mockPersistence)
        viewModel.markAsRead(article)

        #expect(article.isRead == true)
        #expect(viewModel.errorMessage == nil)
    }

    @Test("toggleReadStatus toggles from unread to read")
    @MainActor
    func toggleReadStatusToRead() {
        let feed = TestFixtures.makePersistentFeed()
        let article = TestFixtures.makePersistentArticle(isRead: false)
        let mockPersistence = MockFeedPersistenceService()

        let viewModel = FeedViewModel(feed: feed, feedFetching: MockFeedFetchingService(), persistence: mockPersistence)
        viewModel.toggleReadStatus(article)

        #expect(article.isRead == true)
    }

    @Test("toggleReadStatus toggles from read to unread")
    @MainActor
    func toggleReadStatusToUnread() {
        let feed = TestFixtures.makePersistentFeed()
        let article = TestFixtures.makePersistentArticle(isRead: true)
        let mockPersistence = MockFeedPersistenceService()

        let viewModel = FeedViewModel(feed: feed, feedFetching: MockFeedFetchingService(), persistence: mockPersistence)
        viewModel.toggleReadStatus(article)

        #expect(article.isRead == false)
    }

    @Test("loadFeed clears error on successful retry")
    @MainActor
    func loadFeedClearsErrorOnRetry() async {
        let feed = TestFixtures.makePersistentFeed(feedURL: URL(string: "https://example.com/feed")!)
        let mock = MockFeedFetchingService()
        mock.errorToThrow = FeedFetchingError.invalidResponse(statusCode: 500)
        let mockPersistence = MockFeedPersistenceService()

        let viewModel = FeedViewModel(feed: feed, feedFetching: mock, persistence: mockPersistence)
        await viewModel.loadFeed()
        #expect(viewModel.errorMessage != nil)

        // Retry with success
        mock.errorToThrow = nil
        mock.feedToReturn = TestFixtures.makeFeed(articles: [
            TestFixtures.makeArticle(id: "1", title: "Article"),
        ])
        await viewModel.loadFeed()

        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.articles.count == 1)
    }

    @Test("loadFeed accumulates articles via upsert")
    @MainActor
    func loadFeedAccumulatesArticles() async {
        let feed = TestFixtures.makePersistentFeed(feedURL: URL(string: "https://example.com/feed")!)
        let mock = MockFeedFetchingService()
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]

        // First load: 2 articles
        mock.feedToReturn = TestFixtures.makeFeed(articles: [
            TestFixtures.makeArticle(id: "1", title: "First"),
            TestFixtures.makeArticle(id: "2", title: "Second"),
        ])
        let viewModel = FeedViewModel(feed: feed, feedFetching: mock, persistence: mockPersistence)
        await viewModel.loadFeed()
        #expect(viewModel.articles.count == 2)

        // Second load: 1 new + 1 existing (should have 3 total after upsert)
        mock.feedToReturn = TestFixtures.makeFeed(articles: [
            TestFixtures.makeArticle(id: "2", title: "Second Updated"),
            TestFixtures.makeArticle(id: "3", title: "Third"),
        ])
        await viewModel.loadFeed()
        #expect(viewModel.articles.count == 3)
    }

    @Test("markAsRead sets errorMessage on persistence failure")
    @MainActor
    func markAsReadPersistenceError() {
        let feed = TestFixtures.makePersistentFeed()
        let article = TestFixtures.makePersistentArticle(isRead: false)
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.errorToThrow = NSError(domain: "test", code: 1)

        let viewModel = FeedViewModel(feed: feed, feedFetching: MockFeedFetchingService(), persistence: mockPersistence)
        viewModel.markAsRead(article)

        #expect(viewModel.errorMessage != nil)
    }
}
