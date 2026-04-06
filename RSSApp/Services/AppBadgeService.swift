import Foundation
import UserNotifications
import os

// MARK: - Protocol

@MainActor
protocol AppBadgeUpdating: Sendable {
    /// The current badge mode setting. Changes are persisted to UserDefaults.
    var badgeMode: AppBadgeMode { get set }

    /// Updates the app icon badge based on the current mode and unread count.
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
    private static let badgeModeDefaultsKey = "appBadgeMode"

    private let notificationCenter: UNUserNotificationCenter

    init(notificationCenter: UNUserNotificationCenter = .current()) {
        self.notificationCenter = notificationCenter
    }

    var badgeMode: AppBadgeMode {
        get {
            let stored = UserDefaults.standard.string(forKey: Self.badgeModeDefaultsKey) ?? ""
            return AppBadgeMode(rawValue: stored) ?? .defaultMode
        }
        // RATIONALE: nonmutating because the backing store is UserDefaults, not a stored
        // property on self. This allows views to call the setter without requiring a mutable
        // binding to the service.
        nonmutating set {
            UserDefaults.standard.set(newValue.rawValue, forKey: Self.badgeModeDefaultsKey)
            Self.logger.notice("Badge mode changed to '\(newValue.rawValue, privacy: .public)'")
        }
    }

    func updateBadge(unreadCount: Int) async {
        if unreadCount < 0 {
            Self.logger.warning("updateBadge called with negative count \(unreadCount, privacy: .public) — clamping to 0")
            await clearBadge()
            return
        }

        let mode = badgeMode
        Self.logger.debug("updateBadge(unreadCount: \(unreadCount, privacy: .public)) with mode '\(mode.rawValue, privacy: .public)'")

        switch mode {
        case .off:
            await clearBadge()
        case .count:
            await setBadgeCount(unreadCount)
        case .indicator:
            await setBadgeCount(unreadCount > 0 ? 1 : 0)
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
