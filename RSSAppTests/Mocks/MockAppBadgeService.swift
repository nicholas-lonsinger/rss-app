import Foundation
@testable import RSSApp

@MainActor
final class MockAppBadgeService: AppBadgeUpdating {

    // MARK: - State

    var badgeEnabled: Bool = true
    private(set) var updateBadgeCallCount = 0
    private(set) var clearBadgeCallCount = 0
    private(set) var lastUnreadCount: Int?

    func updateBadge(unreadCount: Int) async {
        updateBadgeCallCount += 1
        lastUnreadCount = unreadCount
    }

    func clearBadge() async {
        clearBadgeCallCount += 1
    }
}
