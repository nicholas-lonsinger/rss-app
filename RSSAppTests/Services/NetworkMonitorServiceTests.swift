import Testing
import Foundation
@testable import RSSApp

/// Tests for the real `NetworkMonitorService` (as opposed to the
/// `MockNetworkMonitorService` used by view-model tests).
///
/// These tests focus on the injected `wifiOnlyProvider` contract. The actual
/// network path is supplied by `NWPathMonitor` and is not deterministic in test
/// environments, so assertions on the boolean result of
/// `isBackgroundDownloadAllowed()` would be racy — the nil-path window is only
/// a few milliseconds wide on a Mac with active networking. Verifying the
/// closure is invoked per-call is sufficient to prove the injection seam works;
/// the path-dependent branches are intentionally left to future tests that add
/// a second injection seam for `NWPath`.
///
/// The suite is `.serialized` as a precaution even though it no longer mutates
/// `UserDefaults.standard`, matching the convention used by other service
/// suites in this project.
@Suite("NetworkMonitorService Tests", .serialized)
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
