import Testing
import Foundation
@testable import RSSApp

@Suite("GroupArticleSource Tests")
struct GroupArticleSourceTests {

    // MARK: - Helpers

    @MainActor
    private static func makeFixture(
        articleCount: Int = 3,
        feedCount: Int = 1
    ) -> (source: GroupArticleSource, mock: MockFeedPersistenceService, group: PersistentFeedGroup) {
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
                let article = TestFixtures.makePersistentArticle(
                    articleID: "feed\(i)-article\(j)",
                    isRead: false,
                    sortDate: sortDate
                )
                article.feed = feed
                articles.append(article)
            }
            mock.articlesByFeedID[feed.id] = articles
        }

        let homeVM = HomeViewModel(persistence: mock)
        let source = GroupArticleSource(group: group, persistence: mock, homeViewModel: homeVM)
        return (source, mock, group)
    }

    // MARK: - Display configuration

    @Test("title returns group name")
    @MainActor
    func titleIsGroupName() {
        let (source, _, _) = Self.makeFixture()
        #expect(source.title == "Test Group")
    }

    @Test("supportsSort is true, supportsUnreadFilter is false")
    @MainActor
    func displayConfiguration() {
        let (source, _, _) = Self.makeFixture()
        #expect(source.supportsSort == true)
        #expect(source.supportsUnreadFilter == false)
    }

    // MARK: - reload

    @Test("reload loads articles from group feeds")
    @MainActor
    func reloadLoadsArticles() {
        let (source, _, _) = Self.makeFixture(articleCount: 3, feedCount: 2)
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
        let (source, _, _) = Self.makeFixture(articleCount: 30, feedCount: 2)
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
        let (source, _, _) = Self.makeFixture()
        source.reload()

        let article = source.articles[0]
        let result = source.markAsRead(article)

        #expect(result == true)
        #expect(article.isRead == true)
    }

    @Test("toggleReadStatus toggles article read state")
    @MainActor
    func toggleReadStatus() {
        let (source, _, _) = Self.makeFixture()
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
        let (source, _, _) = Self.makeFixture()
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
        let (source, mock, _) = Self.makeFixture(articleCount: 2)
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
        let (source, mock, _) = Self.makeFixture(articleCount: 30, feedCount: 2)
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
        let (source, mock, _) = Self.makeFixture()
        mock.groupError = NSError(domain: "test", code: 1)
        source.reload()
        #expect(source.errorMessage != nil)

        source.clearError()
        #expect(source.errorMessage == nil)
    }

    // MARK: - Group deletion

    @Test("deleteGroup() success sets wasGroupDeleted and removes group from persistence")
    @MainActor
    func deleteGroupSuccess() {
        let (source, mock, group) = Self.makeFixture()
        source.deleteGroup()

        #expect(source.wasGroupDeleted == true)
        #expect(source.deleteErrorMessage == nil)
        #expect(!mock.groups.contains { $0.id == group.id })
    }

    @Test("deleteGroup() failure sets deleteErrorMessage and leaves wasGroupDeleted false")
    @MainActor
    func deleteGroupFailure() {
        let (source, mock, _) = Self.makeFixture()
        mock.groupError = NSError(domain: "test", code: 1)
        source.deleteGroup()

        #expect(source.wasGroupDeleted == false)
        #expect(source.deleteErrorMessage != nil)
    }

    // MARK: - Sort

    @Test("sortAscending toggle reloads articles in new order")
    @MainActor
    func sortAscendingToggle() {
        let (source, _, _) = Self.makeFixture(articleCount: 3)
        source.reload()

        let firstDescending = source.articles.first?.articleID

        source.sortAscending = true
        let firstAscending = source.articles.first?.articleID

        #expect(firstDescending != firstAscending)
    }
}
