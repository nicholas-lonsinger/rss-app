import Foundation
import UserNotifications
import os

// MARK: - Protocol

@MainActor
protocol AppBadgeUpdating: Sendable {
    /// Whether the app icon badge is enabled. Changes are persisted to UserDefaults.
    var badgeEnabled: Bool { get set }

    /// Updates the app icon badge based on the current setting and unread count.
    /// Requests notification permission if needed (badge-only, no alerts/sounds).
    /// - Parameter unreadCount: The total number of unread articles across all feeds.
    func updateBadge(unreadCount: Int) async

    /// Clears the app icon badge immediately (sets badge count to 0).
    func clearBadge() async
}

// MARK: - Implementation

@MainActor
struct AppBadgeService: AppBadgeUpdating {

    private static let logger = Logger(category: "AppBadgeService")
    private static let badgeEnabledDefaultsKey = "appBadgeEnabled"

    private let notificationCenter: UNUserNotificationCenter

    init(notificationCenter: UNUserNotificationCenter = .current()) {
        self.notificationCenter = notificationCenter
    }

    var badgeEnabled: Bool {
        get {
            // Default to true (badge on) when key has never been set.
            if UserDefaults.standard.object(forKey: Self.badgeEnabledDefaultsKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: Self.badgeEnabledDefaultsKey)
        }
        // RATIONALE: nonmutating because the backing store is UserDefaults, not a stored
        // property on self. This allows views to call the setter without requiring a mutable
        // binding to the service.
        nonmutating set {
            UserDefaults.standard.set(newValue, forKey: Self.badgeEnabledDefaultsKey)
            Self.logger.notice("Badge enabled changed to \(newValue, privacy: .public)")
        }
    }

    func updateBadge(unreadCount: Int) async {
        if unreadCount < 0 {
            Self.logger.warning("updateBadge called with negative count \(unreadCount, privacy: .public) — clamping to 0")
            await clearBadge()
            return
        }

        if badgeEnabled {
            await setBadgeCount(unreadCount)
        } else {
            await clearBadge()
        }
    }

    func clearBadge() async {
        await setBadgeCount(0)
    }

    // MARK: - Private

    private func setBadgeCount(_ count: Int) async {
        let clampedCount = max(0, count)
        guard await requestPermissionIfNeeded() else {
            Self.logger.warning("Badge permission not granted — skipping badge update")
            return
        }
        do {
            try await notificationCenter.setBadgeCount(clampedCount)
            Self.logger.debug("Badge count set to \(clampedCount, privacy: .public)")
        } catch {
            Self.logger.error("Failed to set badge count to \(clampedCount, privacy: .public): \(error, privacy: .public)")
        }
    }

    /// Requests badge-only notification permission. Returns `true` if badge access is authorized.
    private func requestPermissionIfNeeded() async -> Bool {
        let settings = await notificationCenter.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            Self.logger.warning("Notification authorization denied — badge cannot be updated")
            return false
        case .notDetermined:
            Self.logger.debug("Requesting badge-only notification authorization")
            do {
                let granted = try await notificationCenter.requestAuthorization(options: [.badge])
                if granted {
                    Self.logger.notice("Badge-only notification authorization granted")
                } else {
                    Self.logger.warning("Badge-only notification authorization denied by user")
                }
                return granted
            } catch {
                Self.logger.error("Failed to request notification authorization: \(error, privacy: .public)")
                return false
            }
        @unknown default:
            Self.logger.warning("Unknown notification authorization status: \(String(describing: settings.authorizationStatus), privacy: .public)")
            return false
        }
    }
}
