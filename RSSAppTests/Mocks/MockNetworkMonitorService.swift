import Foundation
@testable import RSSApp

final class MockNetworkMonitorService: NetworkMonitoring, @unchecked Sendable {

    /// Controls what `isBackgroundDownloadAllowed()` returns.
    var backgroundDownloadAllowed = true
    var checkCallCount = 0

    /// Controls what `currentPathIsWiFi()` returns.
    var pathIsWiFi = true

    func isBackgroundDownloadAllowed() -> Bool {
        checkCallCount += 1
        return backgroundDownloadAllowed
    }

    func currentPathIsWiFi() -> Bool {
        return pathIsWiFi
    }
}
