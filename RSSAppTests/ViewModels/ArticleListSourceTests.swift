import Testing
import Foundation
@testable import RSSApp

/// Sendable toggle counting invocations of the refresh closure injected into
/// `HomeViewModel` for source adapter tests.
private actor RefreshProbe {
    private(set) var callCount = 0
    private(set) var lastError: String?

    func recordCall(returning error: String? = nil) {
        callCount += 1
        lastError = error
    }
}

@Suite("ArticleListSource Adapter Tests")
struct ArticleListSourceTests {

    // MARK: - FeedArticleSource

    /// Guards the reader-push gating contract: `FeedArticleSource.markAsRead` must
    /// forward the underlying `FeedViewModel.markAsRead` Bool return so the
    /// shared view can decide whether to push the reader. Prior to this
    /// refactor the per-feed view swallowed the result and always pushed.
    @Test("FeedArticleSource.markAsRead returns false on persistence failure")
    @MainActor
    func feedArticleSourceMarkAsReadForwardsFailure() {
        let feed = TestFixtures.makePersistentFeed()
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.errorToThrow = NSError(domain: "test", code: 1)

        let article = TestFixtures.makePersistentArticle(articleID: "a1", isRead: false)
        article.feed = feed

        let viewModel = FeedViewModel(
            feed: feed,
            feedFetching: MockFeedFetchingService(),
            persistence: mockPersistence
        )
        let source = FeedArticleSource(viewModel: viewModel)

        let result = source.markAsRead(article)
        #expect(result == false)
        #expect(article.isRead == false)
        #expect(source.errorMessage != nil)
    }

    @Test("FeedArticleSource.markAsRead returns true for already-read article")
    @MainActor
    func feedArticleSourceMarkAsReadAlreadyRead() {
        let feed = TestFixtures.makePersistentFeed()
        let mockPersistence = MockFeedPersistenceService()

        let article = TestFixtures.makePersistentArticle(articleID: "a1", isRead: true)
        article.feed = feed

        let viewModel = FeedViewModel(
            feed: feed,
            feedFetching: MockFeedFetchingService(),
            persistence: mockPersistence
        )
        let source = FeedArticleSource(viewModel: viewModel)

        let result = source.markAsRead(article)
        #expect(result == true)
    }

    @Test("FeedArticleSource.markAsRead returns true on successful mutation")
    @MainActor
    func feedArticleSourceMarkAsReadSuccess() {
        let feed = TestFixtures.makePersistentFeed()
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]

        let article = TestFixtures.makePersistentArticle(articleID: "a1", isRead: false)
        article.feed = feed
        mockPersistence.articlesByFeedID[feed.id] = [article]

        let viewModel = FeedViewModel(
            feed: feed,
            feedFetching: MockFeedFetchingService(),
            persistence: mockPersistence
        )
        let source = FeedArticleSource(viewModel: viewModel)

        let result = source.markAsRead(article)
        #expect(result == true)
        #expect(article.isRead == true)
    }

    // MARK: - Cross-feed initialLoad triggers refresh

    /// Core invariant: entering a cross-feed list should trigger a network
    /// refresh of all feeds — cache-first + refresh + reload. Prior to this
    /// refactor the cross-feed views only did a local SwiftData query on
    /// entry, leaving stale data until the user manually pulled to refresh.
    @Test("AllArticlesSource.initialLoad triggers refresh closure on first entry")
    @MainActor
    func allArticlesSourceInitialLoadTriggersRefresh() async {
        // Clear any ambient throttle timestamp from other tests so this
        // asserts the "first entry" path unambiguously.
        UserDefaults.standard.removeObject(forKey: FeedRefreshService.lastRefreshCompletedKey)

        let probe = RefreshProbe()
        let mockPersistence = MockFeedPersistenceService()
        let feed = TestFixtures.makePersistentFeed()
        mockPersistence.feeds = [feed]

        let article = TestFixtures.makePersistentArticle(articleID: "a1")
        article.feed = feed
        mockPersistence.articlesByFeedID[feed.id] = [article]

        let viewModel = HomeViewModel(
            persistence: mockPersistence,
            refreshFeeds: {
                await probe.recordCall()
                return nil
            }
        )
        let source = AllArticlesSource(homeViewModel: viewModel)

        await source.initialLoad()

        #expect(await probe.callCount == 1)
        #expect(source.articles.count == 1)
    }

    @Test("UnreadArticlesSource.initialLoad triggers refresh closure on first entry")
    @MainActor
    func unreadArticlesSourceInitialLoadTriggersRefresh() async {
        UserDefaults.standard.removeObject(forKey: FeedRefreshService.lastRefreshCompletedKey)

        let probe = RefreshProbe()
        let mockPersistence = MockFeedPersistenceService()
        let feed = TestFixtures.makePersistentFeed()
        mockPersistence.feeds = [feed]

        let article = TestFixtures.makePersistentArticle(articleID: "a1", isRead: false)
        article.feed = feed
        mockPersistence.articlesByFeedID[feed.id] = [article]

        let viewModel = HomeViewModel(
            persistence: mockPersistence,
            refreshFeeds: {
                await probe.recordCall()
                return nil
            }
        )
        let source = UnreadArticlesSource(homeViewModel: viewModel)

        await source.initialLoad()

        #expect(await probe.callCount == 1)
        #expect(source.articles.count == 1)
    }

    // MARK: - Snapshot stability on mutations

    /// Per the snapshot-stable rule, unsaving an article from the Saved list
    /// must update the article's `isSaved` flag but NOT drop the row from
    /// `savedArticlesList`. The prior behavior (removeFromSavedList) yanked
    /// rows immediately, which the user explicitly wanted changed — see the
    /// "remove the visual flag but keep it in the list" example in the
    /// refactor discussion.
    @Test("SavedArticlesSource.toggleSaved keeps the article in the list")
    @MainActor
    func savedArticlesSourceToggleSavedKeepsArticle() {
        UserDefaults.standard.removeObject(forKey: FeedViewModel.sortAscendingKey)
        defer { UserDefaults.standard.removeObject(forKey: FeedViewModel.sortAscendingKey) }

        let feed = TestFixtures.makePersistentFeed()
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]

        let saved = TestFixtures.makePersistentArticle(
            articleID: "s1",
            publishedDate: Date(timeIntervalSince1970: 2_000_000),
            isSaved: true,
            savedDate: Date(timeIntervalSince1970: 2_000_000)
        )
        saved.feed = feed
        mockPersistence.articlesByFeedID[feed.id] = [saved]

        let viewModel = HomeViewModel(persistence: mockPersistence)
        let source = SavedArticlesSource(homeViewModel: viewModel)

        viewModel.loadSavedArticles()
        #expect(source.articles.count == 1)

        source.toggleSaved(saved)

        // Row stays visible — isSaved is now false but the article is still
        // in the list snapshot. It drops out only when the user triggers an
        // explicit refresh (pull-to-refresh, leave the view and return).
        #expect(source.articles.count == 1)
        #expect(saved.isSaved == false)
    }

    /// Snapshot stability for mark-all-as-read. The Unread list must not
    /// empty out when the user taps Mark All as Read; it must stay populated
    /// with the (now read-styled) rows until an explicit refresh. The
    /// `HomeViewModel`-level test already pins this at the view model layer;
    /// this test asserts the adapter forwards the same guarantee.
    @Test("UnreadArticlesSource.markAllAsRead preserves the list snapshot")
    @MainActor
    func unreadArticlesSourceMarkAllAsReadPreservesSnapshot() {
        UserDefaults.standard.removeObject(forKey: FeedViewModel.sortAscendingKey)
        defer { UserDefaults.standard.removeObject(forKey: FeedViewModel.sortAscendingKey) }

        let feed = TestFixtures.makePersistentFeed()
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]

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

        let viewModel = HomeViewModel(persistence: mockPersistence)
        let source = UnreadArticlesSource(homeViewModel: viewModel)

        viewModel.loadUnreadArticles()
        #expect(source.articles.count == 2)

        source.markAllAsRead()

        #expect(source.articles.count == 2)
        #expect(source.articles.allSatisfy { $0.isRead })
    }

    // MARK: - Refresh throttling on list entry

    /// Follow-up to cross-feed refresh: rapid navigation across sibling cross-feed lists (or
    /// re-entry within the throttle window) must NOT stack redundant network
    /// refreshes. Seeds the shared `FeedRefreshService.lastRefreshCompletedKey`
    /// UserDefaults entry to "just now" and then asserts `initialLoad()` does
    /// not call the refresh closure.
    @Test("AllArticlesSource.initialLoad skips refresh when within throttle window")
    @MainActor
    func allArticlesSourceInitialLoadThrottled() async {
        UserDefaults.standard.set(
            Date().timeIntervalSince1970,
            forKey: FeedRefreshService.lastRefreshCompletedKey
        )
        defer { UserDefaults.standard.removeObject(forKey: FeedRefreshService.lastRefreshCompletedKey) }

        let probe = RefreshProbe()
        let mockPersistence = MockFeedPersistenceService()
        let feed = TestFixtures.makePersistentFeed()
        mockPersistence.feeds = [feed]
        let article = TestFixtures.makePersistentArticle(articleID: "a1")
        article.feed = feed
        mockPersistence.articlesByFeedID[feed.id] = [article]

        let viewModel = HomeViewModel(
            persistence: mockPersistence,
            refreshFeeds: {
                await probe.recordCall()
                return nil
            }
        )
        let source = AllArticlesSource(homeViewModel: viewModel)

        await source.initialLoad()

        #expect(await probe.callCount == 0)
        // Local snapshot is still populated even though the refresh was
        // skipped — the user should see cached data immediately.
        #expect(source.articles.count == 1)
    }

    /// When the throttle key is stale (older than the interval), the refresh
    /// should fire. Verifies the "fresh on entry" behavior is preserved when
    /// enough time has passed since the last refresh.
    @Test("AllArticlesSource.initialLoad refreshes when throttle window has elapsed")
    @MainActor
    func allArticlesSourceInitialLoadRefreshesWhenStale() async {
        let tenMinutesAgo = Date().addingTimeInterval(-600).timeIntervalSince1970
        UserDefaults.standard.set(tenMinutesAgo, forKey: FeedRefreshService.lastRefreshCompletedKey)
        defer { UserDefaults.standard.removeObject(forKey: FeedRefreshService.lastRefreshCompletedKey) }

        let probe = RefreshProbe()
        let mockPersistence = MockFeedPersistenceService()
        let feed = TestFixtures.makePersistentFeed()
        mockPersistence.feeds = [feed]

        let viewModel = HomeViewModel(
            persistence: mockPersistence,
            refreshFeeds: {
                await probe.recordCall()
                return nil
            }
        )
        let source = AllArticlesSource(homeViewModel: viewModel)

        await source.initialLoad()

        #expect(await probe.callCount == 1)
    }

    // MARK: - SavedArticlesSource does not refresh on entry

    /// Saved articles never benefit from a network refresh. `initialLoad`
    /// must not call `refreshAllFeeds()` regardless of throttle state, and
    /// pull-to-refresh (`refresh()`) is also a local-only re-query.
    @Test("SavedArticlesSource.initialLoad never triggers network refresh")
    @MainActor
    func savedArticlesSourceInitialLoadNeverRefreshes() async {
        // Clear any ambient throttle state so this is the unambiguous case.
        UserDefaults.standard.removeObject(forKey: FeedRefreshService.lastRefreshCompletedKey)

        let probe = RefreshProbe()
        let mockPersistence = MockFeedPersistenceService()
        let feed = TestFixtures.makePersistentFeed()
        mockPersistence.feeds = [feed]

        let saved = TestFixtures.makePersistentArticle(articleID: "s1", isSaved: true, savedDate: Date())
        saved.feed = feed
        mockPersistence.articlesByFeedID[feed.id] = [saved]

        let viewModel = HomeViewModel(
            persistence: mockPersistence,
            refreshFeeds: {
                await probe.recordCall()
                return nil
            }
        )
        let source = SavedArticlesSource(homeViewModel: viewModel)

        await source.initialLoad()
        #expect(await probe.callCount == 0)
        #expect(source.articles.count == 1)

        await source.refresh()
        #expect(await probe.callCount == 0)
    }

    // MARK: - Scoped mark-all-as-read

    /// `SavedArticlesSource.markAllAsRead` must only touch saved articles
    /// — previously it called the global `markAllArticlesRead()` path,
    /// which marked every article in every feed as read when the user
    /// tapped the affordance from the Saved list.
    @Test("SavedArticlesSource.markAllAsRead only marks saved articles as read")
    @MainActor
    func savedArticlesSourceMarkAllAsReadScoped() {
        UserDefaults.standard.removeObject(forKey: FeedViewModel.sortAscendingKey)
        defer { UserDefaults.standard.removeObject(forKey: FeedViewModel.sortAscendingKey) }

        let feed = TestFixtures.makePersistentFeed()
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]

        let saved = TestFixtures.makePersistentArticle(
            articleID: "saved",
            publishedDate: Date(timeIntervalSince1970: 2_000_000),
            isRead: false,
            isSaved: true,
            savedDate: Date(timeIntervalSince1970: 2_000_000)
        )
        saved.feed = feed
        let unsavedUnread = TestFixtures.makePersistentArticle(
            articleID: "unsavedUnread",
            publishedDate: Date(timeIntervalSince1970: 1_000_000),
            isRead: false,
            isSaved: false
        )
        unsavedUnread.feed = feed
        mockPersistence.articlesByFeedID[feed.id] = [saved, unsavedUnread]

        let viewModel = HomeViewModel(persistence: mockPersistence)
        let source = SavedArticlesSource(homeViewModel: viewModel)

        viewModel.loadSavedArticles()
        #expect(source.articles.count == 1)

        source.markAllAsRead()

        // Saved article is marked read. Non-saved, unread article is
        // untouched — the prior global behavior would have marked it too.
        #expect(saved.isRead == true)
        #expect(unsavedUnread.isRead == false)

        // Snapshot-stable: the row remains in the Saved list snapshot.
        #expect(source.articles.count == 1)
    }

    // MARK: - initialLoad sets hasAppeared ordering (covered at view level)

    // RATIONALE: The `hasAppeared = true` before await ordering in
    // `ArticleListScreen.task` is a view-level invariant (#209) that cannot
    // be exercised from a pure view-model test without a production-code
    // test seam. Per CLAUDE.md's "test seams in production code are a smell"
    // rule, we do not add one here — regression risk is mitigated by having
    // the two-gate pattern centralized in a single location (the shared
    // view) rather than duplicated across four list views.
}
