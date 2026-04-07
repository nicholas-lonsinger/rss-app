import Testing
import Foundation
@testable import RSSApp

/// Tests for the real `NetworkMonitorService` (as opposed to the
/// `MockNetworkMonitorService` used by view-model tests).
///
/// These tests focus on the injected `wifiOnlyProvider` so they can exercise the
/// preference branches without depending on `UserDefaults.standard`. The actual
/// network path is supplied by `NWPathMonitor` and is not deterministic in test
/// environments — these tests therefore only assert on behavior that holds for
/// every reachable code path, namely the wifiOnly-vs-not branch when no path is
/// yet available (the nil-path window immediately after init).
@Suite("NetworkMonitorService Tests")
struct NetworkMonitorServiceTests {

    @Test("wifiOnlyProvider closure is invoked on each check")
    func wifiOnlyProviderInvokedOnEachCheck() {
        let callCount = LockedCounter()
        let service = NetworkMonitorService { @Sendable in
            callCount.increment()
            return false
        }

        _ = service.isBackgroundDownloadAllowed()
        _ = service.isBackgroundDownloadAllowed()
        _ = service.isBackgroundDownloadAllowed()

        #expect(callCount.value == 3)
    }

    @Test("Returns true when wifiOnly is false and no path is available yet")
    func returnsTrueWhenWiFiOnlyFalseAndNoPath() {
        // RATIONALE: NWPathMonitor delivers the first path asynchronously. Calling
        // isBackgroundDownloadAllowed() synchronously immediately after init usually
        // hits the nil-path branch, which falls back to !wifiOnly. This test confirms
        // the injected provider is honored on that branch. If the path arrives
        // before the call (rare but possible), the result still depends on the
        // injected wifiOnly value, so the assertion remains stable for false.
        let service = NetworkMonitorService { @Sendable in false }

        // With wifiOnly=false: nil path returns true, satisfied path returns true.
        // Either way the result is true.
        #expect(service.isBackgroundDownloadAllowed() == true)
    }

    @Test("Returns false when wifiOnly is true and no path is available yet")
    func returnsFalseWhenWiFiOnlyTrueAndNoPath() {
        // RATIONALE: With wifiOnly=true, the nil-path branch returns false. Once a
        // path is delivered the result depends on whether the test machine is on
        // WiFi, which is non-deterministic — so this test only asserts the
        // immediate, synchronous result before NWPathMonitor has had a chance to
        // call back.
        let service = NetworkMonitorService { @Sendable in true }

        #expect(service.isBackgroundDownloadAllowed() == false)
    }

    @Test("Default initializer reads from BackgroundImageDownloadSettings")
    func defaultInitReadsFromBackgroundImageDownloadSettings() {
        // Snapshot and restore the real preference so this test does not leak
        // state into other suites.
        let original = BackgroundImageDownloadSettings.wifiOnly
        defer { BackgroundImageDownloadSettings.wifiOnly = original }

        BackgroundImageDownloadSettings.wifiOnly = false
        let serviceA = NetworkMonitorService()
        // wifiOnly=false → nil-path branch returns true.
        #expect(serviceA.isBackgroundDownloadAllowed() == true)

        BackgroundImageDownloadSettings.wifiOnly = true
        let serviceB = NetworkMonitorService()
        // wifiOnly=true → nil-path branch returns false.
        #expect(serviceB.isBackgroundDownloadAllowed() == false)
    }
}

// MARK: - Test helpers

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
