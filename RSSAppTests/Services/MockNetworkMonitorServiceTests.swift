import Testing
import Foundation
@testable import RSSApp

@Suite("MockNetworkMonitorService Tests")
struct MockNetworkMonitorServiceTests {

    @Test("MockNetworkMonitorService returns configured value")
    func mockReturnsConfiguredValue() {
        let mock = MockNetworkMonitorService()

        mock.backgroundDownloadAllowed = true
        #expect(mock.isBackgroundDownloadAllowed() == true)
        #expect(mock.checkCallCount == 1)

        mock.backgroundDownloadAllowed = false
        #expect(mock.isBackgroundDownloadAllowed() == false)
        #expect(mock.checkCallCount == 2)
    }

    @Test("MockNetworkMonitorService defaults to allowed")
    func mockDefaultsToAllowed() {
        let mock = MockNetworkMonitorService()
        #expect(mock.isBackgroundDownloadAllowed() == true)
    }
}
