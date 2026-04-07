import Foundation
@testable import RSSApp

@MainActor
final class MockAppBadgeService: AppBadgeUpdating {

    // MARK: - State

    var badgeEnabled: Bool = false
    var permissionStatus: BadgePermissionStatus = .authorized

    /// When set, `updateBadge(unreadCount:)` transitions `permissionStatus` to this
    /// value — simulating the user responding to the system notification prompt that
    /// `setBadgeCount` triggers internally when permission is `.notDetermined`.
    var permissionStatusAfterPrompt: BadgePermissionStatus?

    private(set) var updateBadgeCallCount = 0
    private(set) var clearBadgeCallCount = 0
    private(set) var checkPermissionCallCount = 0
    private(set) var lastUnreadCount: Int?

    func updateBadge(unreadCount: Int) async {
        updateBadgeCallCount += 1
        lastUnreadCount = unreadCount
        if let afterPrompt = permissionStatusAfterPrompt {
            permissionStatus = afterPrompt
        }
    }

    func clearBadge() async {
        clearBadgeCallCount += 1
    }

    func checkPermission() async -> BadgePermissionStatus {
        checkPermissionCallCount += 1
        return permissionStatus
    }
}
