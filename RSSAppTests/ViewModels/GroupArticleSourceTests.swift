import Testing
import Foundation
@testable import RSSApp

@Suite("GroupArticleSource Tests")
struct GroupArticleSourceTests {

    // MARK: - Helpers

    @MainActor
    private static func makeFixture(
        articleCount: Int = 3,
        feedCount: Int = 1,
        readCount: Int = 0
    ) -> (source: GroupArticleSource, mock: MockFeedPersistenceService, group: PersistentFeedGroup, defaults: UserDefaults) {
        let mock = MockFeedPersistenceService()
        let group = PersistentFeedGroup(name: "Test Group")
        mock.groups = [group]

        var feeds: [PersistentFeed] = []
        for i in 0..<feedCount {
            let feed = TestFixtures.makePersistentFeed(
                id: UUID(),
                title: "Feed \(i)",
                feedURL: URL(string: "https://example.com/feed\(i)")!
            )
            feeds.append(feed)
            mock.feeds.append(feed)
            mock.memberships.append(PersistentFeedGroupMembership(feed: feed, group: group))

            var articles: [PersistentArticle] = []
            for j in 0..<articleCount {
                let sortDate = Date(timeIntervalSince1970: Double(1_000_000 - (i * articleCount + j) * 100))
                let globalIndex = i * articleCount + j
                let article = TestFixtures.makePersistentArticle(
                    articleID: "feed\(i)-article\(j)",
                    isRead: globalIndex < readCount,
                    sortDate: sortDate
                )
                article.feed = feed
                articles.append(article)
            }
            mock.articlesByFeedID[feed.id] = articles
        }

        // Use an isolated UserDefaults suite so sort/filter state changes in one test
        // do not bleed into other tests running in parallel on different suites.
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let homeVM = HomeViewModel(persistence: mock, userDefaults: defaults)
        let source = GroupArticleSource(group: group, persistence: mock, homeViewModel: homeVM, userDefaults: defaults)
        return (source, mock, group, defaults)
    }

    // MARK: - Display configuration

    @Test("title returns group name")
    @MainActor
    func titleIsGroupName() {
        let (source, _, _, _) = Self.makeFixture()
        #expect(source.title == "Test Group")
    }

    @Test("supportsSort is true, supportsUnreadFilter is true")
    @MainActor
    func displayConfiguration() {
        let (source, _, _, _) = Self.makeFixture()
        #expect(source.supportsSort == true)
        #expect(source.supportsUnreadFilter == true)
    }

    // MARK: - reload

    @Test("reload loads articles from group feeds")
    @MainActor
    func reloadLoadsArticles() {
        let (source, _, _, _) = Self.makeFixture(articleCount: 3, feedCount: 2)
        source.reload()

        #expect(source.articles.count == 6)
    }

    @Test("reload with empty group returns no articles")
    @MainActor
    func reloadEmptyGroup() {
        let mock = MockFeedPersistenceService()
        let group = PersistentFeedGroup(name: "Empty")
        mock.groups = [group]

        let homeVM = HomeViewModel(persistence: mock)
        let source = GroupArticleSource(group: group, persistence: mock, homeViewModel: homeVM)
        source.reload()

        #expect(source.articles.isEmpty)
    }

    // MARK: - Multi-page cursor progression

    @Test("loadMoreAndReport advances cursor across pages with no duplicates")
    @MainActor
    func multiPageCursorProgression() {
        // 60 articles across 2 feeds (30 each) exceeds pageSize (50), spanning 2 pages.
        let (source, _, _, _) = Self.makeFixture(articleCount: 30, feedCount: 2)
        source.reload()

        let firstPageCount = source.articles.count
        #expect(firstPageCount == 50)
        #expect(source.hasMore == true)

        let result = source.loadMoreAndReport()
        #expect(result == .loaded)

        let totalCount = source.articles.count
        #expect(totalCount == 60)
        #expect(source.hasMore == false)

        // Verify no duplicates
        let ids = source.articles.map(\.articleID)
        #expect(Set(ids).count == ids.count)
    }

    // MARK: - Mutations

    @Test("markAsRead delegates to homeViewModel and returns true")
    @MainActor
    func markAsReadDelegates() {
        let (source, _, _, _) = Self.makeFixture()
        source.reload()

        let article = source.articles[0]
        let result = source.markAsRead(article)

        #expect(result == true)
        #expect(article.isRead == true)
    }

    @Test("toggleReadStatus toggles article read state")
    @MainActor
    func toggleReadStatus() {
        let (source, _, _, _) = Self.makeFixture()
        source.reload()

        let article = source.articles[0]
        #expect(article.isRead == false)

        source.toggleReadStatus(article)
        #expect(article.isRead == true)

        source.toggleReadStatus(article)
        #expect(article.isRead == false)
    }

    @Test("toggleSaved toggles article saved state")
    @MainActor
    func toggleSaved() {
        let (source, _, _, _) = Self.makeFixture()
        source.reload()

        let article = source.articles[0]
        #expect(article.isSaved == false)

        source.toggleSaved(article)
        #expect(article.isSaved == true)
    }

    @Test("markAllAsRead marks only group articles")
    @MainActor
    func markAllAsReadScoped() {
        let mock = MockFeedPersistenceService()
        let group = PersistentFeedGroup(name: "Scoped")
        mock.groups = [group]

        let feedIn = TestFixtures.makePersistentFeed(id: UUID(), title: "In Group")
        let feedOut = TestFixtures.makePersistentFeed(id: UUID(), title: "Outside")
        mock.feeds = [feedIn, feedOut]
        mock.memberships = [PersistentFeedGroupMembership(feed: feedIn, group: group)]

        let articleIn = TestFixtures.makePersistentArticle(articleID: "in1", isRead: false)
        articleIn.feed = feedIn
        let articleOut = TestFixtures.makePersistentArticle(articleID: "out1", isRead: false)
        articleOut.feed = feedOut
        mock.articlesByFeedID[feedIn.id] = [articleIn]
        mock.articlesByFeedID[feedOut.id] = [articleOut]

        let homeVM = HomeViewModel(persistence: mock)
        let source = GroupArticleSource(group: group, persistence: mock, homeViewModel: homeVM)
        source.markAllAsRead()

        #expect(articleIn.isRead == true)
        #expect(articleOut.isRead == false)
    }

    // MARK: - Error handling

    @Test("reload preserves previous articles on error")
    @MainActor
    func reloadPreservesOnError() {
        let (source, mock, _, _) = Self.makeFixture(articleCount: 2)
        source.reload()
        #expect(source.articles.count == 2)

        mock.groupError = NSError(domain: "test", code: 1)
        source.reload()

        #expect(source.articles.count == 2)
        #expect(source.errorMessage != nil)
    }

    @Test("reload preserves cursor on error so loadMore can resume")
    @MainActor
    func reloadPreservesCursorOnError() {
        // Load enough articles to leave hasMore true (page size is 50, load 60).
        let (source, mock, _, _) = Self.makeFixture(articleCount: 30, feedCount: 2)
        source.reload()
        #expect(source.articles.count == 50)

        // Simulate error on reload — cursor and articles should be preserved.
        mock.groupError = NSError(domain: "test", code: 1)
        source.reload()
        #expect(source.articles.count == 50)

        // Clear error and load more — should pick up from where we left off.
        mock.groupError = nil
        let result = source.loadMoreAndReport()
        #expect(result == .loaded)
        #expect(source.articles.count == 60)
    }

    @Test("clearError clears errorMessage")
    @MainActor
    func clearError() {
        let (source, mock, _, _) = Self.makeFixture()
        mock.groupError = NSError(domain: "test", code: 1)
        source.reload()
        #expect(source.errorMessage != nil)

        source.clearError()
        #expect(source.errorMessage == nil)
    }

    // MARK: - Sort

    @Test("sortAscending toggle reloads articles in new order")
    @MainActor
    func sortAscendingToggle() {
        let (source, _, _, _) = Self.makeFixture(articleCount: 3)
        source.reload()

        let firstDescending = source.articles.first?.articleID

        source.sortAscending = true
        let firstAscending = source.articles.first?.articleID

        #expect(firstDescending != firstAscending)
    }

    // MARK: - Unread filter

    @Test("showUnreadOnly filters to unread articles only")
    @MainActor
    func showUnreadOnlyFilters() {
        // 3 articles, first 1 is read, remaining 2 are unread.
        let (source, _, _, _) = Self.makeFixture(articleCount: 3, readCount: 1)
        source.reload()
        #expect(source.articles.count == 3)

        source.showUnreadOnly = true
        #expect(source.articles.count == 2)
        #expect(source.articles.allSatisfy { !$0.isRead })
    }

    @Test("showUnreadOnly persists to UserDefaults")
    @MainActor
    func showUnreadOnlyPersistsToDefaults() {
        let (source, _, _, defaults) = Self.makeFixture()

        #expect(defaults.bool(forKey: Settings.UserDefaultsKeys.showUnreadOnly) == false)
        source.showUnreadOnly = true
        #expect(defaults.bool(forKey: Settings.UserDefaultsKeys.showUnreadOnly) == true)
        source.showUnreadOnly = false
        #expect(defaults.bool(forKey: Settings.UserDefaultsKeys.showUnreadOnly) == false)
    }

    @Test("showUnreadOnly reads from the global UserDefaults key")
    @MainActor
    func showUnreadOnlyReadsFromDefaults() {
        let (source, _, _, defaults) = Self.makeFixture()
        #expect(source.showUnreadOnly == false)

        defaults.set(true, forKey: Settings.UserDefaultsKeys.showUnreadOnly)
        #expect(source.showUnreadOnly == true)
    }

    @Test("showUnreadOnly toggling to same value is a no-op")
    @MainActor
    func showUnreadOnlyNoOpOnSameValue() {
        let (source, _, _, _) = Self.makeFixture(articleCount: 3, readCount: 1)
        source.reload()
        let countBefore = source.articles.count

        // Setting the same value (false → false) must not reload.
        source.showUnreadOnly = false
        #expect(source.articles.count == countBefore)
    }

    @Test("showUnreadOnly stable: marking article read does not remove it from the list")
    @MainActor
    func showUnreadOnlyStableList() {
        // 3 unread articles.
        let (source, _, _, _) = Self.makeFixture(articleCount: 3, readCount: 0)
        source.reload()
        source.showUnreadOnly = true
        #expect(source.articles.count == 3)

        // Marking an article read (snapshot-stable mutation) must NOT shrink the list.
        let article = source.articles[0]
        source.markAsRead(article)

        #expect(article.isRead == true)
        #expect(source.articles.count == 3)
    }

    @Test("showUnreadOnly: toggling off shows all articles including newly read ones")
    @MainActor
    func showUnreadOnlyToggleOffShowsAll() {
        // 3 articles, 2 unread.
        let (source, _, _, _) = Self.makeFixture(articleCount: 3, readCount: 1)
        source.showUnreadOnly = true
        source.reload()
        #expect(source.articles.count == 2)

        // Toggle off re-queries the full set.
        source.showUnreadOnly = false
        #expect(source.articles.count == 3)
    }

    @Test("showUnreadOnly with paginated group fetches only unread across pages")
    @MainActor
    func showUnreadOnlyPaginated() {
        // 120 articles across 2 feeds (60 each), first 10 are read, 110 unread — well exceeds pageSize.
        let (source, _, _, _) = Self.makeFixture(articleCount: 60, feedCount: 2, readCount: 10)
        source.showUnreadOnly = true
        source.reload()

        let firstPageCount = source.articles.count
        // First page: 50 unread articles (pageSize).
        #expect(firstPageCount == 50)
        #expect(source.hasMore == true)
        #expect(source.articles.allSatisfy { !$0.isRead })

        let result = source.loadMoreAndReport()
        // Second page has more unread articles (110 - 50 = 60 remain).
        #expect(result == .loaded)
        #expect(source.articles.count == 100)
        #expect(source.hasMore == true)
        #expect(source.articles.allSatisfy { !$0.isRead })

        // No duplicates.
        let ids = source.articles.map(\.articleID)
        #expect(Set(ids).count == ids.count)
    }
}
