import Foundation
import os

/// Persists the user's preference for restricting background image downloads
/// (thumbnail prefetch and feed icon resolution during refresh) to WiFi only.
///
/// On-demand image loading — thumbnails when scrolling to an article and feed
/// icons when viewing a feed — is always allowed regardless of this setting.
enum BackgroundImageDownloadSettings {

    private static let logger = Logger(category: "BackgroundImageDownloadSettings")

    private static let wifiOnlyDefaultsKey = "backgroundImageDownloadWiFiOnly"

    /// Posted on `NotificationCenter.default` whenever `wifiOnly` is written.
    /// Observers receive the notification on the same thread as the write.
    /// `FeedRefreshService` subscribes to this notification to cancel in-flight
    /// background download tasks when the WiFi-only setting is turned on.
    static let wifiOnlyDidChangeNotification = Notification.Name(
        "BackgroundImageDownloadSettings.wifiOnlyDidChange"
    )

    /// Whether background image downloads should be restricted to WiFi.
    ///
    /// When `true`, thumbnail prefetching and feed icon resolution during refresh
    /// are skipped on cellular and constrained (Low Data Mode) networks.
    /// Default: `true` (WiFi only).
    static var wifiOnly: Bool {
        get {
            // Default to true (WiFi only) when key has never been set.
            if UserDefaults.standard.object(forKey: wifiOnlyDefaultsKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: wifiOnlyDefaultsKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: wifiOnlyDefaultsKey)
            logger.notice("Background image download WiFi-only changed to \(newValue, privacy: .public)")
            NotificationCenter.default.post(name: wifiOnlyDidChangeNotification, object: nil)
        }
    }
}
