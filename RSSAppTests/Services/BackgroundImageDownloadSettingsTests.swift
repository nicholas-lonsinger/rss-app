import Testing
import Foundation
@testable import RSSApp

@Suite("BackgroundImageDownloadSettings Tests", .serialized)
struct BackgroundImageDownloadSettingsTests {

    private static let wifiOnlyDefaultsKey = "backgroundImageDownloadWiFiOnly"

    init() {
        // Clean slate for each test
        UserDefaults.standard.removeObject(forKey: Self.wifiOnlyDefaultsKey)
    }

    @Test("Default value is true (WiFi only)")
    func defaultIsWiFiOnly() {
        #expect(BackgroundImageDownloadSettings.wifiOnly == true)
    }

    @Test("Setter round-trips through false and back to true")
    func setterRoundTrip() {
        // Assert the intermediate false state so a no-op setter can't pass this test:
        // because the service's default is `true`, asserting only the final value would
        // trivially succeed even if both assignments were dropped.
        BackgroundImageDownloadSettings.wifiOnly = false
        #expect(BackgroundImageDownloadSettings.wifiOnly == false)
        BackgroundImageDownloadSettings.wifiOnly = true
        #expect(BackgroundImageDownloadSettings.wifiOnly == true)
    }
}
