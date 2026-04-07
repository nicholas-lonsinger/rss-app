import Foundation
import Network
import os

// MARK: - Protocol

/// Provides network path status for gating background image downloads.
protocol NetworkMonitoring: Sendable {

    /// Returns `true` when background image downloads are allowed on the current network.
    ///
    /// The check combines the user's preference (WiFi-only vs. any network) with the
    /// current `NWPath`:
    /// - When WiFi-only is **off**, returns `true` whenever the path is satisfied.
    /// - When WiFi-only is **on**, returns `true` only when the path uses WiFi **and**
    ///   is not constrained (Low Data Mode).
    func isBackgroundDownloadAllowed() -> Bool
}

// MARK: - Implementation

/// Monitors the device's network path via `NWPathMonitor` and exposes a simple
/// boolean check for background download eligibility.
///
/// Starts monitoring on `init`; the path is updated asynchronously. The first
/// path is typically available within milliseconds, but callers should handle
/// a briefly-unknown state (defaults to disallowed until the first update).
final class NetworkMonitorService: NetworkMonitoring, @unchecked Sendable {

    private static let logger = Logger(category: "NetworkMonitorService")

    private let monitor: NWPathMonitor
    private let queue: DispatchQueue

    /// The latest network path snapshot. Guarded by `lock` for thread safety.
    private var currentPath: NWPath?
    private let lock = NSLock()

    init() {
        self.monitor = NWPathMonitor()
        self.queue = DispatchQueue(label: "com.nicholas-lonsinger.rss-app.network-monitor", qos: .utility)

        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            self.lock.lock()
            self.currentPath = path
            self.lock.unlock()
            Self.logger.debug("Network path updated: status=\(path.status.debugDescription, privacy: .public) usesWiFi=\(path.usesInterfaceType(.wifi), privacy: .public) isConstrained=\(path.isConstrained, privacy: .public)")
        }
        monitor.start(queue: queue)
        Self.logger.debug("NetworkMonitorService started")
    }

    deinit {
        monitor.cancel()
    }

    func isBackgroundDownloadAllowed() -> Bool {
        let wifiOnly = BackgroundImageDownloadSettings.wifiOnly

        lock.lock()
        let path = currentPath
        lock.unlock()

        guard let path else {
            // No path available yet (very early after init) — default to disallowed
            // when WiFi-only is on, allowed when the user allows any network.
            Self.logger.debug("No network path yet, wifiOnly=\(wifiOnly, privacy: .public) — returning \(!wifiOnly, privacy: .public)")
            return !wifiOnly
        }

        guard path.status == .satisfied else {
            Self.logger.debug("Network not satisfied — background downloads disallowed")
            return false
        }

        if wifiOnly {
            let allowed = path.usesInterfaceType(.wifi) && !path.isConstrained
            Self.logger.debug("WiFi-only check: usesWiFi=\(path.usesInterfaceType(.wifi), privacy: .public) isConstrained=\(path.isConstrained, privacy: .public) — allowed=\(allowed, privacy: .public)")
            return allowed
        }

        return true
    }
}

// MARK: - NWPath.Status debug description

extension NWPath.Status {
    var debugDescription: String {
        switch self {
        case .satisfied: return "satisfied"
        case .unsatisfied: return "unsatisfied"
        case .requiresConnection: return "requiresConnection"
        @unknown default: return "unknown(\(self))"
        }
    }
}
