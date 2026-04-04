import Testing
import Foundation
@testable import RSSApp

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

    @Test("loadUnreadCount sets errorMessage on failure")
    @MainActor
    func loadUnreadCountError() {
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.unreadCountError = NSError(domain: "test", code: 1)

        let viewModel = HomeViewModel(persistence: mockPersistence)
        viewModel.loadUnreadCount()

        #expect(viewModel.errorMessage != nil)
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

    // MARK: - All Articles

    @Test("allArticles returns articles sorted by date descending")
    @MainActor
    func allArticlesReturnsSorted() {
        let feed = TestFixtures.makePersistentFeed()
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]

        let older = TestFixtures.makePersistentArticle(
            articleID: "old",
            title: "Older",
            publishedDate: Date(timeIntervalSince1970: 1_000_000)
        )
        older.feed = feed
        let newer = TestFixtures.makePersistentArticle(
            articleID: "new",
            title: "Newer",
            publishedDate: Date(timeIntervalSince1970: 2_000_000)
        )
        newer.feed = feed
        mockPersistence.articlesByFeedID[feed.id] = [older, newer]

        let viewModel = HomeViewModel(persistence: mockPersistence)
        let articles = viewModel.allArticles()

        #expect(articles.count == 2)
        #expect(articles[0].articleID == "new")
        #expect(articles[1].articleID == "old")
    }

    @Test("allArticles returns articles from multiple feeds")
    @MainActor
    func allArticlesMultipleFeeds() {
        let feed1 = TestFixtures.makePersistentFeed(title: "Feed 1", feedURL: URL(string: "https://one.com/feed")!)
        let feed2 = TestFixtures.makePersistentFeed(title: "Feed 2", feedURL: URL(string: "https://two.com/feed")!)
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed1, feed2]

        let article1 = TestFixtures.makePersistentArticle(articleID: "a1", title: "From Feed 1")
        article1.feed = feed1
        let article2 = TestFixtures.makePersistentArticle(articleID: "a2", title: "From Feed 2")
        article2.feed = feed2
        mockPersistence.articlesByFeedID[feed1.id] = [article1]
        mockPersistence.articlesByFeedID[feed2.id] = [article2]

        let viewModel = HomeViewModel(persistence: mockPersistence)
        let articles = viewModel.allArticles()

        #expect(articles.count == 2)
    }

    @Test("allArticles returns empty on error")
    @MainActor
    func allArticlesError() {
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.errorToThrow = NSError(domain: "test", code: 1)

        let viewModel = HomeViewModel(persistence: mockPersistence)
        let articles = viewModel.allArticles()

        #expect(articles.isEmpty)
        #expect(viewModel.errorMessage != nil)
    }

    // MARK: - Unread Articles

    @Test("unreadArticles returns only unread articles")
    @MainActor
    func unreadArticlesFilters() {
        let feed = TestFixtures.makePersistentFeed()
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]

        let unread = TestFixtures.makePersistentArticle(articleID: "u1", title: "Unread", isRead: false)
        unread.feed = feed
        let read = TestFixtures.makePersistentArticle(articleID: "r1", title: "Read", isRead: true)
        read.feed = feed
        mockPersistence.articlesByFeedID[feed.id] = [unread, read]

        let viewModel = HomeViewModel(persistence: mockPersistence)
        let articles = viewModel.unreadArticles()

        #expect(articles.count == 1)
        #expect(articles[0].articleID == "u1")
    }

    @Test("unreadArticles returns empty when all read")
    @MainActor
    func unreadArticlesAllRead() {
        let feed = TestFixtures.makePersistentFeed()
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]

        let read = TestFixtures.makePersistentArticle(articleID: "r1", isRead: true)
        read.feed = feed
        mockPersistence.articlesByFeedID[feed.id] = [read]

        let viewModel = HomeViewModel(persistence: mockPersistence)
        let articles = viewModel.unreadArticles()

        #expect(articles.isEmpty)
    }

    @Test("unreadArticles returns empty on error")
    @MainActor
    func unreadArticlesError() {
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.errorToThrow = NSError(domain: "test", code: 1)

        let viewModel = HomeViewModel(persistence: mockPersistence)
        let articles = viewModel.unreadArticles()

        #expect(articles.isEmpty)
        #expect(viewModel.errorMessage != nil)
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

    @Test("loadUnreadArticles sets errorMessage on failure")
    @MainActor
    func loadUnreadArticlesPaginatedError() {
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.errorToThrow = NSError(domain: "test", code: 1)

        let viewModel = HomeViewModel(persistence: mockPersistence)
        viewModel.loadUnreadArticles()

        #expect(viewModel.unreadArticlesList.isEmpty)
        #expect(viewModel.errorMessage != nil)
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

    @Test("markAsRead sets errorMessage on persistence failure and returns false")
    @MainActor
    func markAsReadError() {
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.errorToThrow = NSError(domain: "test", code: 1)

        let article = TestFixtures.makePersistentArticle(articleID: "a1", isRead: false)

        let viewModel = HomeViewModel(persistence: mockPersistence)
        let result = viewModel.markAsRead(article)

        #expect(result == false)
        #expect(viewModel.errorMessage != nil)
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

    @Test("toggleReadStatus sets errorMessage on persistence failure")
    @MainActor
    func toggleReadStatusError() {
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.errorToThrow = NSError(domain: "test", code: 1)

        let article = TestFixtures.makePersistentArticle(articleID: "a1", isRead: false)

        let viewModel = HomeViewModel(persistence: mockPersistence)
        viewModel.toggleReadStatus(article)

        #expect(viewModel.errorMessage != nil)
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
