import Testing
import Foundation
import Network
@testable import RSSApp

/// Tests for the real `NetworkMonitorService` (as opposed to the
/// `MockNetworkMonitorService` used by view-model tests).
///
/// The service exposes two injection seams so tests can exercise every branch
/// of `isBackgroundDownloadAllowed()` deterministically:
///
/// - `wifiOnlyProvider` — controls the WiFi-only preference without touching
///   `UserDefaults.standard`.
/// - `pathProvider` — supplies a synthetic `NetworkPathSnapshot` (or `nil`) so
///   tests can drive the path-status, interface-type, and constrained-mode
///   branches without starting a real `NWPathMonitor`, whose timing is
///   non-deterministic and whose `NWPath` type cannot be constructed directly.
///
/// The suite is `.serialized` as a precaution even though it no longer mutates
/// `UserDefaults.standard`, matching the convention used by other service
/// suites in this project.
@Suite("NetworkMonitorService Tests", .serialized)
struct NetworkMonitorServiceTests {

    // MARK: - wifiOnlyProvider contract

    @Test("wifiOnlyProvider closure is invoked on each check")
    func wifiOnlyProviderInvokedOnEachCheck() {
        let callCount = LockedCounter()
        let service = NetworkMonitorService(
            wifiOnlyProvider: { @Sendable in
                callCount.increment()
                return false
            },
            pathProvider: { nil }
        )

        _ = service.isBackgroundDownloadAllowed()
        _ = service.isBackgroundDownloadAllowed()
        _ = service.isBackgroundDownloadAllowed()

        #expect(callCount.value == 3)
    }

    @Test("pathProvider closure is invoked on each check")
    func pathProviderInvokedOnEachCheck() {
        let callCount = LockedCounter()
        let service = NetworkMonitorService(
            wifiOnlyProvider: { false },
            pathProvider: { @Sendable in
                callCount.increment()
                return nil
            }
        )

        _ = service.isBackgroundDownloadAllowed()
        _ = service.isBackgroundDownloadAllowed()

        #expect(callCount.value == 2)
    }

    // MARK: - production-mode smoke test

    /// Exercises the default initializer path where no `pathProvider` is
    /// supplied, so the service constructs a real `NWPathMonitor`, wires up
    /// `pathUpdateHandler`, and starts monitoring. The assertion is incidental;
    /// the value of this test is catching future regressions in the production
    /// init branch (which every other test in this suite bypasses via an
    /// injected `pathProvider`).
    @Test("default initializer starts NWPathMonitor without crashing")
    func defaultInitializerLifecycle() {
        let service = NetworkMonitorService(wifiOnlyProvider: { false })
        _ = service.isBackgroundDownloadAllowed()
    }

    // MARK: - nil-path branch

    @Test("nil path with wifiOnly=false returns true")
    func nilPathWifiOnlyOffAllowsDownload() {
        let service = NetworkMonitorService(
            wifiOnlyProvider: { false },
            pathProvider: { nil }
        )

        #expect(service.isBackgroundDownloadAllowed() == true)
    }

    @Test("nil path with wifiOnly=true returns false")
    func nilPathWifiOnlyOnDisallowsDownload() {
        let service = NetworkMonitorService(
            wifiOnlyProvider: { true },
            pathProvider: { nil }
        )

        #expect(service.isBackgroundDownloadAllowed() == false)
    }

    // MARK: - unsatisfied-path branch

    @Test("unsatisfied path returns false regardless of wifiOnly")
    func unsatisfiedPathDisallowsDownload() {
        let unsatisfied = StubNetworkPathSnapshot(status: .unsatisfied, usesWiFi: true, isConstrained: false)

        let wifiOnlyOff = NetworkMonitorService(
            wifiOnlyProvider: { false },
            pathProvider: { unsatisfied }
        )
        let wifiOnlyOn = NetworkMonitorService(
            wifiOnlyProvider: { true },
            pathProvider: { unsatisfied }
        )

        #expect(wifiOnlyOff.isBackgroundDownloadAllowed() == false)
        #expect(wifiOnlyOn.isBackgroundDownloadAllowed() == false)
    }

    @Test("requiresConnection path returns false")
    func requiresConnectionPathDisallowsDownload() {
        let requiresConnection = StubNetworkPathSnapshot(status: .requiresConnection, usesWiFi: true, isConstrained: false)
        let service = NetworkMonitorService(
            wifiOnlyProvider: { false },
            pathProvider: { requiresConnection }
        )

        #expect(service.isBackgroundDownloadAllowed() == false)
    }

    // MARK: - wifiOnly=true satisfied-path branches

    @Test("wifiOnly=true with WiFi and unconstrained path returns true")
    func wifiOnlySatisfiedWiFiUnconstrainedAllowsDownload() {
        let snapshot = StubNetworkPathSnapshot(status: .satisfied, usesWiFi: true, isConstrained: false)
        let service = NetworkMonitorService(
            wifiOnlyProvider: { true },
            pathProvider: { snapshot }
        )

        #expect(service.isBackgroundDownloadAllowed() == true)
    }

    @Test("wifiOnly=true with non-WiFi path returns false")
    func wifiOnlySatisfiedNonWiFiDisallowsDownload() {
        let snapshot = StubNetworkPathSnapshot(status: .satisfied, usesWiFi: false, isConstrained: false)
        let service = NetworkMonitorService(
            wifiOnlyProvider: { true },
            pathProvider: { snapshot }
        )

        #expect(service.isBackgroundDownloadAllowed() == false)
    }

    @Test("wifiOnly=true with WiFi but constrained (Low Data Mode) returns false")
    func wifiOnlySatisfiedWiFiConstrainedDisallowsDownload() {
        let snapshot = StubNetworkPathSnapshot(status: .satisfied, usesWiFi: true, isConstrained: true)
        let service = NetworkMonitorService(
            wifiOnlyProvider: { true },
            pathProvider: { snapshot }
        )

        #expect(service.isBackgroundDownloadAllowed() == false)
    }

    @Test("wifiOnly=true with non-WiFi and constrained path returns false")
    func wifiOnlySatisfiedNonWiFiConstrainedDisallowsDownload() {
        let snapshot = StubNetworkPathSnapshot(status: .satisfied, usesWiFi: false, isConstrained: true)
        let service = NetworkMonitorService(
            wifiOnlyProvider: { true },
            pathProvider: { snapshot }
        )

        #expect(service.isBackgroundDownloadAllowed() == false)
    }

    // MARK: - wifiOnly=false satisfied-path branch

    @Test("wifiOnly=false with satisfied path always returns true")
    func wifiOnlyOffSatisfiedAllowsDownloadAcrossInterfaces() {
        let wifiUnconstrained = StubNetworkPathSnapshot(status: .satisfied, usesWiFi: true, isConstrained: false)
        let wifiConstrained = StubNetworkPathSnapshot(status: .satisfied, usesWiFi: true, isConstrained: true)
        let cellularUnconstrained = StubNetworkPathSnapshot(status: .satisfied, usesWiFi: false, isConstrained: false)
        let cellularConstrained = StubNetworkPathSnapshot(status: .satisfied, usesWiFi: false, isConstrained: true)

        for snapshot in [wifiUnconstrained, wifiConstrained, cellularUnconstrained, cellularConstrained] {
            let service = NetworkMonitorService(
                wifiOnlyProvider: { false },
                pathProvider: { snapshot }
            )
            #expect(service.isBackgroundDownloadAllowed() == true)
        }
    }

    // MARK: - currentPathIsWiFi

    /// `currentPathIsWiFi()` is the path-only gate used by
    /// `BackgroundRefreshCoordinator` to enforce the Wi-Fi-only setting for
    /// feed XML fetches. It must return `true` only when the path is satisfied,
    /// uses WiFi, and is not constrained — independent of any user preference.

    @Test("currentPathIsWiFi returns false when no path is available yet")
    func currentPathIsWiFiNilPath() {
        let service = NetworkMonitorService(
            wifiOnlyProvider: { false },
            pathProvider: { nil }
        )
        #expect(service.currentPathIsWiFi() == false)
    }

    @Test("currentPathIsWiFi returns false when path is unsatisfied")
    func currentPathIsWiFiUnsatisfied() {
        let snapshot = StubNetworkPathSnapshot(status: .unsatisfied, usesWiFi: true, isConstrained: false)
        let service = NetworkMonitorService(
            wifiOnlyProvider: { false },
            pathProvider: { snapshot }
        )
        #expect(service.currentPathIsWiFi() == false)
    }

    @Test("currentPathIsWiFi returns true when satisfied WiFi and unconstrained")
    func currentPathIsWiFiSatisfiedWiFiUnconstrained() {
        let snapshot = StubNetworkPathSnapshot(status: .satisfied, usesWiFi: true, isConstrained: false)
        let service = NetworkMonitorService(
            wifiOnlyProvider: { false },
            pathProvider: { snapshot }
        )
        #expect(service.currentPathIsWiFi() == true)
    }

    @Test("currentPathIsWiFi returns false when satisfied but on cellular")
    func currentPathIsWiFiSatisfiedCellular() {
        let snapshot = StubNetworkPathSnapshot(status: .satisfied, usesWiFi: false, isConstrained: false)
        let service = NetworkMonitorService(
            wifiOnlyProvider: { false },
            pathProvider: { snapshot }
        )
        #expect(service.currentPathIsWiFi() == false)
    }

    @Test("currentPathIsWiFi returns false when satisfied WiFi but constrained (Low Data Mode)")
    func currentPathIsWiFiSatisfiedWiFiConstrained() {
        let snapshot = StubNetworkPathSnapshot(status: .satisfied, usesWiFi: true, isConstrained: true)
        let service = NetworkMonitorService(
            wifiOnlyProvider: { false },
            pathProvider: { snapshot }
        )
        #expect(service.currentPathIsWiFi() == false)
    }

    @Test("currentPathIsWiFi is independent of wifiOnlyProvider value")
    func currentPathIsWiFiIgnoresPreference() {
        // currentPathIsWiFi() must not consult wifiOnlyProvider — it is a
        // path-only check that the coordinator uses independently of the
        // image-download preference.
        let snapshot = StubNetworkPathSnapshot(status: .satisfied, usesWiFi: true, isConstrained: false)

        let wifiOnlyOff = NetworkMonitorService(
            wifiOnlyProvider: { false },
            pathProvider: { snapshot }
        )
        let wifiOnlyOn = NetworkMonitorService(
            wifiOnlyProvider: { true },
            pathProvider: { snapshot }
        )

        #expect(wifiOnlyOff.currentPathIsWiFi() == true)
        #expect(wifiOnlyOn.currentPathIsWiFi() == true)
    }
}

// MARK: - Test helpers

/// Synthetic `NetworkPathSnapshot` used to drive the path-status, interface,
/// and constrained-mode branches of `NetworkMonitorService` without relying on
/// a real `NWPath`.
private struct StubNetworkPathSnapshot: NetworkPathSnapshot {
    let status: NWPath.Status
    let usesWiFi: Bool
    let isConstrained: Bool

    func usesInterfaceType(_ type: NWInterface.InterfaceType) -> Bool {
        type == .wifi ? usesWiFi : false
    }
}

/// Thread-safe counter used to verify a `@Sendable` closure was invoked the
/// expected number of times across the closure's isolation domain.
private final class LockedCounter: @unchecked Sendable {
    private var count = 0
    private let lock = NSLock()

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }
}
