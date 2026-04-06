import Testing
@testable import RSSApp

@Suite("AppBadgeMode Tests")
struct AppBadgeModeTests {

    @Test("allCases contains all three modes")
    func allCases() {
        #expect(AppBadgeMode.allCases.count == 3)
        #expect(AppBadgeMode.allCases.contains(.count))
        #expect(AppBadgeMode.allCases.contains(.indicator))
        #expect(AppBadgeMode.allCases.contains(.off))
    }

    @Test("each mode has a unique id")
    func uniqueIDs() {
        let ids = Set(AppBadgeMode.allCases.map(\.id))
        #expect(ids.count == AppBadgeMode.allCases.count)
    }

    @Test("display labels are human-readable")
    func displayLabels() {
        #expect(AppBadgeMode.count.displayLabel == "Count")
        #expect(AppBadgeMode.indicator.displayLabel == "Indicator")
        #expect(AppBadgeMode.off.displayLabel == "Off")
    }

    @Test("default mode is count")
    func defaultMode() {
        #expect(AppBadgeMode.defaultMode == .count)
    }

    @Test("rawValue round-trips for all cases")
    func rawValueRoundTrip() {
        for mode in AppBadgeMode.allCases {
            let recreated = AppBadgeMode(rawValue: mode.rawValue)
            #expect(recreated == mode)
        }
    }

    @Test("invalid rawValue returns nil")
    func invalidRawValue() {
        #expect(AppBadgeMode(rawValue: "invalid") == nil)
        #expect(AppBadgeMode(rawValue: "") == nil)
    }
}
