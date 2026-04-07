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

    @Test("Setting to false persists and reads back")
    func setFalseReadsBack() {
        BackgroundImageDownloadSettings.wifiOnly = false
        #expect(BackgroundImageDownloadSettings.wifiOnly == false)
    }

    @Test("Setting to true persists and reads back")
    func setTrueReadsBack() {
        BackgroundImageDownloadSettings.wifiOnly = false
        BackgroundImageDownloadSettings.wifiOnly = true
        #expect(BackgroundImageDownloadSettings.wifiOnly == true)
    }

    @Test("Reads from UserDefaults correctly when key is explicitly set to false")
    func readsExplicitFalse() {
        UserDefaults.standard.set(false, forKey: Self.wifiOnlyDefaultsKey)
        #expect(BackgroundImageDownloadSettings.wifiOnly == false)
    }

    @Test("Reads from UserDefaults correctly when key is explicitly set to true")
    func readsExplicitTrue() {
        UserDefaults.standard.set(true, forKey: Self.wifiOnlyDefaultsKey)
        #expect(BackgroundImageDownloadSettings.wifiOnly == true)
    }
}
