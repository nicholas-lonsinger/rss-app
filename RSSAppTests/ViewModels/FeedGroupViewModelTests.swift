import Testing
import Foundation
@testable import RSSApp

@Suite("FeedGroupViewModel Tests")
struct FeedGroupViewModelTests {

    // MARK: - Loading

    @Test("loadArticles returns articles for group's feeds")
    @MainActor
    func loadArticlesReturnsGroupArticles() {
        let mock = MockFeedPersistenceService()
        let group = TestFixtures.makePersistentFeedGroup(name: "Tech")
        let feed = TestFixtures.makePersistentFeed(title: "Tech Blog")
        feed.group = group
        mock.feeds = [feed]

        let article = TestFixtures.makePersistentArticle(articleID: "a1")
        article.feed = feed
        mock.articlesByFeedID[feed.id] = [article]

        let vm = FeedGroupViewModel(group: group, persistence: mock)
        vm.loadArticles()

        #expect(vm.articles.count == 1)
        #expect(vm.articles.first?.articleID == "a1")
        #expect(vm.errorMessage == nil)
    }

    @Test("loadArticles excludes articles from feeds not in group")
    @MainActor
    func loadArticlesExcludesOtherFeeds() {
        let mock = MockFeedPersistenceService()
        let group = TestFixtures.makePersistentFeedGroup(name: "Tech")
        let inGroupFeed = TestFixtures.makePersistentFeed(title: "In Group")
        inGroupFeed.group = group
        let outsideFeed = TestFixtures.makePersistentFeed(
            id: UUID(),
            title: "Outside",
            feedURL: URL(string: "https://other.com/feed")!
        )
        mock.feeds = [inGroupFeed, outsideFeed]

        let inArticle = TestFixtures.makePersistentArticle(articleID: "in")
        inArticle.feed = inGroupFeed
        let outArticle = TestFixtures.makePersistentArticle(articleID: "out")
        outArticle.feed = outsideFeed
        mock.articlesByFeedID[inGroupFeed.id] = [inArticle]
        mock.articlesByFeedID[outsideFeed.id] = [outArticle]

        let vm = FeedGroupViewModel(group: group, persistence: mock)
        vm.loadArticles()

        #expect(vm.articles.count == 1)
        #expect(vm.articles.first?.articleID == "in")
    }

    @Test("loadArticles preserves previous list on error")
    @MainActor
    func loadArticlesPreservesOnError() {
        let mock = MockFeedPersistenceService()
        let group = TestFixtures.makePersistentFeedGroup(name: "Tech")
        let feed = TestFixtures.makePersistentFeed()
        feed.group = group
        mock.feeds = [feed]

        let article = TestFixtures.makePersistentArticle(articleID: "a1")
        article.feed = feed
        mock.articlesByFeedID[feed.id] = [article]

        let vm = FeedGroupViewModel(group: group, persistence: mock)
        vm.loadArticles()
        #expect(vm.articles.count == 1)

        mock.groupError = NSError(domain: "test", code: 1)
        vm.loadArticles()

        #expect(vm.articles.count == 1)
        #expect(vm.errorMessage != nil)
    }

    // MARK: - Pagination

    @Test("loadMoreArticles appends and deduplicates")
    @MainActor
    func loadMoreDeduplicates() {
        let mock = MockFeedPersistenceService()
        let group = TestFixtures.makePersistentFeedGroup(name: "Tech")
        let feed = TestFixtures.makePersistentFeed()
        feed.group = group
        mock.feeds = [feed]

        // Create enough articles to fill a page (pageSize=50) plus one more
        var articles: [PersistentArticle] = []
        for i in 0..<51 {
            let a = TestFixtures.makePersistentArticle(
                articleID: "a\(i)",
                publishedDate: Date(timeIntervalSince1970: Double(1_711_800_000 - i * 60))
            )
            a.feed = feed
            articles.append(a)
        }
        mock.articlesByFeedID[feed.id] = articles

        let vm = FeedGroupViewModel(group: group, persistence: mock)
        vm.loadArticles()

        #expect(vm.articles.count == 50)
        #expect(vm.hasMore == true)

        let result = vm.loadMoreArticles()
        #expect(result == .loaded)
        #expect(vm.articles.count == 51)
        #expect(vm.hasMore == false)
    }

    // MARK: - Mutations

    @Test("markAsRead marks article and returns true")
    @MainActor
    func markAsReadSuccess() {
        let mock = MockFeedPersistenceService()
        let group = TestFixtures.makePersistentFeedGroup()
        let article = TestFixtures.makePersistentArticle(isRead: false)

        let vm = FeedGroupViewModel(group: group, persistence: mock)
        let result = vm.markAsRead(article)

        #expect(result == true)
        #expect(article.isRead == true)
    }

    @Test("markAsRead returns false on persistence error")
    @MainActor
    func markAsReadFailure() {
        let mock = MockFeedPersistenceService()
        mock.errorToThrow = NSError(domain: "test", code: 1)
        let group = TestFixtures.makePersistentFeedGroup()
        let article = TestFixtures.makePersistentArticle(isRead: false)

        let vm = FeedGroupViewModel(group: group, persistence: mock)
        let result = vm.markAsRead(article)

        #expect(result == false)
        #expect(vm.errorMessage != nil)
    }

    @Test("markAllAsRead marks all articles in group as read")
    @MainActor
    func markAllAsRead() {
        let mock = MockFeedPersistenceService()
        let group = TestFixtures.makePersistentFeedGroup(name: "Tech")
        let feed = TestFixtures.makePersistentFeed()
        feed.group = group
        mock.feeds = [feed]

        let a1 = TestFixtures.makePersistentArticle(articleID: "a1", isRead: false)
        a1.feed = feed
        let a2 = TestFixtures.makePersistentArticle(articleID: "a2", isRead: false)
        a2.feed = feed
        mock.articlesByFeedID[feed.id] = [a1, a2]

        let vm = FeedGroupViewModel(group: group, persistence: mock)
        vm.markAllAsRead()

        #expect(a1.isRead == true)
        #expect(a2.isRead == true)
    }

    @Test("toggleSaved toggles article saved state")
    @MainActor
    func toggleSaved() {
        let mock = MockFeedPersistenceService()
        let group = TestFixtures.makePersistentFeedGroup()
        let article = TestFixtures.makePersistentArticle(isSaved: false)

        let vm = FeedGroupViewModel(group: group, persistence: mock)
        vm.toggleSaved(article)

        #expect(article.isSaved == true)
    }

    // MARK: - Sort Order

    @Test("sortAscending setter triggers reload")
    @MainActor
    func sortAscendingTriggersReload() {
        let mock = MockFeedPersistenceService()
        let group = TestFixtures.makePersistentFeedGroup(name: "Tech")
        let feed = TestFixtures.makePersistentFeed()
        feed.group = group
        mock.feeds = [feed]

        let older = TestFixtures.makePersistentArticle(
            articleID: "older",
            publishedDate: Date(timeIntervalSince1970: 1_711_800_000)
        )
        older.feed = feed
        let newer = TestFixtures.makePersistentArticle(
            articleID: "newer",
            publishedDate: Date(timeIntervalSince1970: 1_711_900_000)
        )
        newer.feed = feed
        mock.articlesByFeedID[feed.id] = [older, newer]

        let vm = FeedGroupViewModel(group: group, persistence: mock)
        vm.loadArticles()

        // Default is descending (newest first)
        #expect(vm.articles.first?.articleID == "newer")

        vm.sortAscending = true
        #expect(vm.articles.first?.articleID == "older")

        // Clean up UserDefaults
        UserDefaults.standard.removeObject(forKey: FeedViewModel.sortAscendingKey)
    }
}
