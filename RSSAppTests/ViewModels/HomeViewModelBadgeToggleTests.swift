import Testing
import Foundation
@testable import RSSApp

@Suite("HomeViewModel Badge Toggle Tests")
struct HomeViewModelBadgeToggleTests {

    // MARK: - handleBadgeToggleEnabled

    @Test("Permission denied returns false immediately without calling updateBadge")
    @MainActor
    func deniedReturnsFalse() async {
        let mockPersistence = MockFeedPersistenceService()
        let mockBadge = MockAppBadgeService()
        mockBadge.permissionStatus = .denied
        let viewModel = HomeViewModel(persistence: mockPersistence, badgeService: mockBadge)

        let result = await viewModel.handleBadgeToggleEnabled()

        #expect(result == false)
        #expect(mockBadge.checkPermissionCallCount == 1)
        #expect(mockBadge.updateBadgeCallCount == 0)
    }

    @Test("Permission authorized returns true and triggers badge update")
    @MainActor
    func authorizedReturnsTrue() async {
        let mockPersistence = MockFeedPersistenceService()
        let mockBadge = MockAppBadgeService()
        mockBadge.permissionStatus = .authorized
        let viewModel = HomeViewModel(persistence: mockPersistence, badgeService: mockBadge)

        let result = await viewModel.handleBadgeToggleEnabled()

        #expect(result == true)
        // First checkPermission before updateBadge, second checkPermission after
        #expect(mockBadge.checkPermissionCallCount == 2)
        #expect(mockBadge.updateBadgeCallCount == 1)
    }

    @Test("Not determined then user grants permission returns true")
    @MainActor
    func notDeterminedThenGrantedReturnsTrue() async {
        let mockPersistence = MockFeedPersistenceService()
        let mockBadge = MockAppBadgeService()
        mockBadge.permissionStatus = .notDetermined
        // Simulate user accepting the prompt during updateBadge
        mockBadge.permissionStatusAfterPrompt = .authorized
        let viewModel = HomeViewModel(persistence: mockPersistence, badgeService: mockBadge)

        let result = await viewModel.handleBadgeToggleEnabled()

        #expect(result == true)
        #expect(mockBadge.updateBadgeCallCount == 1)
        // Two checkPermission calls: pre-prompt (.notDetermined) and post-prompt (.authorized)
        #expect(mockBadge.checkPermissionCallCount == 2)
    }

    @Test("Not determined then user denies prompt returns false")
    @MainActor
    func notDeterminedThenDeniedReturnsFalse() async {
        let mockPersistence = MockFeedPersistenceService()
        let mockBadge = MockAppBadgeService()
        mockBadge.permissionStatus = .notDetermined
        // Simulate user denying the prompt during updateBadge
        mockBadge.permissionStatusAfterPrompt = .denied
        let viewModel = HomeViewModel(persistence: mockPersistence, badgeService: mockBadge)

        let result = await viewModel.handleBadgeToggleEnabled()

        #expect(result == false)
        #expect(mockBadge.updateBadgeCallCount == 1)
        // Two checkPermission calls: pre-prompt (.notDetermined) and post-prompt (.denied)
        #expect(mockBadge.checkPermissionCallCount == 2)
    }

    @Test("Badge update uses current unread count")
    @MainActor
    func badgeUpdateUsesUnreadCount() async {
        let feed = TestFixtures.makePersistentFeed()
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]

        let article1 = TestFixtures.makePersistentArticle(articleID: "a1", isRead: false)
        article1.feed = feed
        let article2 = TestFixtures.makePersistentArticle(articleID: "a2", isRead: false)
        article2.feed = feed
        mockPersistence.articlesByFeedID[feed.id] = [article1, article2]

        let mockBadge = MockAppBadgeService()
        mockBadge.permissionStatus = .authorized
        let viewModel = HomeViewModel(persistence: mockPersistence, badgeService: mockBadge)

        // Load unread count first
        viewModel.loadUnreadCount()
        await Task.yield()
        #expect(viewModel.unreadCount == 2)

        // Reset tracking from loadUnreadCount's internal badge update
        let previousUpdateCount = mockBadge.updateBadgeCallCount

        let result = await viewModel.handleBadgeToggleEnabled()

        #expect(result == true)
        #expect(mockBadge.updateBadgeCallCount == previousUpdateCount + 1)
        #expect(mockBadge.lastUnreadCount == 2)
    }
}
