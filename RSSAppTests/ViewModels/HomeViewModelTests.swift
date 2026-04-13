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

        let viewModel = HomeViewModel(persistence: mockPersistence, userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
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

        let viewModel = HomeViewModel(persistence: mockPersistence, userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
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

        let viewModel = HomeViewModel(persistence: mockPersistence, userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
        viewModel.loadUnreadCount()

        #expect(viewModel.unreadCount == 0)
        #expect(viewModel.errorMessage == nil)
    }

    // MARK: - Empty Database

    @Test("loadAllArticles returns empty list when no articles exist")
    @MainActor
    func loadAllArticlesEmpty() {
        let mockPersistence = MockFeedPersistenceService()

        let viewModel = HomeViewModel(persistence: mockPersistence, userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
        viewModel.loadAllArticles()

        #expect(viewModel.allArticlesList.isEmpty)
        #expect(viewModel.hasMoreAllArticles == false)
        #expect(viewModel.errorMessage == nil)
    }

    @Test("loadUnreadArticles returns empty list when no articles exist")
    @MainActor
    func loadUnreadArticlesEmpty() {
        let mockPersistence = MockFeedPersistenceService()

        let viewModel = HomeViewModel(persistence: mockPersistence, userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
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

        let viewModel = HomeViewModel(persistence: mockPersistence, userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
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

        let viewModel = HomeViewModel(persistence: mockPersistence, userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
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

        let viewModel = HomeViewModel(persistence: mockPersistence, userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
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

        let viewModel = HomeViewModel(persistence: mockPersistence, userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
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

        let viewModel = HomeViewModel(persistence: mockPersistence, userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
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

        let viewModel = HomeViewModel(persistence: mockPersistence, userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
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

        let viewModel = HomeViewModel(persistence: mockPersistence, userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
        viewModel.loadUnreadArticles()
        #expect(viewModel.hasMoreUnreadArticles == false)

        viewModel.loadMoreUnreadArticles()
        #expect(viewModel.unreadArticlesList.isEmpty)
    }

    @Test("loadUnreadArticles sets errorMessage on failure and preserves hasMore for retry")
    @MainActor
    func loadUnreadArticlesPaginatedError() {
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.errorToThrow = NSError(domain: "test", code: 1)

        let viewModel = HomeViewModel(persistence: mockPersistence, userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
        viewModel.loadUnreadArticles()

        #expect(viewModel.unreadArticlesList.isEmpty)
        #expect(viewModel.errorMessage != nil)
        // hasMore preserved so the user can retry
        #expect(viewModel.hasMoreUnreadArticles == true)
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

        let viewModel = HomeViewModel(persistence: mockPersistence, userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
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

        let viewModel = HomeViewModel(persistence: mockPersistence, userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
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

        let viewModel = HomeViewModel(persistence: mockPersistence, userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
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

        let viewModel = HomeViewModel(persistence: mockPersistence, userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
        viewModel.loadUnreadArticles()
        #expect(viewModel.unreadArticlesList.count == 1)

        mockPersistence.errorToThrow = NSError(domain: "test", code: 1)
        viewModel.loadUnreadArticles()
        #expect(viewModel.unreadArticlesList.count == 1)
        #expect(viewModel.errorMessage != nil)
    }

    @Test("loadAllArticles error preserves hasMoreAllArticles for retry")
    @MainActor
    func loadAllArticlesErrorPreservesHasMore() {
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.errorToThrow = NSError(domain: "test", code: 1)

        let viewModel = HomeViewModel(persistence: mockPersistence, userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
        viewModel.loadAllArticles()

        // hasMore preserved so the user can retry
        #expect(viewModel.hasMoreAllArticles == true)
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

        let viewModel = HomeViewModel(persistence: mockPersistence, userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
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

        let viewModel = HomeViewModel(persistence: mockPersistence, userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
        viewModel.loadAllArticles()

        let idsBefore = viewModel.allArticlesList.map(\.articleID)
        #expect(idsBefore.count == 2)

        viewModel.toggleReadStatus(article1)
        #expect(article1.isRead == true)
        #expect(viewModel.allArticlesList.map(\.articleID) == idsBefore)
    }

    @Test("mark as read during simulated reader session leaves saved list snapshot intact")
    @MainActor
    func readerSessionPreservesSavedListSnapshot() {
        let feed = TestFixtures.makePersistentFeed()
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]

        // Use an isolated UserDefaults suite so sort state does not bleed across
        // tests. The saved list honors the sort toggle (sorted by sortDate with
        // the stored direction), so a stale pref from another test would flip ordering.
        let defaults = UserDefaults(suiteName: UUID().uuidString)!

        // Three saved articles, one already read, two unread. publishedDate is
        // used as the authoritative sort key under the new ordering (sortDate
        // descending by default). Expected order after load: s1 (newest), s2,
        // s3 (oldest).
        let saved1 = TestFixtures.makePersistentArticle(
            articleID: "s1",
            publishedDate: Date(timeIntervalSince1970: 3_000_000),
            isRead: false,
            isSaved: true,
            savedDate: Date(timeIntervalSince1970: 3_000_000)
        )
        saved1.feed = feed
        let saved2 = TestFixtures.makePersistentArticle(
            articleID: "s2",
            publishedDate: Date(timeIntervalSince1970: 2_000_000),
            isRead: false,
            isSaved: true,
            savedDate: Date(timeIntervalSince1970: 2_000_000)
        )
        saved2.feed = feed
        let saved3 = TestFixtures.makePersistentArticle(
            articleID: "s3",
            publishedDate: Date(timeIntervalSince1970: 1_000_000),
            isRead: true,
            isSaved: true,
            savedDate: Date(timeIntervalSince1970: 1_000_000)
        )
        saved3.feed = feed
        mockPersistence.articlesByFeedID[feed.id] = [saved1, saved2, saved3]

        let viewModel = HomeViewModel(persistence: mockPersistence, userDefaults: defaults)
        viewModel.loadSavedArticles()
        let expectedOrder = ["s1", "s2", "s3"]
        #expect(viewModel.savedArticlesList.map(\.articleID) == expectedOrder)

        // Simulate tapping saved1: view model marks it as read before pushing the reader.
        let opened = viewModel.markAsRead(saved1)
        #expect(opened == true)
        #expect(saved1.isRead == true)

        // Simulate the reader paging forward and marking saved2 as read via its own
        // markArticleRead path (bypasses HomeViewModel's snapshot preservation helpers).
        try? mockPersistence.markArticleRead(saved2, isRead: true)
        #expect(saved2.isRead == true)

        // Returning from the reader must NOT change the saved list — saved articles
        // are independent of read state but pagination depth/scroll position must be
        // preserved across the reader push/pop too.
        #expect(viewModel.savedArticlesList.map(\.articleID) == expectedOrder)

        // Explicit reload still keeps all three (read state does not exclude saved).
        viewModel.loadSavedArticles()
        #expect(viewModel.savedArticlesList.map(\.articleID) == expectedOrder)
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

        let viewModel = HomeViewModel(persistence: mockPersistence, userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
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

    /// Regression test for #209. Covers the `HomeViewModel` half of the contract:
    /// `markAsRead` (and direct `markArticleRead` calls bypassing the view model)
    /// must mutate persistence without re-querying `unreadArticlesList`, so the
    /// snapshot stays intact for the duration of a "reader session" — until the
    /// view explicitly calls `loadUnreadArticles()` again. The view-layer
    /// suppression that prevents the post-pop `onAppear` from triggering that
    /// explicit reload is exercised manually (it cannot be tested at the view
    /// model layer in isolation).
    @Test("mark as read during simulated reader session leaves unread list snapshot intact")
    @MainActor
    func readerSessionPreservesUnreadListSnapshot() {
        let feed = TestFixtures.makePersistentFeed()
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]

        // Three unread articles with strictly distinct publish dates so sort order
        // is unambiguous (newest first). Expected order after load: u1, u2, u3.
        let article1 = TestFixtures.makePersistentArticle(
            articleID: "u1",
            publishedDate: Date(timeIntervalSince1970: 3_000_000),
            isRead: false
        )
        article1.feed = feed
        let article2 = TestFixtures.makePersistentArticle(
            articleID: "u2",
            publishedDate: Date(timeIntervalSince1970: 2_000_000),
            isRead: false
        )
        article2.feed = feed
        let article3 = TestFixtures.makePersistentArticle(
            articleID: "u3",
            publishedDate: Date(timeIntervalSince1970: 1_000_000),
            isRead: false
        )
        article3.feed = feed
        mockPersistence.articlesByFeedID[feed.id] = [article1, article2, article3]

        let viewModel = HomeViewModel(persistence: mockPersistence, userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
        viewModel.loadUnreadArticles()
        let expectedOrder = ["u1", "u2", "u3"]
        #expect(viewModel.unreadArticlesList.map(\.articleID) == expectedOrder)

        // Simulate tapping article 1: view model marks it as read before pushing the reader.
        let opened = viewModel.markAsRead(article1)
        #expect(opened == true)
        #expect(article1.isRead == true)

        // Simulate the reader paging forward and marking article 2 as read via its own
        // markArticleRead path (bypasses HomeViewModel's snapshot preservation helpers).
        try? mockPersistence.markArticleRead(article2, isRead: true)
        #expect(article2.isRead == true)

        // Returning from the reader must NOT drop the now-read articles from the list —
        // the view suppresses its post-reader onAppear reload so the snapshot is stable.
        // Compare against the explicit expected order, not just the captured snapshot,
        // so a regression that scrambles ordering still trips this assertion.
        #expect(viewModel.unreadArticlesList.map(\.articleID) == expectedOrder)

        // And the unread *count* still reflects reality for the badge/home dots.
        viewModel.loadUnreadCount()
        #expect(viewModel.unreadCount == 1)
    }

    /// Inverse of `readerSessionPreservesUnreadListSnapshot`: once the user genuinely
    /// leaves and returns — or pulls to refresh — an explicit `loadUnreadArticles()`
    /// call must drop the read articles. This proves the regression fix did not
    /// reintroduce the inverse problem of stale snapshots persisting forever.
    @Test("explicit reload after reader session drops articles marked read in the reader")
    @MainActor
    func explicitReloadAfterReaderSessionDropsReadArticles() {
        let (viewModel, mockPersistence, article1, article2, _) = Self.makeUnreadSnapshotFixture()
        viewModel.loadUnreadArticles()
        #expect(viewModel.unreadArticlesList.count == 2)

        // Simulate reader session: mark both articles as read.
        _ = viewModel.markAsRead(article1)
        try? mockPersistence.markArticleRead(article2, isRead: true)

        // Post-reader return leaves the snapshot stable (see test above).
        #expect(viewModel.unreadArticlesList.count == 2)

        // Explicit reload (tab change, pull-to-refresh, sort toggle) drops them.
        viewModel.loadUnreadArticles()
        #expect(viewModel.unreadArticlesList.isEmpty)
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

        let viewModel = HomeViewModel(persistence: mockPersistence, userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
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

        let viewModel = HomeViewModel(persistence: mockPersistence, userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
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

        let viewModel = HomeViewModel(persistence: mockPersistence, userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
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

        let viewModel = HomeViewModel(persistence: mockPersistence, userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
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

        let viewModel = HomeViewModel(persistence: mockPersistence, userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
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

        let viewModel = HomeViewModel(persistence: mockPersistence, userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
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
            userDefaults: UserDefaults(suiteName: UUID().uuidString)!,
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
        let viewModel = HomeViewModel(persistence: mockPersistence, userDefaults: UserDefaults(suiteName: UUID().uuidString)!)

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
            userDefaults: UserDefaults(suiteName: UUID().uuidString)!,
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
            userDefaults: UserDefaults(suiteName: UUID().uuidString)!,
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
            userDefaults: UserDefaults(suiteName: UUID().uuidString)!,
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
            userDefaults: UserDefaults(suiteName: UUID().uuidString)!,
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
            userDefaults: UserDefaults(suiteName: UUID().uuidString)!,
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

        let viewModel = HomeViewModel(persistence: mockPersistence, userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
        viewModel.loadUnreadCount()
        #expect(viewModel.errorMessage != nil)

        viewModel.clearError()

        #expect(viewModel.errorMessage == nil)
    }

    // MARK: - Sort Order

    @Test("sortAscending reads and writes through the injected UserDefaults instance")
    @MainActor
    func sortAscendingReadsSharedKey() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let mockPersistence = MockFeedPersistenceService()
        let viewModel = HomeViewModel(persistence: mockPersistence, userDefaults: defaults)

        #expect(viewModel.sortAscending == false)

        viewModel.sortAscending = true
        #expect(viewModel.sortAscending == true)
        #expect(defaults.bool(forKey: FeedViewModel.sortAscendingKey) == true)
    }

    @Test("loadAllArticles respects ascending sort order")
    @MainActor
    func loadAllArticlesAscending() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set(true, forKey: FeedViewModel.sortAscendingKey)
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

        let viewModel = HomeViewModel(persistence: mockPersistence, userDefaults: defaults)
        viewModel.loadAllArticles()

        // Ascending: oldest first
        #expect(viewModel.allArticlesList.first?.articleID == "a1")
        #expect(viewModel.allArticlesList.last?.articleID == "a2")
    }

    @Test("loadUnreadArticles respects ascending sort order")
    @MainActor
    func loadUnreadArticlesAscending() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set(true, forKey: FeedViewModel.sortAscendingKey)
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

        let viewModel = HomeViewModel(persistence: mockPersistence, userDefaults: defaults)
        viewModel.loadUnreadArticles()

        // Ascending: oldest first
        #expect(viewModel.unreadArticlesList.first?.articleID == "u1")
        #expect(viewModel.unreadArticlesList.last?.articleID == "u2")
    }

    @Test("loadSavedArticles respects ascending sort order")
    @MainActor
    func loadSavedArticlesAscending() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set(true, forKey: FeedViewModel.sortAscendingKey)
        let feed = TestFixtures.makePersistentFeed()
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]

        let article1 = TestFixtures.makePersistentArticle(
            articleID: "s1",
            publishedDate: Date(timeIntervalSince1970: 1_000_000),
            isSaved: true,
            savedDate: Date(timeIntervalSince1970: 2_000_000)
        )
        article1.feed = feed
        let article2 = TestFixtures.makePersistentArticle(
            articleID: "s2",
            publishedDate: Date(timeIntervalSince1970: 2_000_000),
            isSaved: true,
            savedDate: Date(timeIntervalSince1970: 1_000_000)
        )
        article2.feed = feed
        mockPersistence.articlesByFeedID[feed.id] = [article1, article2]

        let viewModel = HomeViewModel(persistence: mockPersistence, userDefaults: defaults)
        viewModel.loadSavedArticles()

        // Ascending: oldest sortDate first. savedDate is deliberately inverted
        // relative to publishedDate so the test validates sorting by sortDate
        // (derived from publishedDate), not savedDate.
        #expect(viewModel.savedArticlesList.first?.articleID == "s1")
        #expect(viewModel.savedArticlesList.last?.articleID == "s2")
    }

    // MARK: - shouldRefreshOnEntry throttle

    @Test("shouldRefreshOnEntry returns true when no refresh has ever completed")
    @MainActor
    func shouldRefreshOnEntryNeverRefreshed() {
        UserDefaults.standard.removeObject(forKey: FeedRefreshService.lastRefreshCompletedKey)
        let viewModel = HomeViewModel(persistence: MockFeedPersistenceService(), userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
        #expect(viewModel.shouldRefreshOnEntry == true)
    }

    @Test("shouldRefreshOnEntry returns false when refresh is within throttle window")
    @MainActor
    func shouldRefreshOnEntryWithinWindow() {
        UserDefaults.standard.set(
            Date().timeIntervalSince1970,
            forKey: FeedRefreshService.lastRefreshCompletedKey
        )
        defer { UserDefaults.standard.removeObject(forKey: FeedRefreshService.lastRefreshCompletedKey) }

        let viewModel = HomeViewModel(persistence: MockFeedPersistenceService(), userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
        #expect(viewModel.shouldRefreshOnEntry == false)
    }

    @Test("shouldRefreshOnEntry returns true when refresh is older than throttle window")
    @MainActor
    func shouldRefreshOnEntryOutsideWindow() {
        let sixMinutesAgo = Date().addingTimeInterval(-(6 * 60))
        UserDefaults.standard.set(
            sixMinutesAgo.timeIntervalSince1970,
            forKey: FeedRefreshService.lastRefreshCompletedKey
        )
        defer { UserDefaults.standard.removeObject(forKey: FeedRefreshService.lastRefreshCompletedKey) }

        let viewModel = HomeViewModel(persistence: MockFeedPersistenceService(), userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
        #expect(viewModel.shouldRefreshOnEntry == true)
    }

    // MARK: - Scoped mark-all-as-read for saved articles

    @Test("markAllSavedArticlesRead marks only saved articles and leaves others unread")
    @MainActor
    func markAllSavedArticlesReadScoped() {
        let feed = TestFixtures.makePersistentFeed()
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]

        let savedUnread = TestFixtures.makePersistentArticle(
            articleID: "s1",
            isRead: false,
            isSaved: true,
            savedDate: Date()
        )
        savedUnread.feed = feed
        let notSavedUnread = TestFixtures.makePersistentArticle(
            articleID: "n1",
            isRead: false,
            isSaved: false
        )
        notSavedUnread.feed = feed
        mockPersistence.articlesByFeedID[feed.id] = [savedUnread, notSavedUnread]

        let viewModel = HomeViewModel(persistence: mockPersistence, userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
        viewModel.loadUnreadCount()
        #expect(viewModel.unreadCount == 2)

        viewModel.markAllSavedArticlesRead()

        #expect(savedUnread.isRead == true)
        #expect(notSavedUnread.isRead == false)
        // Unread count reflects the scoped mutation — one unread remains.
        #expect(viewModel.unreadCount == 1)
        #expect(viewModel.errorMessage == nil)
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

        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let viewModel = HomeViewModel(persistence: mockPersistence, userDefaults: defaults)
        viewModel.loadUnreadCount()
        #expect(viewModel.unreadCount == 2)

        viewModel.loadUnreadArticles()
        #expect(viewModel.unreadArticlesList.count == 2)

        viewModel.markAllAsRead()

        #expect(article1.isRead == true)
        #expect(article2.isRead == true)
        #expect(viewModel.unreadCount == 0)
        // Snapshot-stable rule: markAllAsRead updates row visuals (isRead) but
        // does NOT re-query the unread list. The rows remain visible until the
        // user triggers an explicit refresh.
        #expect(viewModel.unreadArticlesList.count == 2)
        #expect(viewModel.unreadArticlesList.allSatisfy { $0.isRead })
        #expect(viewModel.errorMessage == nil)
    }

    @Test("markAllAsRead sets errorMessage on persistence failure")
    @MainActor
    func markAllAsReadError() {
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.errorToThrow = NSError(domain: "test", code: 1)

        let viewModel = HomeViewModel(persistence: mockPersistence, userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
        viewModel.markAllAsRead()

        #expect(viewModel.errorMessage != nil)
    }

    @Test("markAllAsRead preserves unread articles list snapshot (snapshot-stable rule)")
    @MainActor
    func markAllAsReadPreservesUnreadList() {
        let feed = TestFixtures.makePersistentFeed()
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]

        let article = TestFixtures.makePersistentArticle(articleID: "u1", isRead: false)
        article.feed = feed
        mockPersistence.articlesByFeedID[feed.id] = [article]

        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let viewModel = HomeViewModel(persistence: mockPersistence, userDefaults: defaults)
        viewModel.loadUnreadArticles()
        #expect(viewModel.unreadArticlesList.count == 1)

        viewModel.markAllAsRead()

        // Snapshot-stable rule: the list is NOT re-queried. The item stays
        // visible with isRead == true; the user can refresh to re-query.
        #expect(viewModel.unreadArticlesList.count == 1)
        #expect(viewModel.unreadArticlesList.first?.isRead == true)
    }

    @Test("markAllAsRead updates isRead on allArticlesList items without reloading")
    @MainActor
    func markAllAsReadMutatesAllArticlesListInPlace() {
        let feed = TestFixtures.makePersistentFeed()
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]

        let article1 = TestFixtures.makePersistentArticle(articleID: "a1", isRead: false)
        article1.feed = feed
        let article2 = TestFixtures.makePersistentArticle(articleID: "a2", isRead: false)
        article2.feed = feed
        mockPersistence.articlesByFeedID[feed.id] = [article1, article2]

        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let viewModel = HomeViewModel(persistence: mockPersistence, userDefaults: defaults)
        viewModel.loadAllArticles()
        #expect(viewModel.allArticlesList.count == 2)

        viewModel.markAllAsRead()

        // Snapshot-stable rule: the list is NOT re-queried. The row visuals
        // update because the same PersistentArticle references are mutated
        // in place by the persistence layer's bulk mark-read operation.
        #expect(viewModel.allArticlesList.count == 2)
        #expect(viewModel.allArticlesList.allSatisfy { $0.isRead })
    }

    @Test("sortAscending setter is no-op when set to same value")
    @MainActor
    func sortAscendingSameValueNoOp() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let mockPersistence = MockFeedPersistenceService()
        let viewModel = HomeViewModel(persistence: mockPersistence, userDefaults: defaults)

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

        let viewModel = HomeViewModel(persistence: mockPersistence, userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
        viewModel.loadSavedArticles()

        #expect(viewModel.savedArticlesList.count == 2)
        #expect(viewModel.hasMoreSavedArticles == false)
        #expect(viewModel.errorMessage == nil)
    }

    @Test("loadSavedArticles returns empty list when no saved articles")
    @MainActor
    func loadSavedArticlesEmpty() {
        let mockPersistence = MockFeedPersistenceService()

        let viewModel = HomeViewModel(persistence: mockPersistence, userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
        viewModel.loadSavedArticles()

        #expect(viewModel.savedArticlesList.isEmpty)
        #expect(viewModel.hasMoreSavedArticles == false)
        #expect(viewModel.errorMessage == nil)
    }

    @Test("loadSavedArticles sets errorMessage on failure and preserves hasMore for retry")
    @MainActor
    func loadSavedArticlesError() {
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.errorToThrow = NSError(domain: "test", code: 1)

        let viewModel = HomeViewModel(persistence: mockPersistence, userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
        viewModel.loadSavedArticles()

        #expect(viewModel.savedArticlesList.isEmpty)
        #expect(viewModel.errorMessage != nil)
        // hasMore preserved so the user can retry
        #expect(viewModel.hasMoreSavedArticles == true)
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

        let viewModel = HomeViewModel(persistence: mockPersistence, userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
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

        let viewModel = HomeViewModel(persistence: mockPersistence, userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
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

        let viewModel = HomeViewModel(persistence: mockPersistence, userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
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

        let viewModel = HomeViewModel(persistence: mockPersistence, userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
        viewModel.loadSavedArticles()
        #expect(viewModel.savedArticlesList.count == 1)

        mockPersistence.errorToThrow = NSError(domain: "test", code: 1)
        viewModel.loadSavedArticles()
        #expect(viewModel.savedArticlesList.count == 1)
        #expect(viewModel.errorMessage != nil)
    }

    @Test("toggleSaved saves an article")
    @MainActor
    func toggleSavedSavesArticle() {
        let feed = TestFixtures.makePersistentFeed()
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]
        let article = TestFixtures.makePersistentArticle(articleID: "a1", isSaved: false)
        article.feed = feed
        mockPersistence.articlesByFeedID[feed.id] = [article]

        let viewModel = HomeViewModel(persistence: mockPersistence, userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
        viewModel.toggleSaved(article)

        #expect(article.isSaved)
        #expect(viewModel.errorMessage == nil)
    }

    @Test("toggleSaved unsaves a saved article")
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

        let viewModel = HomeViewModel(persistence: mockPersistence, userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
        viewModel.toggleSaved(article)

        #expect(!article.isSaved)
    }

    @Test("toggleSaved sets errorMessage on failure")
    @MainActor
    func toggleSavedError() {
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.errorToThrow = NSError(domain: "test", code: 1)

        let article = TestFixtures.makePersistentArticle(articleID: "a1")
        let viewModel = HomeViewModel(persistence: mockPersistence, userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
        viewModel.toggleSaved(article)

        #expect(viewModel.errorMessage != nil)
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

        let viewModel = HomeViewModel(persistence: mockPersistence, userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
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

        let viewModel = HomeViewModel(persistence: mockPersistence, userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
        viewModel.loadAllArticles()

        #expect(viewModel.allArticlesList.count == 1)
        #expect(viewModel.hasMoreAllArticles == false)

        let result = viewModel.loadMoreAllArticlesAndReport()

        #expect(result == .exhausted)
        #expect(viewModel.allArticlesList.count == 1)
    }

    @Test("loadMoreAllArticlesAndReport returns .failed on persistence error and preserves hasMore for retry")
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

        let viewModel = HomeViewModel(persistence: mockPersistence, userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
        viewModel.loadAllArticles()

        #expect(viewModel.hasMoreAllArticles == true)

        // Inject error for the next page load
        mockPersistence.errorToThrow = NSError(domain: "test", code: 1)
        let result = viewModel.loadMoreAllArticlesAndReport()

        #expect(result == .failed("Unable to load all articles."))
        // hasMore preserved so the user can retry
        #expect(viewModel.hasMoreAllArticles == true)
        // loadMoreAllArticlesAndReport clears errorMessage so only the article reader shows the error
        #expect(viewModel.errorMessage == nil)
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

        let viewModel = HomeViewModel(persistence: mockPersistence, userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
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

        let viewModel = HomeViewModel(persistence: mockPersistence, userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
        viewModel.loadUnreadArticles()

        #expect(viewModel.unreadArticlesList.count == 1)
        #expect(viewModel.hasMoreUnreadArticles == false)

        let result = viewModel.loadMoreUnreadArticlesAndReport()

        #expect(result == .exhausted)
        #expect(viewModel.unreadArticlesList.count == 1)
    }

    @Test("loadMoreUnreadArticlesAndReport returns .failed on persistence error and preserves hasMore for retry")
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

        let viewModel = HomeViewModel(persistence: mockPersistence, userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
        viewModel.loadUnreadArticles()

        #expect(viewModel.hasMoreUnreadArticles == true)

        mockPersistence.errorToThrow = NSError(domain: "test", code: 1)
        let result = viewModel.loadMoreUnreadArticlesAndReport()

        #expect(result == .failed("Unable to load unread articles."))
        // hasMore preserved so the user can retry
        #expect(viewModel.hasMoreUnreadArticles == true)
        // loadMoreUnreadArticlesAndReport clears errorMessage so only the article reader shows the error
        #expect(viewModel.errorMessage == nil)
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

        let viewModel = HomeViewModel(persistence: mockPersistence, userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
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

        let viewModel = HomeViewModel(persistence: mockPersistence, userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
        viewModel.loadSavedArticles()

        #expect(viewModel.savedArticlesList.count == 1)
        #expect(viewModel.hasMoreSavedArticles == false)

        let result = viewModel.loadMoreSavedArticlesAndReport()

        #expect(result == .exhausted)
        #expect(viewModel.savedArticlesList.count == 1)
    }

    @Test("loadMoreSavedArticlesAndReport returns .failed on persistence error and preserves hasMore for retry")
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

        let viewModel = HomeViewModel(persistence: mockPersistence, userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
        viewModel.loadSavedArticles()

        #expect(viewModel.hasMoreSavedArticles == true)

        mockPersistence.errorToThrow = NSError(domain: "test", code: 1)
        let result = viewModel.loadMoreSavedArticlesAndReport()

        #expect(result == .failed("Unable to load saved articles."))
        // hasMore preserved so the user can retry
        #expect(viewModel.hasMoreSavedArticles == true)
        // loadMoreSavedArticlesAndReport clears errorMessage so only the article reader shows the error
        #expect(viewModel.errorMessage == nil)
    }

    // MARK: - Retry After Transient Error

    @Test("loadMoreAllArticles succeeds on retry after transient error")
    @MainActor
    func loadMoreAllArticlesRetryAfterError() {
        let feed = TestFixtures.makePersistentFeed()
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]

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

        let viewModel = HomeViewModel(persistence: mockPersistence, userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
        viewModel.loadAllArticles()

        #expect(viewModel.hasMoreAllArticles == true)
        let countBeforeError = viewModel.allArticlesList.count

        // First attempt fails
        mockPersistence.errorToThrow = NSError(domain: "test", code: 1)
        let failedResult = viewModel.loadMoreAllArticles()
        #expect(failedResult == .failed("Unable to load all articles."))
        #expect(viewModel.hasMoreAllArticles == true)
        #expect(viewModel.allArticlesList.count == countBeforeError)

        // Clear error and retry succeeds
        mockPersistence.errorToThrow = nil
        let retryResult = viewModel.loadMoreAllArticles()
        #expect(retryResult == .loaded)
        #expect(viewModel.allArticlesList.count > countBeforeError)
    }

    // MARK: - Article Identity Stability

    /// Regression guard for #256. `ArticleReaderView` observes the displayed article's
    /// `articleID` (`.onChange(of: article.articleID)`) to drive both extraction reset
    /// and mark-as-read. That makes `articleID` stability across `loadAllArticles()`
    /// load-bearing: if a reload produced different `articleID` values for the same
    /// logical entries, the reader would fire spurious `.onChange` events and could
    /// mark the wrong articles as read.
    ///
    /// This variant pre-populates persistence with `pageSize` all-articles entries and
    /// asserts the first-page `articleID` prefix is unchanged after a subsequent
    /// `loadAllArticles()` reload.
    @Test("loadAllArticles preserves articleID prefix on reload")
    @MainActor
    func loadAllArticlesPreservesArticleIDPrefixOnReload() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let feed = TestFixtures.makePersistentFeed()
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]

        // pageSize + 5 articles in descending publishedDate order so the first page
        // is deterministic under the default newest-first sort.
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

        let viewModel = HomeViewModel(persistence: mockPersistence, userDefaults: defaults)
        viewModel.loadAllArticles()

        #expect(viewModel.allArticlesList.count == HomeViewModel.pageSize)
        let prefixBefore = viewModel.allArticlesList.map(\.articleID)

        viewModel.loadAllArticles()

        let prefixAfter = Array(viewModel.allArticlesList.prefix(HomeViewModel.pageSize)).map(\.articleID)
        #expect(prefixAfter == prefixBefore, "loadAllArticles must preserve articleID identity for the previously loaded prefix")
    }

    /// Regression guard for #256. Companion to `loadAllArticlesPreservesArticleIDPrefixOnReload`:
    /// when `loadMoreAllArticlesAndReport()` returns `.loaded`, the previously loaded prefix must
    /// keep stable `articleID` values even though new entries are appended.
    @Test("loadMoreAllArticlesAndReport preserves articleID for previously loaded prefix")
    @MainActor
    func loadMoreAllArticlesAndReportPreservesArticleIDPrefix() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let feed = TestFixtures.makePersistentFeed()
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]

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

        let viewModel = HomeViewModel(persistence: mockPersistence, userDefaults: defaults)
        viewModel.loadAllArticles()

        #expect(viewModel.allArticlesList.count == HomeViewModel.pageSize)
        let prefixBefore = viewModel.allArticlesList.map(\.articleID)

        let result = viewModel.loadMoreAllArticlesAndReport()
        #expect(result == .loaded)
        #expect(viewModel.allArticlesList.count == totalCount)

        let prefixAfter = Array(viewModel.allArticlesList.prefix(HomeViewModel.pageSize)).map(\.articleID)
        #expect(prefixAfter == prefixBefore, "loadMoreAllArticlesAndReport must preserve articleID identity for the previously loaded prefix")
    }

    /// Regression guard for #256. Mirrors the all-articles variant for the unread pathway.
    /// `ArticleReaderView` is presented from `ArticleListScreen` (via `UnreadArticlesSource`)
    /// and observes `articleID` for the same load-bearing reasons.
    @Test("loadUnreadArticles preserves articleID prefix on reload")
    @MainActor
    func loadUnreadArticlesPreservesArticleIDPrefixOnReload() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
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

        let viewModel = HomeViewModel(persistence: mockPersistence, userDefaults: defaults)
        viewModel.loadUnreadArticles()

        #expect(viewModel.unreadArticlesList.count == HomeViewModel.pageSize)
        let prefixBefore = viewModel.unreadArticlesList.map(\.articleID)

        viewModel.loadUnreadArticles()

        let prefixAfter = Array(viewModel.unreadArticlesList.prefix(HomeViewModel.pageSize)).map(\.articleID)
        #expect(prefixAfter == prefixBefore, "loadUnreadArticles must preserve articleID identity for the previously loaded prefix")

    }

    /// Regression guard for #256. Companion to `loadUnreadArticlesPreservesArticleIDPrefixOnReload`:
    /// when `loadMoreUnreadArticlesAndReport()` returns `.loaded`, the previously loaded prefix must
    /// keep stable `articleID` values even though new entries are appended.
    @Test("loadMoreUnreadArticlesAndReport preserves articleID for previously loaded prefix")
    @MainActor
    func loadMoreUnreadArticlesAndReportPreservesArticleIDPrefix() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
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

        let viewModel = HomeViewModel(persistence: mockPersistence, userDefaults: defaults)
        viewModel.loadUnreadArticles()

        #expect(viewModel.unreadArticlesList.count == HomeViewModel.pageSize)
        let prefixBefore = viewModel.unreadArticlesList.map(\.articleID)

        let result = viewModel.loadMoreUnreadArticlesAndReport()
        #expect(result == .loaded)
        #expect(viewModel.unreadArticlesList.count == totalCount)

        let prefixAfter = Array(viewModel.unreadArticlesList.prefix(HomeViewModel.pageSize)).map(\.articleID)
        #expect(prefixAfter == prefixBefore, "loadMoreUnreadArticlesAndReport must preserve articleID identity for the previously loaded prefix")
    }

    /// Regression guard for #256. Mirrors the all-articles variant for the saved-articles pathway.
    /// `ArticleReaderView` is presented from `ArticleListScreen` (via `SavedArticlesSource`)
    /// and observes `articleID` for the same load-bearing reasons.
    @Test("loadSavedArticles preserves articleID prefix on reload")
    @MainActor
    func loadSavedArticlesPreservesArticleIDPrefixOnReload() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let feed = TestFixtures.makePersistentFeed()
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]

        let totalCount = HomeViewModel.pageSize + 5
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

        let viewModel = HomeViewModel(persistence: mockPersistence, userDefaults: defaults)
        viewModel.loadSavedArticles()

        #expect(viewModel.savedArticlesList.count == HomeViewModel.pageSize)
        let prefixBefore = viewModel.savedArticlesList.map(\.articleID)

        viewModel.loadSavedArticles()

        let prefixAfter = Array(viewModel.savedArticlesList.prefix(HomeViewModel.pageSize)).map(\.articleID)
        #expect(prefixAfter == prefixBefore, "loadSavedArticles must preserve articleID identity for the previously loaded prefix")
    }

    /// Regression guard for #256. Companion to `loadSavedArticlesPreservesArticleIDPrefixOnReload`:
    /// when `loadMoreSavedArticlesAndReport()` returns `.loaded`, the previously loaded prefix must
    /// keep stable `articleID` values even though new entries are appended.
    @Test("loadMoreSavedArticlesAndReport preserves articleID for previously loaded prefix")
    @MainActor
    func loadMoreSavedArticlesAndReportPreservesArticleIDPrefix() {
        let feed = TestFixtures.makePersistentFeed()
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]

        let totalCount = HomeViewModel.pageSize + 5
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

        let viewModel = HomeViewModel(persistence: mockPersistence, userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
        viewModel.loadSavedArticles()

        #expect(viewModel.savedArticlesList.count == HomeViewModel.pageSize)
        let prefixBefore = viewModel.savedArticlesList.map(\.articleID)

        let result = viewModel.loadMoreSavedArticlesAndReport()
        #expect(result == .loaded)
        #expect(viewModel.savedArticlesList.count == totalCount)

        let prefixAfter = Array(viewModel.savedArticlesList.prefix(HomeViewModel.pageSize)).map(\.articleID)
        #expect(prefixAfter == prefixBefore, "loadMoreSavedArticlesAndReport must preserve articleID identity for the previously loaded prefix")
    }

    // MARK: - Feed failure indicator

    @Test("hasFeedsWithLongRunningFailure is false when no feeds have errors")
    @MainActor
    func feedFailureIndicatorFalseWhenNoErrors() {
        let feed = TestFixtures.makePersistentFeed()
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]

        let viewModel = HomeViewModel(persistence: mockPersistence, userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
        viewModel.loadUnreadCount()

        #expect(viewModel.hasFeedsWithLongRunningFailure == false)
    }

    @Test("hasFeedsWithLongRunningFailure is false when failure streak is below threshold")
    @MainActor
    func feedFailureIndicatorFalseWhenStreakBelowThreshold() {
        // 12 hours into a streak — below the 24-hour bubble-up threshold
        let feed = TestFixtures.makePersistentFeed(
            lastFetchError: "HTTP 503",
            firstFetchErrorDate: Date(timeIntervalSinceNow: -(12 * 3600))
        )
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]

        let viewModel = HomeViewModel(persistence: mockPersistence, userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
        viewModel.loadUnreadCount()

        #expect(viewModel.hasFeedsWithLongRunningFailure == false)
    }

    @Test("hasFeedsWithLongRunningFailure is true when any feed exceeds the 24-hour threshold")
    @MainActor
    func feedFailureIndicatorTrueWhenStreakExceedsThreshold() {
        let healthyFeed = TestFixtures.makePersistentFeed(title: "Healthy", feedURL: URL(string: "https://healthy.com/feed")!)
        let brokenFeed = TestFixtures.makePersistentFeed(
            title: "Broken",
            feedURL: URL(string: "https://broken.com/feed")!,
            lastFetchError: "HTTP 404",
            firstFetchErrorDate: Date(timeIntervalSinceNow: -(FeedRefreshService.bubbleUpThreshold + 3600))
        )
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [healthyFeed, brokenFeed]

        let viewModel = HomeViewModel(persistence: mockPersistence, userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
        viewModel.loadUnreadCount()

        #expect(viewModel.hasFeedsWithLongRunningFailure == true)
    }
}
