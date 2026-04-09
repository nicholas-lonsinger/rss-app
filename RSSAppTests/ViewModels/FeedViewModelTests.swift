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

    @Test("loadMoreArticles sets errorMessage on persistence failure and preserves hasMore for retry")
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
        // hasMoreArticles preserved so the user can retry
        #expect(viewModel.hasMoreArticles == true)
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

    /// Regression test for #209 (per-feed surface). When the user opens an article
    /// from `ArticleListScreen` (via `FeedArticleSource`) with "Show Unread Only" active, reads it (and additional
    /// articles via the reader's previous/next navigation), then returns to the list,
    /// the now-read articles must remain visible until the user explicitly leaves
    /// and returns or pulls to refresh. This covers the `FeedViewModel` half of
    /// the contract: `markAsRead` (and direct `markArticleRead` calls bypassing the
    /// view model) must mutate persistence without re-querying `articles`, so the
    /// snapshot stays intact for the duration of a reader session — until the view
    /// explicitly calls `reloadArticles()` again. The view-layer suppression that
    /// prevents the post-pop `onAppear` from triggering that explicit reload is
    /// exercised manually (it cannot be tested at the view model layer in isolation).
    @Test("mark as read during simulated reader session leaves unread-filtered list snapshot intact")
    @MainActor
    func readerSessionPreservesUnreadFilteredListSnapshot() async {
        let feed = TestFixtures.makePersistentFeed(feedURL: URL(string: "https://example.com/feed")!)
        let mock = MockFeedFetchingService()
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]

        // Two unread articles with strictly distinct publish dates so sort order is
        // unambiguous. Expected order under default newest-first sort: u1, u2.
        let article1 = TestFixtures.makePersistentArticle(
            articleID: "u1",
            publishedDate: Date(timeIntervalSince1970: 2_000_000),
            isRead: false
        )
        article1.feed = feed
        let article2 = TestFixtures.makePersistentArticle(
            articleID: "u2",
            publishedDate: Date(timeIntervalSince1970: 1_000_000),
            isRead: false
        )
        article2.feed = feed
        mockPersistence.articlesByFeedID[feed.id] = [article1, article2]

        mock.feedToReturn = TestFixtures.makeFeed()

        UserDefaults.standard.removeObject(forKey: FeedViewModel.sortAscendingKey)
        let viewModel = FeedViewModel(feed: feed, feedFetching: mock, persistence: mockPersistence)
        viewModel.showUnreadOnly = true
        await viewModel.loadFeed()

        let expectedOrder = ["u1", "u2"]
        #expect(viewModel.articles.map(\.articleID) == expectedOrder)

        // Simulate tapping article 1: view model marks it as read before pushing the reader.
        viewModel.markAsRead(article1)
        #expect(article1.isRead == true)

        // Simulate the reader paging forward and marking article 2 as read via its own
        // markArticleRead path (bypasses FeedViewModel's snapshot preservation helpers).
        try? mockPersistence.markArticleRead(article2, isRead: true)
        #expect(article2.isRead == true)

        // Returning from the reader must NOT drop the now-read articles from the list —
        // the view suppresses its post-reader onAppear reload so the snapshot is stable
        // even with showUnreadOnly active. Compare against the explicit expected order,
        // not just a captured snapshot, so a regression that scrambles ordering still
        // trips this assertion.
        #expect(viewModel.articles.map(\.articleID) == expectedOrder)

        // Explicit reload (pull-to-refresh, sort/filter toggle, tab change) drops them.
        viewModel.reloadArticles()
        #expect(viewModel.articles.isEmpty)

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

    @Test("markAllAsRead preserves articles list under showUnreadOnly (snapshot-stable rule)")
    @MainActor
    func markAllAsReadPreservesListUnderUnreadFilter() async {
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
        viewModel.showUnreadOnly = true
        await viewModel.loadFeed()
        #expect(viewModel.articles.count == 2)

        viewModel.markAllAsRead()

        // Snapshot-stable rule: even under showUnreadOnly, markAllAsRead does
        // NOT re-query the list. The just-read rows remain visible (now read-
        // styled) until the user triggers an explicit refresh — otherwise the
        // scroll position and currently-focused row are lost mid-action.
        #expect(viewModel.articles.count == 2)
        #expect(viewModel.articles.allSatisfy { $0.isRead })

        // Clean up
        UserDefaults.standard.removeObject(forKey: FeedViewModel.sortAscendingKey)
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

    // MARK: - Load More And Report

    @Test("loadMoreAndReport returns .loaded when new articles are loaded")
    @MainActor
    func loadMoreAndReportReturnsLoaded() async {
        let feed = TestFixtures.makePersistentFeed(feedURL: URL(string: "https://example.com/feed")!)
        let mock = MockFeedFetchingService()
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]

        // Create pageSize + 5 articles to force a second page
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

        #expect(viewModel.articles.count == FeedViewModel.pageSize)
        #expect(viewModel.hasMoreArticles == true)

        let result = viewModel.loadMoreAndReport()

        #expect(result == .loaded)
        #expect(viewModel.articles.count == totalCount)
    }

    @Test("loadMoreAndReport returns .exhausted when no more articles exist")
    @MainActor
    func loadMoreAndReportReturnsExhausted() async {
        let feed = TestFixtures.makePersistentFeed(feedURL: URL(string: "https://example.com/feed")!)
        let mock = MockFeedFetchingService()
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]

        mock.feedToReturn = TestFixtures.makeFeed(articles: [
            TestFixtures.makeArticle(id: "1", title: "Only Article"),
        ])

        let viewModel = FeedViewModel(feed: feed, feedFetching: mock, persistence: mockPersistence)
        await viewModel.loadFeed()

        #expect(viewModel.articles.count == 1)
        #expect(viewModel.hasMoreArticles == false)

        let result = viewModel.loadMoreAndReport()

        #expect(result == .exhausted)
        #expect(viewModel.articles.count == 1)
    }

    @Test("loadMoreAndReport returns .failed when persistence error occurs and preserves hasMore for retry")
    @MainActor
    func loadMoreAndReportReturnsFailed() async {
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

        // Inject error for the next page load
        mockPersistence.errorToThrow = NSError(domain: "test", code: 1)
        let result = viewModel.loadMoreAndReport()

        #expect(result == .failed("Unable to load more articles."))
        // hasMoreArticles preserved so the user can retry
        #expect(viewModel.hasMoreArticles == true)
        // loadMoreAndReport clears errorMessage so only the article reader shows the error
        #expect(viewModel.errorMessage == nil)
    }

    @Test("loadMoreAndReport appends new article at the expected next index")
    @MainActor
    func loadMoreAndReportAppendsNewArticleAtExpectedIndex() async {
        // Verifies that after `loadMoreAndReport()` returns `.loaded`, the freshly appended
        // article appears at the expected index in `viewModel.articles` (i.e. immediately
        // after the previous last element). The pagination read-tracking semantics live in
        // `ArticleReaderView`'s SwiftUI observer chain (`.onChange(of: article.articleID)`)
        // and are exercised via the manual test plan, not unit tests.
        let feed = TestFixtures.makePersistentFeed(feedURL: URL(string: "https://example.com/feed")!)
        let mock = MockFeedFetchingService()
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]

        // Create pageSize + 1 articles so the second page contains exactly one new article.
        // Descending publishedDate is intentional: the default fetch sort is newest-first,
        // so the article order produced by the persistence layer matches the index order
        // asserted below.
        let totalCount = FeedViewModel.pageSize + 1
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

        #expect(viewModel.articles.count == FeedViewModel.pageSize)
        #expect(viewModel.hasMoreArticles == true)

        // The reader increments its currentIndex from pageSize - 1 to pageSize after
        // loadMore returns .loaded; the new article must occupy that next slot.
        let indexBeforePagination = viewModel.articles.count - 1
        let result = viewModel.loadMoreAndReport()
        #expect(result == .loaded)
        #expect(viewModel.articles.count == FeedViewModel.pageSize + 1)

        let newIndex = indexBeforePagination + 1
        #expect(viewModel.articles.indices.contains(newIndex))
    }

    // MARK: - Article Identity Stability

    /// Regression guard for #235. `ArticleReaderView` observes the displayed article's
    /// `articleID` (`.onChange(of: article.articleID)`) to drive both extraction reset
    /// and mark-as-read. That makes `articleID` stability across `reloadArticles()`
    /// load-bearing: if a refresh rebuilt `PersistentArticle` instances (or otherwise
    /// produced different `articleID` values for the same logical entries), the reader
    /// would fire spurious `.onChange` events on every refresh and could mark the wrong
    /// articles as read.
    ///
    /// This variant exercises the cache + overlapping network-merge path — the most
    /// plausible regression surface described in the issue. The cache is pre-populated
    /// with `pageSize` articles, then `loadFeed()` fetches a network response whose
    /// first `pageSize` entries overlap the cache (plus a handful of older additions).
    /// `upsertArticles` must treat the overlap as a dedupe, not a rebuild, so that both
    /// the post-fetch reload inside `loadFeed()` and the subsequent explicit
    /// `reloadArticles()` return the same `articleID` values for the prefix.
    @Test("reloadArticles preserves articleID prefix when network response overlaps cache")
    @MainActor
    func reloadArticlesPreservesArticleIDPrefix() async {
        UserDefaults.standard.removeObject(forKey: FeedViewModel.sortAscendingKey)
        let feed = TestFixtures.makePersistentFeed(feedURL: URL(string: "https://example.com/feed")!)
        let mock = MockFeedFetchingService()
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]

        // Pre-populate persistence with `pageSize` articles in descending publishedDate
        // order so the loaded prefix is deterministic under the default newest-first sort.
        // Uses `makePersistentArticle` because these bypass `upsertArticles` — they model
        // articles already materialized in SwiftData from a prior session.
        let totalCount = FeedViewModel.pageSize + 5
        let cached = (0..<FeedViewModel.pageSize).map { i in
            let article = TestFixtures.makePersistentArticle(
                articleID: "a\(i)",
                publishedDate: Date(timeIntervalSince1970: Double(totalCount - i) * 1_000_000)
            )
            article.feed = feed
            return article
        }
        mockPersistence.articlesByFeedID[feed.id] = cached

        // Network response contains the same `pageSize` articles (full overlap with the
        // cache) plus 5 older additions. Uses `makeArticle` because this is the parser
        // struct path — these flow through `upsertArticles`, exercising the merge logic.
        // The overlap asserts that `upsertArticles` dedupes rather than rebuilding
        // existing rows, which is the regression shape issue #235 is guarding against.
        let networkArticles = (0..<totalCount).map { i in
            TestFixtures.makeArticle(
                id: "a\(i)",
                title: "Article \(i)",
                publishedDate: Date(timeIntervalSince1970: Double(totalCount - i) * 1_000_000)
            )
        }
        mock.feedToReturn = TestFixtures.makeFeed(articles: networkArticles)

        let viewModel = FeedViewModel(feed: feed, feedFetching: mock, persistence: mockPersistence)
        await viewModel.loadFeed()

        #expect(viewModel.articles.count == FeedViewModel.pageSize)
        let prefixBefore = Array(viewModel.articles.prefix(FeedViewModel.pageSize)).map(\.articleID)
        #expect(prefixBefore.count == FeedViewModel.pageSize)

        viewModel.reloadArticles()

        let prefixAfter = Array(viewModel.articles.prefix(FeedViewModel.pageSize)).map(\.articleID)
        #expect(prefixAfter == prefixBefore, "reloadArticles must preserve articleID identity for the previously loaded prefix")

        UserDefaults.standard.removeObject(forKey: FeedViewModel.sortAscendingKey)
    }

    /// Regression guard for #235. Companion to `reloadArticlesPreservesArticleIDPrefix`:
    /// when `loadMoreAndReport()` returns `.loaded`, the previously loaded prefix must
    /// keep stable `articleID` values even though new entries are appended. Otherwise
    /// the reader's `.onChange(of: article.articleID)` observer would mistake an
    /// unchanged article for a new one and re-fire its read-tracking logic.
    @Test("loadMoreAndReport preserves articleID for previously loaded prefix")
    @MainActor
    func loadMoreAndReportPreservesArticleIDPrefix() async {
        UserDefaults.standard.removeObject(forKey: FeedViewModel.sortAscendingKey)
        let feed = TestFixtures.makePersistentFeed(feedURL: URL(string: "https://example.com/feed")!)
        let mock = MockFeedFetchingService()
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]

        // pageSize + 5 articles in descending publishedDate order so the first page
        // is deterministic and the next page contains the remaining 5 entries. Uses
        // `makeArticle` (parser struct path) because the cache is empty here — all
        // rows are materialized through `upsertArticles` during `loadFeed()`.
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

        #expect(viewModel.articles.count == FeedViewModel.pageSize)
        let prefixBefore = Array(viewModel.articles.prefix(FeedViewModel.pageSize)).map(\.articleID)

        let result = viewModel.loadMoreAndReport()
        #expect(result == .loaded)
        #expect(viewModel.articles.count == totalCount)

        let prefixAfter = Array(viewModel.articles.prefix(FeedViewModel.pageSize)).map(\.articleID)
        #expect(prefixAfter == prefixBefore, "loadMoreAndReport must preserve articleID identity for the previously loaded prefix")

        UserDefaults.standard.removeObject(forKey: FeedViewModel.sortAscendingKey)
    }

    @Test("loadMoreArticles succeeds on retry after transient error")
    @MainActor
    func loadMoreArticlesRetryAfterError() async {
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
        let articleCountBeforeError = viewModel.articles.count

        // First attempt fails
        mockPersistence.errorToThrow = NSError(domain: "test", code: 1)
        let failedResult = viewModel.loadMoreArticles()
        #expect(failedResult == .failed("Unable to load more articles."))
        #expect(viewModel.hasMoreArticles == true)
        #expect(viewModel.articles.count == articleCountBeforeError)

        // Clear error and retry succeeds
        mockPersistence.errorToThrow = nil
        let retryResult = viewModel.loadMoreArticles()
        #expect(retryResult == .loaded)
        #expect(viewModel.articles.count > articleCountBeforeError)
    }
}
