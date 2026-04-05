import Testing
import Foundation
@testable import RSSApp

/// Sendable call counter for verifying async closure invocations from `@Sendable` contexts.
private actor CallCounter {
    private(set) var value = 0

    func increment() {
        value += 1
    }
}

@Suite("HomeViewModel Tests")
struct HomeViewModelTests {

    // MARK: - Unread Count

    @Test("loadUnreadCount returns total unread count")
    @MainActor
    func loadUnreadCountSuccess() {
        let feed = TestFixtures.makePersistentFeed()
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]
        let unreadArticle = TestFixtures.makePersistentArticle(articleID: "a1", isRead: false)
        unreadArticle.feed = feed
        let readArticle = TestFixtures.makePersistentArticle(articleID: "a2", isRead: true)
        readArticle.feed = feed
        mockPersistence.articlesByFeedID[feed.id] = [unreadArticle, readArticle]

        let viewModel = HomeViewModel(persistence: mockPersistence)
        viewModel.loadUnreadCount()

        #expect(viewModel.unreadCount == 1)
        #expect(viewModel.errorMessage == nil)
    }

    @Test("loadUnreadCount sets errorMessage on failure and preserves prior count")
    @MainActor
    func loadUnreadCountError() {
        let feed = TestFixtures.makePersistentFeed()
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]

        let article = TestFixtures.makePersistentArticle(articleID: "a1", isRead: false)
        article.feed = feed
        mockPersistence.articlesByFeedID[feed.id] = [article]

        let viewModel = HomeViewModel(persistence: mockPersistence)
        viewModel.loadUnreadCount()
        #expect(viewModel.unreadCount == 1)
        #expect(viewModel.errorMessage == nil)

        // Inject error after successful count load
        mockPersistence.unreadCountError = NSError(domain: "test", code: 1)
        viewModel.loadUnreadCount()

        #expect(viewModel.errorMessage != nil)
        #expect(viewModel.unreadCount == 1)
    }

    @Test("loadUnreadCount returns zero when no articles")
    @MainActor
    func loadUnreadCountEmpty() {
        let mockPersistence = MockFeedPersistenceService()

        let viewModel = HomeViewModel(persistence: mockPersistence)
        viewModel.loadUnreadCount()

        #expect(viewModel.unreadCount == 0)
        #expect(viewModel.errorMessage == nil)
    }

    // MARK: - Empty Database

    @Test("loadAllArticles returns empty list when no articles exist")
    @MainActor
    func loadAllArticlesEmpty() {
        let mockPersistence = MockFeedPersistenceService()

        let viewModel = HomeViewModel(persistence: mockPersistence)
        viewModel.loadAllArticles()

        #expect(viewModel.allArticlesList.isEmpty)
        #expect(viewModel.hasMoreAllArticles == false)
        #expect(viewModel.errorMessage == nil)
    }

    @Test("loadUnreadArticles returns empty list when no articles exist")
    @MainActor
    func loadUnreadArticlesEmpty() {
        let mockPersistence = MockFeedPersistenceService()

        let viewModel = HomeViewModel(persistence: mockPersistence)
        viewModel.loadUnreadArticles()

        #expect(viewModel.unreadArticlesList.isEmpty)
        #expect(viewModel.hasMoreUnreadArticles == false)
        #expect(viewModel.errorMessage == nil)
    }

    // MARK: - Paginated All Articles

    @Test("loadAllArticles loads first page into allArticlesList")
    @MainActor
    func loadAllArticlesFirstPage() {
        let feed = TestFixtures.makePersistentFeed()
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]

        // Create articles fewer than page size
        let articles = (0..<3).map { i in
            let article = TestFixtures.makePersistentArticle(
                articleID: "a\(i)",
                publishedDate: Date(timeIntervalSince1970: Double(i) * 1_000_000)
            )
            article.feed = feed
            return article
        }
        mockPersistence.articlesByFeedID[feed.id] = articles

        let viewModel = HomeViewModel(persistence: mockPersistence)
        viewModel.loadAllArticles()

        #expect(viewModel.allArticlesList.count == 3)
        #expect(viewModel.hasMoreAllArticles == false)
        #expect(viewModel.errorMessage == nil)
    }

    @Test("loadMoreAllArticles appends next page")
    @MainActor
    func loadMoreAllArticlesAppendsPage() {
        let feed = TestFixtures.makePersistentFeed()
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]

        // Create exactly pageSize + 5 articles to force a second page
        let totalCount = HomeViewModel.pageSize + 5
        let articles = (0..<totalCount).map { i in
            let article = TestFixtures.makePersistentArticle(
                articleID: "a\(i)",
                publishedDate: Date(timeIntervalSince1970: Double(totalCount - i) * 1_000_000)
            )
            article.feed = feed
            return article
        }
        mockPersistence.articlesByFeedID[feed.id] = articles

        let viewModel = HomeViewModel(persistence: mockPersistence)
        viewModel.loadAllArticles()

        #expect(viewModel.allArticlesList.count == HomeViewModel.pageSize)
        #expect(viewModel.hasMoreAllArticles == true)

        viewModel.loadMoreAllArticles()

        #expect(viewModel.allArticlesList.count == totalCount)
        #expect(viewModel.hasMoreAllArticles == false)
    }

    @Test("loadMoreAllArticles does nothing when no more pages")
    @MainActor
    func loadMoreAllArticlesNoOp() {
        let mockPersistence = MockFeedPersistenceService()

        let viewModel = HomeViewModel(persistence: mockPersistence)
        viewModel.loadAllArticles()
        #expect(viewModel.hasMoreAllArticles == false)

        // Should be a no-op
        viewModel.loadMoreAllArticles()
        #expect(viewModel.allArticlesList.isEmpty)
    }

    @Test("loadAllArticles sets errorMessage on failure")
    @MainActor
    func loadAllArticlesError() {
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.errorToThrow = NSError(domain: "test", code: 1)

        let viewModel = HomeViewModel(persistence: mockPersistence)
        viewModel.loadAllArticles()

        #expect(viewModel.allArticlesList.isEmpty)
        #expect(viewModel.errorMessage != nil)
    }

    // MARK: - Paginated Unread Articles

    @Test("loadUnreadArticles loads first page into unreadArticlesList")
    @MainActor
    func loadUnreadArticlesFirstPage() {
        let feed = TestFixtures.makePersistentFeed()
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]

        let unread1 = TestFixtures.makePersistentArticle(articleID: "u1", isRead: false)
        unread1.feed = feed
        let unread2 = TestFixtures.makePersistentArticle(articleID: "u2", isRead: false)
        unread2.feed = feed
        let read = TestFixtures.makePersistentArticle(articleID: "r1", isRead: true)
        read.feed = feed
        mockPersistence.articlesByFeedID[feed.id] = [unread1, unread2, read]

        let viewModel = HomeViewModel(persistence: mockPersistence)
        viewModel.loadUnreadArticles()

        #expect(viewModel.unreadArticlesList.count == 2)
        #expect(viewModel.hasMoreUnreadArticles == false)
    }

    @Test("loadMoreUnreadArticles appends next page")
    @MainActor
    func loadMoreUnreadArticlesAppendsPage() {
        let feed = TestFixtures.makePersistentFeed()
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]

        let totalCount = HomeViewModel.pageSize + 3
        let articles = (0..<totalCount).map { i in
            let article = TestFixtures.makePersistentArticle(
                articleID: "u\(i)",
                publishedDate: Date(timeIntervalSince1970: Double(totalCount - i) * 1_000_000),
                isRead: false
            )
            article.feed = feed
            return article
        }
        mockPersistence.articlesByFeedID[feed.id] = articles

        let viewModel = HomeViewModel(persistence: mockPersistence)
        viewModel.loadUnreadArticles()

        #expect(viewModel.unreadArticlesList.count == HomeViewModel.pageSize)
        #expect(viewModel.hasMoreUnreadArticles == true)

        viewModel.loadMoreUnreadArticles()

        #expect(viewModel.unreadArticlesList.count == totalCount)
        #expect(viewModel.hasMoreUnreadArticles == false)
    }

    @Test("loadMoreUnreadArticles does nothing when no more pages")
    @MainActor
    func loadMoreUnreadArticlesNoOp() {
        let mockPersistence = MockFeedPersistenceService()

        let viewModel = HomeViewModel(persistence: mockPersistence)
        viewModel.loadUnreadArticles()
        #expect(viewModel.hasMoreUnreadArticles == false)

        viewModel.loadMoreUnreadArticles()
        #expect(viewModel.unreadArticlesList.isEmpty)
    }

    @Test("loadUnreadArticles sets errorMessage on failure")
    @MainActor
    func loadUnreadArticlesPaginatedError() {
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.errorToThrow = NSError(domain: "test", code: 1)

        let viewModel = HomeViewModel(persistence: mockPersistence)
        viewModel.loadUnreadArticles()

        #expect(viewModel.unreadArticlesList.isEmpty)
        #expect(viewModel.errorMessage != nil)
        #expect(viewModel.hasMoreUnreadArticles == false)
    }

    @Test("loadAllArticles resets list before loading")
    @MainActor
    func loadAllArticlesResetsState() {
        let feed = TestFixtures.makePersistentFeed()
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]

        let article = TestFixtures.makePersistentArticle(articleID: "a1")
        article.feed = feed
        mockPersistence.articlesByFeedID[feed.id] = [article]

        let viewModel = HomeViewModel(persistence: mockPersistence)
        viewModel.loadAllArticles()
        #expect(viewModel.allArticlesList.count == 1)

        // Load again should reset, not duplicate
        viewModel.loadAllArticles()
        #expect(viewModel.allArticlesList.count == 1)
    }

    @Test("loadUnreadArticles resets list before loading")
    @MainActor
    func loadUnreadArticlesResetsState() {
        let feed = TestFixtures.makePersistentFeed()
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]

        let article = TestFixtures.makePersistentArticle(articleID: "u1", isRead: false)
        article.feed = feed
        mockPersistence.articlesByFeedID[feed.id] = [article]

        let viewModel = HomeViewModel(persistence: mockPersistence)
        viewModel.loadUnreadArticles()
        #expect(viewModel.unreadArticlesList.count == 1)

        // Load again should reset, not duplicate
        viewModel.loadUnreadArticles()
        #expect(viewModel.unreadArticlesList.count == 1)
    }

    @Test("loadAllArticles preserves previous list on error")
    @MainActor
    func loadAllArticlesPreservesOnError() {
        let feed = TestFixtures.makePersistentFeed()
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]

        let article = TestFixtures.makePersistentArticle(articleID: "a1")
        article.feed = feed
        mockPersistence.articlesByFeedID[feed.id] = [article]

        let viewModel = HomeViewModel(persistence: mockPersistence)
        viewModel.loadAllArticles()
        #expect(viewModel.allArticlesList.count == 1)

        // Inject error and reload — previous list should be preserved
        mockPersistence.errorToThrow = NSError(domain: "test", code: 1)
        viewModel.loadAllArticles()
        #expect(viewModel.allArticlesList.count == 1)
        #expect(viewModel.errorMessage != nil)
    }

    @Test("loadUnreadArticles preserves previous list on error")
    @MainActor
    func loadUnreadArticlesPreservesOnError() {
        let feed = TestFixtures.makePersistentFeed()
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]

        let article = TestFixtures.makePersistentArticle(articleID: "u1", isRead: false)
        article.feed = feed
        mockPersistence.articlesByFeedID[feed.id] = [article]

        let viewModel = HomeViewModel(persistence: mockPersistence)
        viewModel.loadUnreadArticles()
        #expect(viewModel.unreadArticlesList.count == 1)

        mockPersistence.errorToThrow = NSError(domain: "test", code: 1)
        viewModel.loadUnreadArticles()
        #expect(viewModel.unreadArticlesList.count == 1)
        #expect(viewModel.errorMessage != nil)
    }

    @Test("loadAllArticles error sets hasMoreAllArticles to false")
    @MainActor
    func loadAllArticlesErrorSetsHasMoreFalse() {
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.errorToThrow = NSError(domain: "test", code: 1)

        let viewModel = HomeViewModel(persistence: mockPersistence)
        viewModel.loadAllArticles()

        #expect(viewModel.hasMoreAllArticles == false)
    }

    // MARK: - Remove From Unread List

    @Test("removeFromUnreadList removes article by ID")
    @MainActor
    func removeFromUnreadListRemovesArticle() {
        let feed = TestFixtures.makePersistentFeed()
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]

        let article1 = TestFixtures.makePersistentArticle(articleID: "u1", isRead: false)
        article1.feed = feed
        let article2 = TestFixtures.makePersistentArticle(articleID: "u2", isRead: false)
        article2.feed = feed
        mockPersistence.articlesByFeedID[feed.id] = [article1, article2]

        let viewModel = HomeViewModel(persistence: mockPersistence)
        viewModel.loadUnreadArticles()
        #expect(viewModel.unreadArticlesList.count == 2)

        viewModel.removeFromUnreadList(article1)
        #expect(viewModel.unreadArticlesList.count == 1)
        #expect(viewModel.unreadArticlesList[0].articleID == "u2")
    }

    // MARK: - Read Status

    @Test("markAsRead sets read status and updates unread count")
    @MainActor
    func markAsReadUpdatesCount() {
        let feed = TestFixtures.makePersistentFeed()
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]

        let article = TestFixtures.makePersistentArticle(articleID: "a1", isRead: false)
        article.feed = feed
        mockPersistence.articlesByFeedID[feed.id] = [article]

        let viewModel = HomeViewModel(persistence: mockPersistence)
        viewModel.loadUnreadCount()
        #expect(viewModel.unreadCount == 1)

        let result = viewModel.markAsRead(article)

        #expect(result == true)
        #expect(article.isRead == true)
        #expect(viewModel.unreadCount == 0)
    }

    @Test("markAsRead is no-op for already read article")
    @MainActor
    func markAsReadNoOp() {
        let feed = TestFixtures.makePersistentFeed()
        let mockPersistence = MockFeedPersistenceService()

        let article = TestFixtures.makePersistentArticle(articleID: "a1", isRead: true)
        article.feed = feed
        mockPersistence.articlesByFeedID[feed.id] = [article]

        let viewModel = HomeViewModel(persistence: mockPersistence)
        let result = viewModel.markAsRead(article)

        #expect(result == true)
        #expect(article.isRead == true)
        #expect(viewModel.errorMessage == nil)
    }

    @Test("markAsRead sets errorMessage on persistence failure, returns false, and preserves unread count")
    @MainActor
    func markAsReadError() {
        let feed = TestFixtures.makePersistentFeed()
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]

        let article = TestFixtures.makePersistentArticle(articleID: "a1", isRead: false)
        article.feed = feed
        let article2 = TestFixtures.makePersistentArticle(articleID: "a2", isRead: false)
        article2.feed = feed
        mockPersistence.articlesByFeedID[feed.id] = [article, article2]

        let viewModel = HomeViewModel(persistence: mockPersistence)
        viewModel.loadUnreadCount()
        #expect(viewModel.unreadCount == 2)

        // Inject error after successful count load
        mockPersistence.errorToThrow = NSError(domain: "test", code: 1)
        let result = viewModel.markAsRead(article)

        #expect(result == false)
        #expect(viewModel.errorMessage != nil)
        #expect(viewModel.unreadCount == 2)
        #expect(article.isRead == false)
    }

    @Test("toggleReadStatus toggles from unread to read")
    @MainActor
    func toggleReadStatusToRead() {
        let feed = TestFixtures.makePersistentFeed()
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]

        let article = TestFixtures.makePersistentArticle(articleID: "a1", isRead: false)
        article.feed = feed
        mockPersistence.articlesByFeedID[feed.id] = [article]

        let viewModel = HomeViewModel(persistence: mockPersistence)
        viewModel.toggleReadStatus(article)

        #expect(article.isRead == true)
    }

    @Test("toggleReadStatus toggles from read to unread")
    @MainActor
    func toggleReadStatusToUnread() {
        let feed = TestFixtures.makePersistentFeed()
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]

        let article = TestFixtures.makePersistentArticle(articleID: "a1", isRead: true)
        article.feed = feed
        mockPersistence.articlesByFeedID[feed.id] = [article]

        let viewModel = HomeViewModel(persistence: mockPersistence)
        viewModel.toggleReadStatus(article)

        #expect(article.isRead == false)
    }

    @Test("toggleReadStatus sets errorMessage on persistence failure and preserves unread count")
    @MainActor
    func toggleReadStatusError() {
        let feed = TestFixtures.makePersistentFeed()
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]

        let article = TestFixtures.makePersistentArticle(articleID: "a1", isRead: false)
        article.feed = feed
        let article2 = TestFixtures.makePersistentArticle(articleID: "a2", isRead: false)
        article2.feed = feed
        mockPersistence.articlesByFeedID[feed.id] = [article, article2]

        let viewModel = HomeViewModel(persistence: mockPersistence)
        viewModel.loadUnreadCount()
        #expect(viewModel.unreadCount == 2)

        // Inject error after successful count load
        mockPersistence.errorToThrow = NSError(domain: "test", code: 1)
        viewModel.toggleReadStatus(article)

        #expect(viewModel.errorMessage != nil)
        #expect(viewModel.unreadCount == 2)
        #expect(article.isRead == false)
    }

    // MARK: - Refresh All Feeds

    @Test("refreshAllFeeds calls refresh closure and reloads unread count")
    @MainActor
    func refreshAllFeedsCallsClosureAndReloadsCount() async {
        let feed = TestFixtures.makePersistentFeed()
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]

        let article = TestFixtures.makePersistentArticle(articleID: "a1", isRead: false)
        article.feed = feed
        mockPersistence.articlesByFeedID[feed.id] = [article]

        let refreshCallCount = CallCounter()
        let viewModel = HomeViewModel(
            persistence: mockPersistence,
            refreshFeeds: { await refreshCallCount.increment() }
        )

        await viewModel.refreshAllFeeds()

        #expect(await refreshCallCount.value == 1)
        #expect(viewModel.unreadCount == 1)
    }

    @Test("refreshAllFeeds is no-op without refresh closure")
    @MainActor
    func refreshAllFeedsNoOpWithoutClosure() async {
        let mockPersistence = MockFeedPersistenceService()
        let viewModel = HomeViewModel(persistence: mockPersistence)

        await viewModel.refreshAllFeeds()

        // Should complete without error
        #expect(viewModel.isRefreshing == false)
        #expect(viewModel.errorMessage == nil)
    }

    @Test("refreshAllFeeds resets isRefreshing to false after completion")
    @MainActor
    func refreshAllFeedsResetsIsRefreshing() async {
        let mockPersistence = MockFeedPersistenceService()

        let viewModel = HomeViewModel(
            persistence: mockPersistence,
            refreshFeeds: {}
        )

        #expect(viewModel.isRefreshing == false)
        await viewModel.refreshAllFeeds()
        #expect(viewModel.isRefreshing == false)
    }

    @Test("refreshAllFeeds skips when already refreshing")
    @MainActor
    func refreshAllFeedsSkipsWhenAlreadyRefreshing() async {
        let mockPersistence = MockFeedPersistenceService()
        let refreshCallCount = CallCounter()

        // Use a continuation to hold the first refresh in-flight
        // so we can attempt a second refresh while it's running.
        let (holdStream, holdContinuation) = AsyncStream<Void>.makeStream()

        let viewModel = HomeViewModel(
            persistence: mockPersistence,
            refreshFeeds: {
                await refreshCallCount.increment()
                // Only the first call waits; subsequent calls should be
                // rejected by the guard before reaching this closure.
                var iterator = holdStream.makeAsyncIterator()
                _ = await iterator.next()
            }
        )

        // Start the first refresh — it will block inside the closure
        let firstRefreshTask = Task { @MainActor in
            await viewModel.refreshAllFeeds()
        }

        // Yield to let the first refresh start and set isRefreshing = true
        await Task.yield()

        // Attempt a second refresh while the first is in-flight
        await viewModel.refreshAllFeeds()

        // Release the first refresh
        holdContinuation.finish()
        await firstRefreshTask.value

        #expect(await refreshCallCount.value == 1)
    }

    @Test("init without refreshFeeds defaults to nil")
    @MainActor
    func initWithoutRefreshFeedsDefaultsToNil() async {
        let mockPersistence = MockFeedPersistenceService()
        let viewModel = HomeViewModel(persistence: mockPersistence)

        // Should be safe to call — no-op
        await viewModel.refreshAllFeeds()
        #expect(viewModel.isRefreshing == false)
    }

    // MARK: - Clear Error

    @Test("clearError resets errorMessage to nil")
    @MainActor
    func clearErrorResetsMessage() {
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.errorToThrow = NSError(domain: "test", code: 1)

        let viewModel = HomeViewModel(persistence: mockPersistence)
        viewModel.loadUnreadCount()
        #expect(viewModel.errorMessage != nil)

        viewModel.clearError()

        #expect(viewModel.errorMessage == nil)
    }
}
