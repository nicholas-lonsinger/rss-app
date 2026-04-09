import Foundation
import Network
import os

// MARK: - Protocol

/// Provides network path status for gating background image downloads and
/// background refresh.
protocol NetworkMonitoring: Sendable {

    /// Returns `true` when background image downloads are allowed on the current network.
    ///
    /// The check combines the user's preference (WiFi-only vs. any network) with the
    /// current `NWPath`:
    /// - When WiFi-only is **off**, returns `true` whenever the path is satisfied.
    /// - When WiFi-only is **on**, returns `true` only when the path uses WiFi **and**
    ///   is not constrained (Low Data Mode).
    func isBackgroundDownloadAllowed() -> Bool

    /// Returns `true` when the current network path is using WiFi and is not
    /// constrained (Low Data Mode).
    ///
    /// This is a path-only check with no user-preference component. It is used
    /// by `BackgroundRefreshCoordinator` to enforce the
    /// `BackgroundRefreshSettings.networkRequirement == .wifiOnly` gate at
    /// runtime, independent of the image-download WiFi preference.
    ///
    /// Returns `false` when no path is available yet or when the path is unsatisfied
    /// (conservative default matches the WiFi-only intent: skip rather than fetch
    /// over an unknown interface).
    func currentPathIsWiFi() -> Bool
}

// MARK: - Path snapshot abstraction

/// Minimal view of an `NWPath` snapshot, exposing only the fields
/// `NetworkMonitorService` reads. Abstracting these three properties into a
/// protocol lets tests supply a synthetic snapshot because `NWPath` itself
/// cannot be constructed directly.
protocol NetworkPathSnapshot: Sendable {

    /// Whether the path is currently satisfied, unsatisfied, or awaiting a connection.
    var status: NWPath.Status { get }

    /// Whether the path runs over the given interface type (e.g. `.wifi`).
    func usesInterfaceType(_ type: NWInterface.InterfaceType) -> Bool

    /// Whether the path is constrained (Low Data Mode).
    var isConstrained: Bool { get }
}

/// Production adapter that wraps a real `NWPath` and satisfies the
/// `NetworkPathSnapshot` contract.
struct NWPathSnapshot: NetworkPathSnapshot {

    private let path: NWPath

    init(path: NWPath) {
        self.path = path
    }

    var status: NWPath.Status { path.status }

    func usesInterfaceType(_ type: NWInterface.InterfaceType) -> Bool {
        path.usesInterfaceType(type)
    }

    var isConstrained: Bool { path.isConstrained }
}

// MARK: - Implementation

/// Monitors the device's network path via `NWPathMonitor` and exposes a simple
/// boolean check for background download eligibility.
///
/// Starts monitoring on `init`; the path is updated asynchronously. The first
/// path is typically available within milliseconds, but callers should handle
/// a briefly-unknown state (defaults to disallowed until the first update).
// RATIONALE: @unchecked Sendable because NWPathMonitor delivers updates on a private
// DispatchQueue; NSLock guards the mutable currentPath for thread-safe reads from any
// isolation domain.
final class NetworkMonitorService: NetworkMonitoring, @unchecked Sendable {

    private static let logger = Logger(category: "NetworkMonitorService")

    private let monitor: NWPathMonitor?
    private let queue: DispatchQueue

    /// The latest network path snapshot. Guarded by `lock` for thread safety.
    private var currentPath: NWPath?
    private let lock = NSLock()

    /// Closure that returns the current WiFi-only preference. Injected so tests can
    /// control the preference value without touching `UserDefaults.standard`.
    private let wifiOnlyProvider: @Sendable () -> Bool

    /// Optional test-only override that returns a synthetic network path snapshot.
    /// When set, `isBackgroundDownloadAllowed()` uses this closure instead of
    /// reading from the real `NWPathMonitor`. Abstracting `NWPath`'s fields
    /// behind `NetworkPathSnapshot` lets tests drive the path-status,
    /// interface-type, and constrained-mode branches without relying on
    /// `NWPathMonitor`, whose delivery timing is non-deterministic and whose
    /// `NWPath` type cannot be constructed directly.
    private let pathProviderOverride: (@Sendable () -> NetworkPathSnapshot?)?

    /// Creates a network monitor that reads the WiFi-only preference from the supplied
    /// provider closure. Defaults to `BackgroundImageDownloadSettings.wifiOnly` for
    /// production use; tests can inject a fixed-value closure to exercise the
    /// preference branches independently of `UserDefaults`.
    ///
    /// In production, `pathProvider` is left unset and the service starts an
    /// internal `NWPathMonitor` that tracks the device's real network path.
    /// Tests supply their own `pathProvider` closure to bypass `NWPathMonitor`
    /// entirely and deliver deterministic `NetworkPathSnapshot` values.
    init(
        wifiOnlyProvider: @escaping @Sendable () -> Bool = { BackgroundImageDownloadSettings.wifiOnly },
        pathProvider: (@Sendable () -> NetworkPathSnapshot?)? = nil
    ) {
        self.queue = DispatchQueue(label: "com.nicholas-lonsinger.rss-app.network-monitor", qos: .utility)
        self.wifiOnlyProvider = wifiOnlyProvider
        self.pathProviderOverride = pathProvider

        if pathProvider != nil {
            // Test mode: caller supplies the path snapshot directly. No
            // NWPathMonitor is started, so nothing mutates `currentPath`.
            self.monitor = nil
            Self.logger.debug("NetworkMonitorService started with injected pathProvider")
        } else {
            // Production mode: start NWPathMonitor and expose snapshots via
            // the locked `currentPath` inside `isBackgroundDownloadAllowed()`.
            let monitor = NWPathMonitor()
            self.monitor = monitor

            monitor.pathUpdateHandler = { [weak self] path in
                guard let self else { return }
                self.lock.lock()
                self.currentPath = path
                self.lock.unlock()
                Self.logger.debug("Network path updated: status=\(path.status.statusLabel, privacy: .public) usesWiFi=\(path.usesInterfaceType(.wifi), privacy: .public) isConstrained=\(path.isConstrained, privacy: .public)")
            }
            monitor.start(queue: queue)
            Self.logger.debug("NetworkMonitorService started")
        }
    }

    deinit {
        monitor?.cancel()
    }

    /// Returns the current `NetworkPathSnapshot` from either the injected
    /// override (test mode) or the monitored `NWPath` (production mode).
    private func currentSnapshot() -> NetworkPathSnapshot? {
        if let pathProviderOverride {
            return pathProviderOverride()
        }
        lock.lock()
        let path = currentPath
        lock.unlock()
        return path.map(NWPathSnapshot.init(path:))
    }

    func isBackgroundDownloadAllowed() -> Bool {
        let wifiOnly = wifiOnlyProvider()
        let path = currentSnapshot()

        // RATIONALE: When WiFi-only is off and no path is available yet, returning true
        // is safe because downstream URLSession calls will fail gracefully if the network
        // is actually unavailable. The nil-path window is milliseconds after init.
        guard let path else {
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

    func currentPathIsWiFi() -> Bool {
        guard let path = currentSnapshot() else {
            // No path yet — conservatively deny. A WiFi-only BG refresh skips
            // rather than risks fetching over an unknown interface. This can
            // happen when a BGTask fires before NWPathMonitor delivers its
            // first update.
            Self.logger.warning("currentPathIsWiFi() — no path yet (BGTask may have fired before NWPathMonitor delivered its first update), returning false (conservative deny)")
            return false
        }
        guard path.status == .satisfied else {
            Self.logger.debug("currentPathIsWiFi() — path not satisfied, returning false")
            return false
        }
        let isWiFi = path.usesInterfaceType(.wifi) && !path.isConstrained
        Self.logger.debug("currentPathIsWiFi() — usesWiFi=\(path.usesInterfaceType(.wifi), privacy: .public) isConstrained=\(path.isConstrained, privacy: .public) → \(isWiFi, privacy: .public)")
        return isWiFi
    }
}

// MARK: - NWPath.Status label

extension NWPath.Status {
    var statusLabel: String {
        switch self {
        case .satisfied: return "satisfied"
        case .unsatisfied: return "unsatisfied"
        case .requiresConnection: return "requiresConnection"
        @unknown default: return "unknown(\(self))"
        }
    }
}
