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

    @Test("Setter writes false then true and reads back the final value")
    func setTrueReadsBack() {
        BackgroundImageDownloadSettings.wifiOnly = false
        BackgroundImageDownloadSettings.wifiOnly = true
        #expect(BackgroundImageDownloadSettings.wifiOnly == true)
    }
}
