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

    // MARK: - Stable List Snapshot

    /// Creates a loaded FeedViewModel with two articles for snapshot tests.
    /// Cleans up UserDefaults before setup. Caller must clean up after test.
    @MainActor
    private static func makeSnapshotFixture() async -> (
        viewModel: FeedViewModel,
        mockPersistence: MockFeedPersistenceService,
        article1: PersistentArticle,
        article2: PersistentArticle,
        feed: PersistentFeed
    ) {
        let feed = TestFixtures.makePersistentFeed(feedURL: URL(string: "https://example.com/feed")!)
        let mock = MockFeedFetchingService()
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]

        let article1 = TestFixtures.makePersistentArticle(articleID: "a1", isRead: false)
        article1.feed = feed
        let article2 = TestFixtures.makePersistentArticle(articleID: "a2", isRead: true)
        article2.feed = feed
        mockPersistence.articlesByFeedID[feed.id] = [article1, article2]

        mock.feedToReturn = TestFixtures.makeFeed()

        UserDefaults.standard.removeObject(forKey: FeedViewModel.sortAscendingKey)
        let viewModel = FeedViewModel(feed: feed, feedFetching: mock, persistence: mockPersistence)
        await viewModel.loadFeed()

        return (viewModel, mockPersistence, article1, article2, feed)
    }

    @Test("toggleReadStatus does not change article list")
    @MainActor
    func toggleReadStatusKeepsListStable() async {
        let (viewModel, _, article1, _, _) = await Self.makeSnapshotFixture()

        let idsBefore = viewModel.articles.map(\.articleID)

        viewModel.toggleReadStatus(article1)

        #expect(article1.isRead == true)
        #expect(viewModel.articles.map(\.articleID) == idsBefore)

        UserDefaults.standard.removeObject(forKey: FeedViewModel.sortAscendingKey)
    }

    @Test("markAsRead does not change article list")
    @MainActor
    func markAsReadKeepsListStable() async {
        let (viewModel, _, article1, _, _) = await Self.makeSnapshotFixture()

        let idsBefore = viewModel.articles.map(\.articleID)

        viewModel.markAsRead(article1)

        #expect(article1.isRead == true)
        #expect(viewModel.articles.map(\.articleID) == idsBefore)

        UserDefaults.standard.removeObject(forKey: FeedViewModel.sortAscendingKey)
    }

    @Test("reloadArticles refreshes list from persistence")
    @MainActor
    func reloadArticlesRefreshesList() async {
        let (viewModel, mockPersistence, article1, _, feed) = await Self.makeSnapshotFixture()
        #expect(viewModel.articles.count == 2)

        // Add another article to persistence
        let article3 = TestFixtures.makePersistentArticle(articleID: "a3", isRead: false)
        article3.feed = feed
        mockPersistence.articlesByFeedID[feed.id] = [article1, mockPersistence.articlesByFeedID[feed.id]![1], article3]

        viewModel.reloadArticles()
        #expect(viewModel.articles.count == 3)

        UserDefaults.standard.removeObject(forKey: FeedViewModel.sortAscendingKey)
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

    // MARK: - Sort Order

    @Test("sortAscending defaults to false (newest first)")
    @MainActor
    func sortAscendingDefault() {
        UserDefaults.standard.removeObject(forKey: FeedViewModel.sortAscendingKey)
        let feed = TestFixtures.makePersistentFeed()
        let viewModel = FeedViewModel(feed: feed, feedFetching: MockFeedFetchingService(), persistence: MockFeedPersistenceService())

        #expect(viewModel.sortAscending == false)
    }

    @Test("sortAscending toggle persists and reloads articles")
    @MainActor
    func sortAscendingToggleReloads() async {
        UserDefaults.standard.removeObject(forKey: FeedViewModel.sortAscendingKey)
        let feed = TestFixtures.makePersistentFeed(feedURL: URL(string: "https://example.com/feed")!)
        let mock = MockFeedFetchingService()
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]

        let article1 = TestFixtures.makePersistentArticle(
            articleID: "a1",
            publishedDate: Date(timeIntervalSince1970: 1_000_000)
        )
        article1.feed = feed
        let article2 = TestFixtures.makePersistentArticle(
            articleID: "a2",
            publishedDate: Date(timeIntervalSince1970: 2_000_000)
        )
        article2.feed = feed
        mockPersistence.articlesByFeedID[feed.id] = [article1, article2]

        mock.feedToReturn = TestFixtures.makeFeed()

        let viewModel = FeedViewModel(feed: feed, feedFetching: mock, persistence: mockPersistence)
        await viewModel.loadFeed()

        // Default: newest first — article2 should be first
        #expect(viewModel.articles.first?.articleID == "a2")

        // Toggle to ascending (oldest first)
        viewModel.sortAscending = true

        #expect(viewModel.articles.first?.articleID == "a1")

        // Clean up
        UserDefaults.standard.removeObject(forKey: FeedViewModel.sortAscendingKey)
    }

    // MARK: - Read Filter

    @Test("showUnreadOnly filters articles when toggled")
    @MainActor
    func showUnreadOnlyFilters() async {
        let feed = TestFixtures.makePersistentFeed(feedURL: URL(string: "https://example.com/feed")!)
        let mock = MockFeedFetchingService()
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]

        let unread = TestFixtures.makePersistentArticle(articleID: "u1", isRead: false)
        unread.feed = feed
        let read = TestFixtures.makePersistentArticle(articleID: "r1", isRead: true)
        read.feed = feed
        mockPersistence.articlesByFeedID[feed.id] = [unread, read]

        mock.feedToReturn = TestFixtures.makeFeed()

        UserDefaults.standard.removeObject(forKey: FeedViewModel.sortAscendingKey)
        let viewModel = FeedViewModel(feed: feed, feedFetching: mock, persistence: mockPersistence)
        await viewModel.loadFeed()

        #expect(viewModel.articles.count == 2)

        viewModel.showUnreadOnly = true

        #expect(viewModel.articles.count == 1)
        #expect(viewModel.articles.first?.articleID == "u1")

        // Toggle back to all
        viewModel.showUnreadOnly = false

        #expect(viewModel.articles.count == 2)

        // Clean up
        UserDefaults.standard.removeObject(forKey: FeedViewModel.sortAscendingKey)
    }

    @Test("showUnreadOnly does not reload when set to same value")
    @MainActor
    func showUnreadOnlySameValueNoOp() async {
        let feed = TestFixtures.makePersistentFeed(feedURL: URL(string: "https://example.com/feed")!)
        let mock = MockFeedFetchingService()
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]

        let article = TestFixtures.makePersistentArticle(articleID: "a1", isRead: false)
        article.feed = feed
        mockPersistence.articlesByFeedID[feed.id] = [article]

        mock.feedToReturn = TestFixtures.makeFeed()

        let viewModel = FeedViewModel(feed: feed, feedFetching: mock, persistence: mockPersistence)
        await viewModel.loadFeed()
        let articlesBefore = viewModel.articles

        // Set to same value — should not trigger a reload
        viewModel.showUnreadOnly = false

        #expect(viewModel.articles.count == articlesBefore.count)
    }

    // MARK: - Mark All as Read

    @Test("markAllAsRead marks all articles in feed as read")
    @MainActor
    func markAllAsReadMarksFeedArticles() async {
        let feed = TestFixtures.makePersistentFeed(feedURL: URL(string: "https://example.com/feed")!)
        let mock = MockFeedFetchingService()
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]

        let article1 = TestFixtures.makePersistentArticle(articleID: "a1", isRead: false)
        article1.feed = feed
        let article2 = TestFixtures.makePersistentArticle(articleID: "a2", isRead: false)
        article2.feed = feed
        mockPersistence.articlesByFeedID[feed.id] = [article1, article2]

        mock.feedToReturn = TestFixtures.makeFeed()

        UserDefaults.standard.removeObject(forKey: FeedViewModel.sortAscendingKey)
        let viewModel = FeedViewModel(feed: feed, feedFetching: mock, persistence: mockPersistence)
        await viewModel.loadFeed()

        viewModel.markAllAsRead()

        #expect(article1.isRead == true)
        #expect(article2.isRead == true)
        #expect(viewModel.errorMessage == nil)

        // Clean up
        UserDefaults.standard.removeObject(forKey: FeedViewModel.sortAscendingKey)
    }

    @Test("markAllAsRead sets errorMessage on persistence failure")
    @MainActor
    func markAllAsReadError() {
        let feed = TestFixtures.makePersistentFeed()
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.errorToThrow = NSError(domain: "test", code: 1)

        let viewModel = FeedViewModel(feed: feed, feedFetching: MockFeedFetchingService(), persistence: mockPersistence)
        viewModel.markAllAsRead()

        #expect(viewModel.errorMessage != nil)
    }

    // MARK: - Reload Error Paths

    @Test("reloadArticles sets errorMessage when persistence fails during filter toggle")
    @MainActor
    func reloadArticlesErrorOnFilterToggle() async {
        let feed = TestFixtures.makePersistentFeed(feedURL: URL(string: "https://example.com/feed")!)
        let mock = MockFeedFetchingService()
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]

        let article = TestFixtures.makePersistentArticle(articleID: "a1", isRead: false)
        article.feed = feed
        mockPersistence.articlesByFeedID[feed.id] = [article]

        mock.feedToReturn = TestFixtures.makeFeed()

        UserDefaults.standard.removeObject(forKey: FeedViewModel.sortAscendingKey)
        let viewModel = FeedViewModel(feed: feed, feedFetching: mock, persistence: mockPersistence)
        await viewModel.loadFeed()
        #expect(viewModel.articles.count == 1)

        // Inject error before toggling filter
        mockPersistence.errorToThrow = NSError(domain: "test", code: 1)
        viewModel.showUnreadOnly = true

        #expect(viewModel.errorMessage == "Unable to reload articles.")
        #expect(viewModel.articles.count == 1, "Previous article list should be preserved on error")

        // Clean up
        UserDefaults.standard.removeObject(forKey: FeedViewModel.sortAscendingKey)
    }

    @Test("reloadArticles sets errorMessage when persistence fails during sort toggle")
    @MainActor
    func reloadArticlesErrorOnSortToggle() async {
        let feed = TestFixtures.makePersistentFeed(feedURL: URL(string: "https://example.com/feed")!)
        let mock = MockFeedFetchingService()
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]

        let article = TestFixtures.makePersistentArticle(articleID: "a1")
        article.feed = feed
        mockPersistence.articlesByFeedID[feed.id] = [article]

        mock.feedToReturn = TestFixtures.makeFeed()

        UserDefaults.standard.removeObject(forKey: FeedViewModel.sortAscendingKey)
        let viewModel = FeedViewModel(feed: feed, feedFetching: mock, persistence: mockPersistence)
        await viewModel.loadFeed()
        #expect(viewModel.articles.count == 1)

        // Inject error before toggling sort
        mockPersistence.errorToThrow = NSError(domain: "test", code: 1)
        viewModel.sortAscending = true

        #expect(viewModel.errorMessage == "Unable to reload articles.")
        #expect(viewModel.articles.count == 1, "Previous article list should be preserved on error")

        // Clean up
        UserDefaults.standard.removeObject(forKey: FeedViewModel.sortAscendingKey)
    }

    @Test("reloadArticles direct call preserves list on persistence error")
    @MainActor
    func reloadArticlesDirectCallError() async {
        let (viewModel, mockPersistence, _, _, _) = await Self.makeSnapshotFixture()
        #expect(viewModel.articles.count == 2)

        mockPersistence.errorToThrow = NSError(domain: "test", code: 1)
        viewModel.reloadArticles()

        #expect(viewModel.errorMessage == "Unable to reload articles.")
        #expect(viewModel.articles.count == 2, "Previous article list should be preserved on error")

        UserDefaults.standard.removeObject(forKey: FeedViewModel.sortAscendingKey)
    }

    // MARK: - Pagination with Unread Filter

    @Test("loadMoreArticles paginates correctly with showUnreadOnly active")
    @MainActor
    func loadMoreArticlesWithUnreadFilter() async {
        let feed = TestFixtures.makePersistentFeed(feedURL: URL(string: "https://example.com/feed")!)
        let mock = MockFeedFetchingService()
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]

        // Create pageSize + 3 unread articles to force a second page
        let totalCount = FeedViewModel.pageSize + 3
        let articles = (0..<totalCount).map { i in
            let article = TestFixtures.makePersistentArticle(
                articleID: "u\(i)",
                publishedDate: Date(timeIntervalSince1970: Double(totalCount - i) * 1_000_000),
                isRead: false
            )
            article.feed = feed
            return article
        }
        // Also add a read article that should be excluded
        let readArticle = TestFixtures.makePersistentArticle(
            articleID: "read1",
            publishedDate: Date(timeIntervalSince1970: 999_999_999),
            isRead: true
        )
        readArticle.feed = feed
        mockPersistence.articlesByFeedID[feed.id] = articles + [readArticle]

        mock.feedToReturn = TestFixtures.makeFeed()

        UserDefaults.standard.removeObject(forKey: FeedViewModel.sortAscendingKey)
        let viewModel = FeedViewModel(feed: feed, feedFetching: mock, persistence: mockPersistence)
        viewModel.showUnreadOnly = true
        await viewModel.loadFeed()

        // First page should have pageSize unread articles
        #expect(viewModel.articles.count == FeedViewModel.pageSize)
        #expect(viewModel.hasMoreArticles == true)
        // None should be the read article
        #expect(!viewModel.articles.contains { $0.articleID == "read1" })

        // Load next page
        viewModel.loadMoreArticles()

        #expect(viewModel.articles.count == totalCount)
        #expect(viewModel.hasMoreArticles == false)
        // Still no read article
        #expect(!viewModel.articles.contains { $0.articleID == "read1" })

        // Clean up
        UserDefaults.standard.removeObject(forKey: FeedViewModel.sortAscendingKey)
    }

    // MARK: - Toggle Saved

    @Test("toggleSaved saves an unsaved article")
    @MainActor
    func toggleSavedSaves() async {
        let feed = TestFixtures.makePersistentFeed()
        let mock = MockFeedFetchingService()
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]

        let article = TestFixtures.makePersistentArticle(articleID: "a1", isSaved: false)
        article.feed = feed
        mockPersistence.articlesByFeedID[feed.id] = [article]

        let viewModel = FeedViewModel(feed: feed, feedFetching: mock, persistence: mockPersistence)
        viewModel.toggleSaved(article)

        #expect(article.isSaved)
        #expect(article.savedDate != nil)
        #expect(viewModel.errorMessage == nil)
    }

    @Test("toggleSaved unsaves a saved article")
    @MainActor
    func toggleSavedUnsaves() async {
        let feed = TestFixtures.makePersistentFeed()
        let mock = MockFeedFetchingService()
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]

        let article = TestFixtures.makePersistentArticle(
            articleID: "a1",
            isSaved: true,
            savedDate: Date()
        )
        article.feed = feed
        mockPersistence.articlesByFeedID[feed.id] = [article]

        let viewModel = FeedViewModel(feed: feed, feedFetching: mock, persistence: mockPersistence)
        viewModel.toggleSaved(article)

        #expect(!article.isSaved)
        #expect(article.savedDate == nil)
    }

    @Test("toggleSaved sets errorMessage on failure")
    @MainActor
    func toggleSavedError() async {
        let feed = TestFixtures.makePersistentFeed()
        let mock = MockFeedFetchingService()
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.errorToThrow = NSError(domain: "test", code: 1)

        let article = TestFixtures.makePersistentArticle(articleID: "a1")
        let viewModel = FeedViewModel(feed: feed, feedFetching: mock, persistence: mockPersistence)
        viewModel.toggleSaved(article)

        #expect(viewModel.errorMessage != nil)
    }
}
