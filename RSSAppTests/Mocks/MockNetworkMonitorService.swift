import Foundation
@testable import RSSApp

final class MockNetworkMonitorService: NetworkMonitoring, @unchecked Sendable {

    /// Controls what `isBackgroundDownloadAllowed()` returns.
    var backgroundDownloadAllowed = true
    var checkCallCount = 0

    func isBackgroundDownloadAllowed() -> Bool {
        checkCallCount += 1
        return backgroundDownloadAllowed
    }
}
