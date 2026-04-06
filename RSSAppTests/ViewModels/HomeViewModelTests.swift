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

/// Sendable toggle for controlling closure behavior across `@Sendable` boundaries in tests.
private actor FailToggle {
    private(set) var shouldFail = true

    func setShouldFail(_ value: Bool) {
        shouldFail = value
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

    // MARK: - Stable List Snapshot

    /// Creates two unread articles linked to a feed and returns the view model with the unread list loaded.
    @MainActor
    private static func makeUnreadSnapshotFixture() -> (
        viewModel: HomeViewModel,
        mockPersistence: MockFeedPersistenceService,
        article1: PersistentArticle,
        article2: PersistentArticle,
        feed: PersistentFeed
    ) {
        let feed = TestFixtures.makePersistentFeed()
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]

        let article1 = TestFixtures.makePersistentArticle(articleID: "u1", isRead: false)
        article1.feed = feed
        let article2 = TestFixtures.makePersistentArticle(articleID: "u2", isRead: false)
        article2.feed = feed
        mockPersistence.articlesByFeedID[feed.id] = [article1, article2]

        let viewModel = HomeViewModel(persistence: mockPersistence)
        return (viewModel, mockPersistence, article1, article2, feed)
    }

    @Test("toggleReadStatus does not remove article from unread list")
    @MainActor
    func toggleReadStatusKeepsArticleInUnreadList() {
        let (viewModel, _, article1, _, _) = Self.makeUnreadSnapshotFixture()
        viewModel.loadUnreadArticles()

        let idsBefore = viewModel.unreadArticlesList.map(\.articleID)
        #expect(idsBefore.count == 2)

        viewModel.toggleReadStatus(article1)
        #expect(article1.isRead == true)
        #expect(viewModel.unreadArticlesList.map(\.articleID) == idsBefore)
    }

    @Test("markAsRead does not remove article from unread list")
    @MainActor
    func markAsReadKeepsArticleInUnreadList() {
        let (viewModel, _, article1, _, _) = Self.makeUnreadSnapshotFixture()
        viewModel.loadUnreadArticles()

        let idsBefore = viewModel.unreadArticlesList.map(\.articleID)
        #expect(idsBefore.count == 2)

        let result = viewModel.markAsRead(article1)
        #expect(result == true)
        #expect(article1.isRead == true)
        #expect(viewModel.unreadArticlesList.map(\.articleID) == idsBefore)
    }

    @Test("toggleReadStatus does not remove article from all articles list")
    @MainActor
    func toggleReadStatusKeepsArticleInAllArticlesList() {
        let feed = TestFixtures.makePersistentFeed()
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]

        let article1 = TestFixtures.makePersistentArticle(articleID: "a1", isRead: false)
        article1.feed = feed
        let article2 = TestFixtures.makePersistentArticle(articleID: "a2", isRead: true)
        article2.feed = feed
        mockPersistence.articlesByFeedID[feed.id] = [article1, article2]

        let viewModel = HomeViewModel(persistence: mockPersistence)
        viewModel.loadAllArticles()

        let idsBefore = viewModel.allArticlesList.map(\.articleID)
        #expect(idsBefore.count == 2)

        viewModel.toggleReadStatus(article1)
        #expect(article1.isRead == true)
        #expect(viewModel.allArticlesList.map(\.articleID) == idsBefore)
    }

    @Test("loadAllArticles reload picks up new articles from persistence")
    @MainActor
    func loadAllArticlesReloadPicksUpNewData() {
        let feed = TestFixtures.makePersistentFeed()
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]

        let article1 = TestFixtures.makePersistentArticle(articleID: "a1")
        article1.feed = feed
        mockPersistence.articlesByFeedID[feed.id] = [article1]

        let viewModel = HomeViewModel(persistence: mockPersistence)
        viewModel.loadAllArticles()
        #expect(viewModel.allArticlesList.count == 1)

        // Simulate a new article appearing in persistence (e.g., background fetch)
        let article2 = TestFixtures.makePersistentArticle(articleID: "a2")
        article2.feed = feed
        mockPersistence.articlesByFeedID[feed.id] = [article1, article2]

        viewModel.loadAllArticles()
        #expect(viewModel.allArticlesList.count == 2)
    }

    @Test("loadUnreadArticles reload picks up new unread articles from persistence")
    @MainActor
    func loadUnreadArticlesReloadPicksUpNewData() {
        let (viewModel, mockPersistence, article1, _, feed) = Self.makeUnreadSnapshotFixture()
        viewModel.loadUnreadArticles()
        #expect(viewModel.unreadArticlesList.count == 2)

        // Simulate a new unread article appearing in persistence
        let article3 = TestFixtures.makePersistentArticle(articleID: "u3", isRead: false)
        article3.feed = feed
        mockPersistence.articlesByFeedID[feed.id] = [article1, mockPersistence.articlesByFeedID[feed.id]![1], article3]

        viewModel.loadUnreadArticles()
        #expect(viewModel.unreadArticlesList.count == 3)
    }

    @Test("loadUnreadArticles reload excludes articles marked read since last load")
    @MainActor
    func loadUnreadArticlesReloadExcludesReadArticles() {
        let (viewModel, _, article1, _, _) = Self.makeUnreadSnapshotFixture()
        viewModel.loadUnreadArticles()
        #expect(viewModel.unreadArticlesList.count == 2)

        // Mark article as read — snapshot stays stable
        viewModel.toggleReadStatus(article1)
        #expect(article1.isRead == true)
        #expect(viewModel.unreadArticlesList.count == 2)

        // Reload (simulating navigation return) — now-read article should be excluded
        viewModel.loadUnreadArticles()
        #expect(viewModel.unreadArticlesList.count == 1)
        #expect(viewModel.unreadArticlesList.first?.articleID == "u2")
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

    @Test("refreshAllFeeds calls refresh closure")
    @MainActor
    func refreshAllFeedsCallsClosure() async {
        let mockPersistence = MockFeedPersistenceService()
        let refreshCallCount = CallCounter()
        let viewModel = HomeViewModel(
            persistence: mockPersistence,
            refreshFeeds: {
                await refreshCallCount.increment()
                return nil
            }
        )

        await viewModel.refreshAllFeeds()

        #expect(await refreshCallCount.value == 1)
        #expect(viewModel.errorMessage == nil)
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
            refreshFeeds: { return nil }
        )

        #expect(viewModel.isRefreshing == false)
        await viewModel.refreshAllFeeds()
        #expect(viewModel.isRefreshing == false)
    }

    @Test("refreshAllFeeds sets errorMessage when refresh closure returns error")
    @MainActor
    func refreshAllFeedsSetsErrorFromClosure() async {
        let mockPersistence = MockFeedPersistenceService()
        let viewModel = HomeViewModel(
            persistence: mockPersistence,
            refreshFeeds: { return "2 of 5 feed(s) could not be updated." }
        )

        await viewModel.refreshAllFeeds()

        #expect(viewModel.errorMessage == "2 of 5 feed(s) could not be updated.")
        #expect(viewModel.isRefreshing == false)
    }

    @Test("refreshAllFeeds clears previous errorMessage on success")
    @MainActor
    func refreshAllFeedsClearsPreviousError() async {
        let mockPersistence = MockFeedPersistenceService()
        let failToggle = FailToggle()

        let viewModel = HomeViewModel(
            persistence: mockPersistence,
            refreshFeeds: {
                return await failToggle.shouldFail ? "Error" : nil
            }
        )

        await viewModel.refreshAllFeeds()
        #expect(viewModel.errorMessage == "Error")

        // Second call succeeds — error should be cleared
        await failToggle.setShouldFail(false)
        await viewModel.refreshAllFeeds()
        #expect(viewModel.errorMessage == nil)
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
                return nil
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

    @Test("refreshAllFeeds does not call loadUnreadCount — callers are responsible")
    @MainActor
    func refreshAllFeedsDoesNotReloadUnreadCount() async {
        let feed = TestFixtures.makePersistentFeed()
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]

        let article = TestFixtures.makePersistentArticle(articleID: "a1", isRead: false)
        article.feed = feed
        mockPersistence.articlesByFeedID[feed.id] = [article]

        let viewModel = HomeViewModel(
            persistence: mockPersistence,
            refreshFeeds: { return nil }
        )

        // Unread count starts at 0 (not yet loaded)
        #expect(viewModel.unreadCount == 0)
        await viewModel.refreshAllFeeds()
        // refreshAllFeeds does NOT reload unread count — caller must do it
        #expect(viewModel.unreadCount == 0)

        // Caller explicitly reloads
        viewModel.loadUnreadCount()
        #expect(viewModel.unreadCount == 1)
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

    // MARK: - Sort Order

    @Test("sortAscending reads from UserDefaults via shared key")
    @MainActor
    func sortAscendingReadsSharedKey() {
        UserDefaults.standard.removeObject(forKey: FeedViewModel.sortAscendingKey)
        let mockPersistence = MockFeedPersistenceService()
        let viewModel = HomeViewModel(persistence: mockPersistence)

        #expect(viewModel.sortAscending == false)

        viewModel.sortAscending = true
        #expect(viewModel.sortAscending == true)
        #expect(UserDefaults.standard.bool(forKey: FeedViewModel.sortAscendingKey) == true)

        // Clean up
        UserDefaults.standard.removeObject(forKey: FeedViewModel.sortAscendingKey)
    }

    @Test("loadAllArticles respects ascending sort order")
    @MainActor
    func loadAllArticlesAscending() {
        UserDefaults.standard.set(true, forKey: FeedViewModel.sortAscendingKey)
        let feed = TestFixtures.makePersistentFeed()
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

        let viewModel = HomeViewModel(persistence: mockPersistence)
        viewModel.loadAllArticles()

        // Ascending: oldest first
        #expect(viewModel.allArticlesList.first?.articleID == "a1")
        #expect(viewModel.allArticlesList.last?.articleID == "a2")

        // Clean up
        UserDefaults.standard.removeObject(forKey: FeedViewModel.sortAscendingKey)
    }

    @Test("loadUnreadArticles respects ascending sort order")
    @MainActor
    func loadUnreadArticlesAscending() {
        UserDefaults.standard.set(true, forKey: FeedViewModel.sortAscendingKey)
        let feed = TestFixtures.makePersistentFeed()
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]

        let article1 = TestFixtures.makePersistentArticle(
            articleID: "u1",
            publishedDate: Date(timeIntervalSince1970: 1_000_000),
            isRead: false
        )
        article1.feed = feed
        let article2 = TestFixtures.makePersistentArticle(
            articleID: "u2",
            publishedDate: Date(timeIntervalSince1970: 2_000_000),
            isRead: false
        )
        article2.feed = feed
        mockPersistence.articlesByFeedID[feed.id] = [article1, article2]

        let viewModel = HomeViewModel(persistence: mockPersistence)
        viewModel.loadUnreadArticles()

        // Ascending: oldest first
        #expect(viewModel.unreadArticlesList.first?.articleID == "u1")
        #expect(viewModel.unreadArticlesList.last?.articleID == "u2")

        // Clean up
        UserDefaults.standard.removeObject(forKey: FeedViewModel.sortAscendingKey)
    }

    // MARK: - Mark All as Read

    @Test("markAllAsRead marks all articles as read and updates unread count")
    @MainActor
    func markAllAsReadUpdatesState() {
        let feed = TestFixtures.makePersistentFeed()
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]

        let article1 = TestFixtures.makePersistentArticle(articleID: "a1", isRead: false)
        article1.feed = feed
        let article2 = TestFixtures.makePersistentArticle(articleID: "a2", isRead: false)
        article2.feed = feed
        mockPersistence.articlesByFeedID[feed.id] = [article1, article2]

        UserDefaults.standard.removeObject(forKey: FeedViewModel.sortAscendingKey)
        let viewModel = HomeViewModel(persistence: mockPersistence)
        viewModel.loadUnreadCount()
        #expect(viewModel.unreadCount == 2)

        viewModel.loadUnreadArticles()
        #expect(viewModel.unreadArticlesList.count == 2)

        viewModel.markAllAsRead()

        #expect(article1.isRead == true)
        #expect(article2.isRead == true)
        #expect(viewModel.unreadCount == 0)
        #expect(viewModel.unreadArticlesList.isEmpty)
        #expect(viewModel.errorMessage == nil)

        // Clean up
        UserDefaults.standard.removeObject(forKey: FeedViewModel.sortAscendingKey)
    }

    @Test("markAllAsRead sets errorMessage on persistence failure")
    @MainActor
    func markAllAsReadError() {
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.errorToThrow = NSError(domain: "test", code: 1)

        let viewModel = HomeViewModel(persistence: mockPersistence)
        viewModel.markAllAsRead()

        #expect(viewModel.errorMessage != nil)
    }

    @Test("markAllAsRead clears unread articles list")
    @MainActor
    func markAllAsReadClearsUnreadList() {
        let feed = TestFixtures.makePersistentFeed()
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]

        let article = TestFixtures.makePersistentArticle(articleID: "u1", isRead: false)
        article.feed = feed
        mockPersistence.articlesByFeedID[feed.id] = [article]

        UserDefaults.standard.removeObject(forKey: FeedViewModel.sortAscendingKey)
        let viewModel = HomeViewModel(persistence: mockPersistence)
        viewModel.loadUnreadArticles()
        #expect(viewModel.unreadArticlesList.count == 1)

        viewModel.markAllAsRead()

        #expect(viewModel.unreadArticlesList.isEmpty)
        #expect(viewModel.hasMoreUnreadArticles == false)

        // Clean up
        UserDefaults.standard.removeObject(forKey: FeedViewModel.sortAscendingKey)
    }

    @Test("markAllAsRead reloads allArticlesList with updated read state")
    @MainActor
    func markAllAsReadReloadsAllArticlesList() {
        let feed = TestFixtures.makePersistentFeed()
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]

        let article1 = TestFixtures.makePersistentArticle(articleID: "a1", isRead: false)
        article1.feed = feed
        let article2 = TestFixtures.makePersistentArticle(articleID: "a2", isRead: false)
        article2.feed = feed
        mockPersistence.articlesByFeedID[feed.id] = [article1, article2]

        UserDefaults.standard.removeObject(forKey: FeedViewModel.sortAscendingKey)
        let viewModel = HomeViewModel(persistence: mockPersistence)
        viewModel.loadAllArticles()
        #expect(viewModel.allArticlesList.count == 2)

        viewModel.markAllAsRead()

        // allArticlesList should be reloaded (still 2 articles, but now all read)
        #expect(viewModel.allArticlesList.count == 2)
        let allRead = viewModel.allArticlesList.allSatisfy(\.isRead)
        #expect(allRead)

        // Clean up
        UserDefaults.standard.removeObject(forKey: FeedViewModel.sortAscendingKey)
    }

    @Test("sortAscending setter is no-op when set to same value")
    @MainActor
    func sortAscendingSameValueNoOp() {
        UserDefaults.standard.removeObject(forKey: FeedViewModel.sortAscendingKey)
        let mockPersistence = MockFeedPersistenceService()
        let viewModel = HomeViewModel(persistence: mockPersistence)

        #expect(viewModel.sortAscending == false)

        // Set to same value (false) — should not write to UserDefaults
        viewModel.sortAscending = false
        // Verify it's still false (no change)
        #expect(viewModel.sortAscending == false)

        // Now set to true, then set to true again
        viewModel.sortAscending = true
        #expect(viewModel.sortAscending == true)

        viewModel.sortAscending = true
        #expect(viewModel.sortAscending == true)

        // Clean up
        UserDefaults.standard.removeObject(forKey: FeedViewModel.sortAscendingKey)
    }

    // MARK: - Saved Count

    @Test("loadSavedCount returns total saved count")
    @MainActor
    func loadSavedCountSuccess() {
        let feed = TestFixtures.makePersistentFeed()
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]
        let saved = TestFixtures.makePersistentArticle(articleID: "s1", isSaved: true, savedDate: Date())
        saved.feed = feed
        let unsaved = TestFixtures.makePersistentArticle(articleID: "s2", isSaved: false)
        unsaved.feed = feed
        mockPersistence.articlesByFeedID[feed.id] = [saved, unsaved]

        let viewModel = HomeViewModel(persistence: mockPersistence)
        viewModel.loadSavedCount()

        #expect(viewModel.savedCount == 1)
        #expect(viewModel.errorMessage == nil)
    }

    @Test("loadSavedCount sets errorMessage on failure")
    @MainActor
    func loadSavedCountError() {
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.errorToThrow = NSError(domain: "test", code: 1)

        let viewModel = HomeViewModel(persistence: mockPersistence)
        viewModel.loadSavedCount()

        #expect(viewModel.errorMessage != nil)
    }

    @Test("loadSavedCount returns zero when no saved articles")
    @MainActor
    func loadSavedCountEmpty() {
        let mockPersistence = MockFeedPersistenceService()

        let viewModel = HomeViewModel(persistence: mockPersistence)
        viewModel.loadSavedCount()

        #expect(viewModel.savedCount == 0)
        #expect(viewModel.errorMessage == nil)
    }

    // MARK: - Paginated Saved Articles

    @Test("loadSavedArticles loads saved articles into list")
    @MainActor
    func loadSavedArticlesFirstPage() {
        let feed = TestFixtures.makePersistentFeed()
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]

        let saved1 = TestFixtures.makePersistentArticle(
            articleID: "s1",
            isSaved: true,
            savedDate: Date(timeIntervalSince1970: 1_000)
        )
        saved1.feed = feed
        let saved2 = TestFixtures.makePersistentArticle(
            articleID: "s2",
            isSaved: true,
            savedDate: Date(timeIntervalSince1970: 2_000)
        )
        saved2.feed = feed
        let unsaved = TestFixtures.makePersistentArticle(articleID: "u1", isSaved: false)
        unsaved.feed = feed
        mockPersistence.articlesByFeedID[feed.id] = [saved1, saved2, unsaved]

        let viewModel = HomeViewModel(persistence: mockPersistence)
        viewModel.loadSavedArticles()

        #expect(viewModel.savedArticlesList.count == 2)
        #expect(viewModel.hasMoreSavedArticles == false)
        #expect(viewModel.errorMessage == nil)
    }

    @Test("loadSavedArticles returns empty list when no saved articles")
    @MainActor
    func loadSavedArticlesEmpty() {
        let mockPersistence = MockFeedPersistenceService()

        let viewModel = HomeViewModel(persistence: mockPersistence)
        viewModel.loadSavedArticles()

        #expect(viewModel.savedArticlesList.isEmpty)
        #expect(viewModel.hasMoreSavedArticles == false)
        #expect(viewModel.errorMessage == nil)
    }

    @Test("loadSavedArticles sets errorMessage on failure")
    @MainActor
    func loadSavedArticlesError() {
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.errorToThrow = NSError(domain: "test", code: 1)

        let viewModel = HomeViewModel(persistence: mockPersistence)
        viewModel.loadSavedArticles()

        #expect(viewModel.savedArticlesList.isEmpty)
        #expect(viewModel.errorMessage != nil)
        #expect(viewModel.hasMoreSavedArticles == false)
    }

    @Test("loadMoreSavedArticles appends next page")
    @MainActor
    func loadMoreSavedArticlesAppendsPage() {
        let feed = TestFixtures.makePersistentFeed()
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]

        let totalCount = HomeViewModel.pageSize + 3
        let articles = (0..<totalCount).map { i in
            let article = TestFixtures.makePersistentArticle(
                articleID: "s\(i)",
                publishedDate: Date(timeIntervalSince1970: Double(totalCount - i) * 1_000_000),
                isSaved: true,
                savedDate: Date(timeIntervalSince1970: Double(totalCount - i) * 1_000_000)
            )
            article.feed = feed
            return article
        }
        mockPersistence.articlesByFeedID[feed.id] = articles

        let viewModel = HomeViewModel(persistence: mockPersistence)
        viewModel.loadSavedArticles()

        #expect(viewModel.savedArticlesList.count == HomeViewModel.pageSize)
        #expect(viewModel.hasMoreSavedArticles == true)

        viewModel.loadMoreSavedArticles()

        #expect(viewModel.savedArticlesList.count == totalCount)
        #expect(viewModel.hasMoreSavedArticles == false)
    }

    @Test("loadMoreSavedArticles does nothing when no more pages")
    @MainActor
    func loadMoreSavedArticlesNoOp() {
        let mockPersistence = MockFeedPersistenceService()

        let viewModel = HomeViewModel(persistence: mockPersistence)
        viewModel.loadSavedArticles()
        #expect(viewModel.hasMoreSavedArticles == false)

        viewModel.loadMoreSavedArticles()
        #expect(viewModel.savedArticlesList.isEmpty)
    }

    @Test("loadSavedArticles resets list before loading")
    @MainActor
    func loadSavedArticlesResetsState() {
        let feed = TestFixtures.makePersistentFeed()
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]

        let article = TestFixtures.makePersistentArticle(
            articleID: "s1",
            isSaved: true,
            savedDate: Date()
        )
        article.feed = feed
        mockPersistence.articlesByFeedID[feed.id] = [article]

        let viewModel = HomeViewModel(persistence: mockPersistence)
        viewModel.loadSavedArticles()
        #expect(viewModel.savedArticlesList.count == 1)

        // Load again should reset, not duplicate
        viewModel.loadSavedArticles()
        #expect(viewModel.savedArticlesList.count == 1)
    }

    // MARK: - Toggle Saved

    @Test("loadSavedArticles preserves previous list on error")
    @MainActor
    func loadSavedArticlesPreservesOnError() {
        let feed = TestFixtures.makePersistentFeed()
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]

        let article = TestFixtures.makePersistentArticle(
            articleID: "s1",
            isSaved: true,
            savedDate: Date()
        )
        article.feed = feed
        mockPersistence.articlesByFeedID[feed.id] = [article]

        let viewModel = HomeViewModel(persistence: mockPersistence)
        viewModel.loadSavedArticles()
        #expect(viewModel.savedArticlesList.count == 1)

        mockPersistence.errorToThrow = NSError(domain: "test", code: 1)
        viewModel.loadSavedArticles()
        #expect(viewModel.savedArticlesList.count == 1)
        #expect(viewModel.errorMessage != nil)
    }

    @Test("toggleSaved saves an article and updates count")
    @MainActor
    func toggleSavedSavesArticle() {
        let feed = TestFixtures.makePersistentFeed()
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]
        let article = TestFixtures.makePersistentArticle(articleID: "a1", isSaved: false)
        article.feed = feed
        mockPersistence.articlesByFeedID[feed.id] = [article]

        let viewModel = HomeViewModel(persistence: mockPersistence)
        viewModel.loadSavedCount()
        #expect(viewModel.savedCount == 0)

        viewModel.toggleSaved(article)

        #expect(article.isSaved)
        #expect(viewModel.savedCount == 1)
        #expect(viewModel.errorMessage == nil)
    }

    @Test("toggleSaved unsaves a saved article and updates count")
    @MainActor
    func toggleSavedUnsavesArticle() {
        let feed = TestFixtures.makePersistentFeed()
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]
        let article = TestFixtures.makePersistentArticle(
            articleID: "a1",
            isSaved: true,
            savedDate: Date()
        )
        article.feed = feed
        mockPersistence.articlesByFeedID[feed.id] = [article]

        let viewModel = HomeViewModel(persistence: mockPersistence)
        viewModel.loadSavedCount()
        #expect(viewModel.savedCount == 1)

        viewModel.toggleSaved(article)

        #expect(!article.isSaved)
        #expect(viewModel.savedCount == 0)
    }

    @Test("toggleSaved sets errorMessage on failure")
    @MainActor
    func toggleSavedError() {
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.errorToThrow = NSError(domain: "test", code: 1)

        let article = TestFixtures.makePersistentArticle(articleID: "a1")
        let viewModel = HomeViewModel(persistence: mockPersistence)
        viewModel.toggleSaved(article)

        #expect(viewModel.errorMessage != nil)
    }

    // MARK: - Local List Removal

    @Test("removeFromSavedList removes article from savedArticlesList without reloading")
    @MainActor
    func removeFromSavedListRemovesArticle() {
        let feed = TestFixtures.makePersistentFeed()
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]

        let saved1 = TestFixtures.makePersistentArticle(
            articleID: "s1",
            isSaved: true,
            savedDate: Date(timeIntervalSince1970: 1_000)
        )
        saved1.feed = feed
        let saved2 = TestFixtures.makePersistentArticle(
            articleID: "s2",
            isSaved: true,
            savedDate: Date(timeIntervalSince1970: 2_000)
        )
        saved2.feed = feed
        mockPersistence.articlesByFeedID[feed.id] = [saved1, saved2]

        let viewModel = HomeViewModel(persistence: mockPersistence)
        viewModel.loadSavedArticles()
        #expect(viewModel.savedArticlesList.count == 2)

        viewModel.removeFromSavedList(saved1)

        #expect(viewModel.savedArticlesList.count == 1)
        #expect(viewModel.savedArticlesList.first?.articleID == "s2")
    }

    @Test("removeFromSavedList is no-op when article not in list")
    @MainActor
    func removeFromSavedListNoOp() {
        let feed = TestFixtures.makePersistentFeed()
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]

        let saved = TestFixtures.makePersistentArticle(
            articleID: "s1",
            isSaved: true,
            savedDate: Date()
        )
        saved.feed = feed
        mockPersistence.articlesByFeedID[feed.id] = [saved]

        let viewModel = HomeViewModel(persistence: mockPersistence)
        viewModel.loadSavedArticles()
        #expect(viewModel.savedArticlesList.count == 1)

        let notInList = TestFixtures.makePersistentArticle(articleID: "other")
        viewModel.removeFromSavedList(notInList)

        #expect(viewModel.savedArticlesList.count == 1)
    }

    @Test("removeFromSavedList preserves remaining article order")
    @MainActor
    func removeFromSavedListPreservesOrder() {
        let feed = TestFixtures.makePersistentFeed()
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]

        let articles = (0..<5).map { i in
            let article = TestFixtures.makePersistentArticle(
                articleID: "s\(i)",
                isSaved: true,
                savedDate: Date(timeIntervalSince1970: Double(i) * 1_000)
            )
            article.feed = feed
            return article
        }
        mockPersistence.articlesByFeedID[feed.id] = articles

        let viewModel = HomeViewModel(persistence: mockPersistence)
        viewModel.loadSavedArticles()
        #expect(viewModel.savedArticlesList.count == 5)

        // Remove the middle article
        viewModel.removeFromSavedList(articles[2])

        #expect(viewModel.savedArticlesList.count == 4)
        let remainingIDs = viewModel.savedArticlesList.map(\.articleID)
        #expect(remainingIDs == ["s4", "s3", "s1", "s0"])
    }

    // MARK: - Load More And Report

    @Test("loadMoreAllArticlesAndReport returns .loaded when new articles are loaded")
    @MainActor
    func loadMoreAllArticlesAndReportReturnsLoaded() {
        let feed = TestFixtures.makePersistentFeed()
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]

        // Create pageSize + 5 articles to force a second page
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

        let result = viewModel.loadMoreAllArticlesAndReport()

        #expect(result == .loaded)
        #expect(viewModel.allArticlesList.count == totalCount)
    }

    @Test("loadMoreAllArticlesAndReport returns .exhausted when no more articles exist")
    @MainActor
    func loadMoreAllArticlesAndReportReturnsExhausted() {
        let feed = TestFixtures.makePersistentFeed()
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]

        let article = TestFixtures.makePersistentArticle(articleID: "a1")
        article.feed = feed
        mockPersistence.articlesByFeedID[feed.id] = [article]

        let viewModel = HomeViewModel(persistence: mockPersistence)
        viewModel.loadAllArticles()

        #expect(viewModel.allArticlesList.count == 1)
        #expect(viewModel.hasMoreAllArticles == false)

        let result = viewModel.loadMoreAllArticlesAndReport()

        #expect(result == .exhausted)
        #expect(viewModel.allArticlesList.count == 1)
    }

    @Test("loadMoreAllArticlesAndReport returns .failed on persistence error")
    @MainActor
    func loadMoreAllArticlesAndReportReturnsFailed() {
        let feed = TestFixtures.makePersistentFeed()
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]

        // Create enough articles for pagination
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

        #expect(viewModel.hasMoreAllArticles == true)

        // Inject error for the next page load
        mockPersistence.errorToThrow = NSError(domain: "test", code: 1)
        let result = viewModel.loadMoreAllArticlesAndReport()

        #expect(result == .failed("Unable to load all articles."))
        #expect(viewModel.errorMessage != nil)
    }

    @Test("loadMoreUnreadArticlesAndReport returns .loaded when new articles are loaded")
    @MainActor
    func loadMoreUnreadArticlesAndReportReturnsLoaded() {
        let feed = TestFixtures.makePersistentFeed()
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]

        let totalCount = HomeViewModel.pageSize + 5
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

        let result = viewModel.loadMoreUnreadArticlesAndReport()

        #expect(result == .loaded)
        #expect(viewModel.unreadArticlesList.count == totalCount)
    }

    @Test("loadMoreUnreadArticlesAndReport returns .exhausted when no more articles exist")
    @MainActor
    func loadMoreUnreadArticlesAndReportReturnsExhausted() {
        let feed = TestFixtures.makePersistentFeed()
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]

        let article = TestFixtures.makePersistentArticle(articleID: "u1", isRead: false)
        article.feed = feed
        mockPersistence.articlesByFeedID[feed.id] = [article]

        let viewModel = HomeViewModel(persistence: mockPersistence)
        viewModel.loadUnreadArticles()

        #expect(viewModel.unreadArticlesList.count == 1)
        #expect(viewModel.hasMoreUnreadArticles == false)

        let result = viewModel.loadMoreUnreadArticlesAndReport()

        #expect(result == .exhausted)
        #expect(viewModel.unreadArticlesList.count == 1)
    }

    @Test("loadMoreUnreadArticlesAndReport returns .failed on persistence error")
    @MainActor
    func loadMoreUnreadArticlesAndReportReturnsFailed() {
        let feed = TestFixtures.makePersistentFeed()
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]

        let totalCount = HomeViewModel.pageSize + 5
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

        #expect(viewModel.hasMoreUnreadArticles == true)

        mockPersistence.errorToThrow = NSError(domain: "test", code: 1)
        let result = viewModel.loadMoreUnreadArticlesAndReport()

        #expect(result == .failed("Unable to load unread articles."))
        #expect(viewModel.errorMessage != nil)
    }

    @Test("loadMoreSavedArticlesAndReport returns .loaded when new articles are loaded")
    @MainActor
    func loadMoreSavedArticlesAndReportReturnsLoaded() {
        let feed = TestFixtures.makePersistentFeed()
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]

        let totalCount = HomeViewModel.pageSize + 5
        let articles = (0..<totalCount).map { i in
            let article = TestFixtures.makePersistentArticle(
                articleID: "s\(i)",
                isSaved: true,
                savedDate: Date(timeIntervalSince1970: Double(totalCount - i) * 1_000)
            )
            article.feed = feed
            return article
        }
        mockPersistence.articlesByFeedID[feed.id] = articles

        let viewModel = HomeViewModel(persistence: mockPersistence)
        viewModel.loadSavedArticles()

        #expect(viewModel.savedArticlesList.count == HomeViewModel.pageSize)
        #expect(viewModel.hasMoreSavedArticles == true)

        let result = viewModel.loadMoreSavedArticlesAndReport()

        #expect(result == .loaded)
        #expect(viewModel.savedArticlesList.count == totalCount)
    }

    @Test("loadMoreSavedArticlesAndReport returns .exhausted when no more articles exist")
    @MainActor
    func loadMoreSavedArticlesAndReportReturnsExhausted() {
        let feed = TestFixtures.makePersistentFeed()
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]

        let article = TestFixtures.makePersistentArticle(
            articleID: "s1",
            isSaved: true,
            savedDate: Date()
        )
        article.feed = feed
        mockPersistence.articlesByFeedID[feed.id] = [article]

        let viewModel = HomeViewModel(persistence: mockPersistence)
        viewModel.loadSavedArticles()

        #expect(viewModel.savedArticlesList.count == 1)
        #expect(viewModel.hasMoreSavedArticles == false)

        let result = viewModel.loadMoreSavedArticlesAndReport()

        #expect(result == .exhausted)
        #expect(viewModel.savedArticlesList.count == 1)
    }

    @Test("loadMoreSavedArticlesAndReport returns .failed on persistence error")
    @MainActor
    func loadMoreSavedArticlesAndReportReturnsFailed() {
        let feed = TestFixtures.makePersistentFeed()
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]

        let totalCount = HomeViewModel.pageSize + 5
        let articles = (0..<totalCount).map { i in
            let article = TestFixtures.makePersistentArticle(
                articleID: "s\(i)",
                isSaved: true,
                savedDate: Date(timeIntervalSince1970: Double(totalCount - i) * 1_000)
            )
            article.feed = feed
            return article
        }
        mockPersistence.articlesByFeedID[feed.id] = articles

        let viewModel = HomeViewModel(persistence: mockPersistence)
        viewModel.loadSavedArticles()

        #expect(viewModel.hasMoreSavedArticles == true)

        mockPersistence.errorToThrow = NSError(domain: "test", code: 1)
        let result = viewModel.loadMoreSavedArticlesAndReport()

        #expect(result == .failed("Unable to load saved articles."))
        #expect(viewModel.errorMessage != nil)
    }
}
