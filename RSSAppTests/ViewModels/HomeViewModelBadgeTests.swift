import Testing
import Foundation
@testable import RSSApp

@Suite("HomeViewModel Badge Integration Tests")
struct HomeViewModelBadgeTests {

    // MARK: - Badge updates on loadUnreadCount

    @Test("loadUnreadCount triggers badge update with correct count")
    @MainActor
    func loadUnreadCountUpdatesBadge() async {
        let feed = TestFixtures.makePersistentFeed()
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]

        let article1 = TestFixtures.makePersistentArticle(articleID: "a1", isRead: false)
        article1.feed = feed
        let article2 = TestFixtures.makePersistentArticle(articleID: "a2", isRead: false)
        article2.feed = feed
        let article3 = TestFixtures.makePersistentArticle(articleID: "a3", isRead: true)
        article3.feed = feed
        mockPersistence.articlesByFeedID[feed.id] = [article1, article2, article3]

        let mockBadge = MockAppBadgeService()
        let viewModel = HomeViewModel(persistence: mockPersistence, badgeService: mockBadge)

        viewModel.loadUnreadCount()
        #expect(viewModel.unreadCount == 2)

        // Badge update is dispatched via Task — yield to allow it to execute
        await Task.yield()

        #expect(mockBadge.updateBadgeCallCount == 1)
        #expect(mockBadge.lastUnreadCount == 2)
    }

    @Test("loadUnreadCount with zero unread sends zero to badge")
    @MainActor
    func loadUnreadCountZero() async {
        let mockPersistence = MockFeedPersistenceService()
        let mockBadge = MockAppBadgeService()
        let viewModel = HomeViewModel(persistence: mockPersistence, badgeService: mockBadge)

        viewModel.loadUnreadCount()
        #expect(viewModel.unreadCount == 0)

        await Task.yield()

        #expect(mockBadge.updateBadgeCallCount == 1)
        #expect(mockBadge.lastUnreadCount == 0)
    }

    @Test("loadUnreadCount error does not trigger badge update")
    @MainActor
    func loadUnreadCountErrorSkipsBadge() async {
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.unreadCountError = NSError(domain: "test", code: 1)
        let mockBadge = MockAppBadgeService()
        let viewModel = HomeViewModel(persistence: mockPersistence, badgeService: mockBadge)

        viewModel.loadUnreadCount()

        await Task.yield()

        #expect(viewModel.errorMessage != nil)
        #expect(mockBadge.updateBadgeCallCount == 0)
    }

    // MARK: - updateBadge direct call

    @Test("updateBadge sends current unread count to badge service")
    @MainActor
    func updateBadgeDirect() async {
        let feed = TestFixtures.makePersistentFeed()
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]

        let article = TestFixtures.makePersistentArticle(articleID: "a1", isRead: false)
        article.feed = feed
        mockPersistence.articlesByFeedID[feed.id] = [article]

        let mockBadge = MockAppBadgeService()
        let viewModel = HomeViewModel(persistence: mockPersistence, badgeService: mockBadge)

        viewModel.loadUnreadCount()
        await Task.yield()

        // Reset call count from loadUnreadCount's auto-update
        let previousCount = mockBadge.updateBadgeCallCount

        await viewModel.updateBadge()

        #expect(mockBadge.updateBadgeCallCount == previousCount + 1)
        #expect(mockBadge.lastUnreadCount == 1)
    }

    // MARK: - Badge updates after mark-read operations

    @Test("markAsRead triggers badge update via loadUnreadCount")
    @MainActor
    func markAsReadUpdatesBadge() async {
        let feed = TestFixtures.makePersistentFeed()
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]

        let article = TestFixtures.makePersistentArticle(articleID: "a1", isRead: false)
        article.feed = feed
        mockPersistence.articlesByFeedID[feed.id] = [article]

        let mockBadge = MockAppBadgeService()
        let viewModel = HomeViewModel(persistence: mockPersistence, badgeService: mockBadge)

        viewModel.loadUnreadCount()
        await Task.yield()
        #expect(mockBadge.lastUnreadCount == 1)

        viewModel.markAsRead(article)
        await Task.yield()

        // After marking as read, unread count should be 0
        #expect(viewModel.unreadCount == 0)
        #expect(mockBadge.lastUnreadCount == 0)
    }

    @Test("toggleReadStatus triggers badge update via loadUnreadCount")
    @MainActor
    func toggleReadStatusUpdatesBadge() async {
        let feed = TestFixtures.makePersistentFeed()
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]

        let article = TestFixtures.makePersistentArticle(articleID: "a1", isRead: true)
        article.feed = feed
        mockPersistence.articlesByFeedID[feed.id] = [article]

        let mockBadge = MockAppBadgeService()
        let viewModel = HomeViewModel(persistence: mockPersistence, badgeService: mockBadge)

        viewModel.loadUnreadCount()
        await Task.yield()
        #expect(mockBadge.lastUnreadCount == 0)

        // Toggle from read to unread
        viewModel.toggleReadStatus(article)
        await Task.yield()

        #expect(viewModel.unreadCount == 1)
        #expect(mockBadge.lastUnreadCount == 1)
    }

    @Test("markAllAsRead triggers badge update via loadUnreadCount")
    @MainActor
    func markAllAsReadUpdatesBadge() async {
        let feed = TestFixtures.makePersistentFeed()
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]

        let article1 = TestFixtures.makePersistentArticle(articleID: "a1", isRead: false)
        article1.feed = feed
        let article2 = TestFixtures.makePersistentArticle(articleID: "a2", isRead: false)
        article2.feed = feed
        mockPersistence.articlesByFeedID[feed.id] = [article1, article2]

        let mockBadge = MockAppBadgeService()
        let viewModel = HomeViewModel(persistence: mockPersistence, badgeService: mockBadge)

        viewModel.loadUnreadCount()
        await Task.yield()
        #expect(mockBadge.lastUnreadCount == 2)

        viewModel.markAllAsRead()
        await Task.yield()

        #expect(viewModel.unreadCount == 0)
        #expect(mockBadge.lastUnreadCount == 0)
    }
}
