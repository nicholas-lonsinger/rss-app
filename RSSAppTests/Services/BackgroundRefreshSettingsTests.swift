import Testing
import Foundation
@testable import RSSApp

@Suite("BackgroundRefreshSettings Tests", .serialized)
struct BackgroundRefreshSettingsTests {

    private static let enabledKey = "backgroundRefreshEnabled"
    private static let intervalKey = "backgroundRefreshIntervalSeconds"
    private static let networkKey = "backgroundRefreshNetworkRequirement"
    private static let powerKey = "backgroundRefreshPowerRequirement"

    init() {
        // Clean slate for each test so defaults are observed on first read.
        UserDefaults.standard.removeObject(forKey: Self.enabledKey)
        UserDefaults.standard.removeObject(forKey: Self.intervalKey)
        UserDefaults.standard.removeObject(forKey: Self.networkKey)
        UserDefaults.standard.removeObject(forKey: Self.powerKey)
    }

    // MARK: - Defaults (issue #76 spec)

    @Test("Default isEnabled is true")
    func defaultEnabledTrue() {
        #expect(BackgroundRefreshSettings.isEnabled == true)
    }

    @Test("Default interval is one hour")
    func defaultIntervalIsOneHour() {
        #expect(BackgroundRefreshSettings.interval == .oneHour)
    }

    @Test("Default network requirement is Wi-Fi only")
    func defaultNetworkIsWiFiOnly() {
        #expect(BackgroundRefreshSettings.networkRequirement == .wifiOnly)
    }

    @Test("Default power requirement is charging only")
    func defaultPowerIsChargingOnly() {
        #expect(BackgroundRefreshSettings.powerRequirement == .chargingOnly)
    }

    // MARK: - Setter round-trips

    @Test("isEnabled round-trips through false and back to true")
    func isEnabledRoundTrip() {
        BackgroundRefreshSettings.isEnabled = false
        #expect(BackgroundRefreshSettings.isEnabled == false)
        BackgroundRefreshSettings.isEnabled = true
        #expect(BackgroundRefreshSettings.isEnabled == true)
    }

    @Test("interval round-trips through a non-default value and back")
    func intervalRoundTrip() {
        BackgroundRefreshSettings.interval = .fifteenMinutes
        #expect(BackgroundRefreshSettings.interval == .fifteenMinutes)
        BackgroundRefreshSettings.interval = .eightHours
        #expect(BackgroundRefreshSettings.interval == .eightHours)
    }

    @Test("network requirement round-trips")
    func networkRequirementRoundTrip() {
        BackgroundRefreshSettings.networkRequirement = .wifiAndCellular
        #expect(BackgroundRefreshSettings.networkRequirement == .wifiAndCellular)
        BackgroundRefreshSettings.networkRequirement = .wifiOnly
        #expect(BackgroundRefreshSettings.networkRequirement == .wifiOnly)
    }

    @Test("power requirement round-trips")
    func powerRequirementRoundTrip() {
        BackgroundRefreshSettings.powerRequirement = .anytime
        #expect(BackgroundRefreshSettings.powerRequirement == .anytime)
        BackgroundRefreshSettings.powerRequirement = .chargingOnly
        #expect(BackgroundRefreshSettings.powerRequirement == .chargingOnly)
    }

    // MARK: - Corrupt-value recovery

    @Test("Unknown stored interval value falls back to default")
    func unknownIntervalFallsBackToDefault() {
        UserDefaults.standard.set(99_999, forKey: Self.intervalKey)
        #expect(BackgroundRefreshSettings.interval == .default)
    }

    @Test("Unknown stored network requirement falls back to default")
    func unknownNetworkFallsBackToDefault() {
        UserDefaults.standard.set("bluetooth", forKey: Self.networkKey)
        #expect(BackgroundRefreshSettings.networkRequirement == .default)
    }

    @Test("Unknown stored power requirement falls back to default")
    func unknownPowerFallsBackToDefault() {
        UserDefaults.standard.set("solar", forKey: Self.powerKey)
        #expect(BackgroundRefreshSettings.powerRequirement == .default)
    }
}
