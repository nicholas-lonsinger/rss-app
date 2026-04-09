import Testing
@testable import RSSApp

/// Matrix tests for `BackgroundRefreshScheduler.decideTaskType(interval:network:power:)`.
///
/// The rule documented on `decideTaskType`:
/// - Any constraint tightening (Wi-Fi Only OR Charging Only) → `.processing`,
///   because only `BGProcessingTask` natively enforces
///   `requiresNetworkConnectivity` / `requiresExternalPower`.
/// - Otherwise short intervals (≤ 1 hour) → `.appRefresh`, because
///   `BGAppRefreshTask` is best-suited to frequent short windows.
/// - Otherwise long intervals (≥ 2 hours) → `.processing`, because
///   `BGProcessingTask` is better suited to infrequent long-window wakeups.
@Suite("BackgroundRefreshScheduler decideTaskType Tests")
struct BackgroundRefreshSchedulerTests {

    // MARK: - Unconstrained + short interval → appRefresh

    @Test("15 min + any network + any power → appRefresh")
    func fifteenMinutesAnyAny() {
        let result = BackgroundRefreshScheduler.decideTaskType(
            interval: .fifteenMinutes,
            network: .wifiAndCellular,
            power: .anytime
        )
        #expect(result == .appRefresh)
    }

    @Test("1 hour + any network + any power → appRefresh")
    func oneHourAnyAny() {
        let result = BackgroundRefreshScheduler.decideTaskType(
            interval: .oneHour,
            network: .wifiAndCellular,
            power: .anytime
        )
        #expect(result == .appRefresh)
    }

    // MARK: - Wi-Fi Only constraint → processing (regardless of interval)

    @Test("15 min + Wi-Fi only + any power → processing")
    func fifteenMinutesWiFiOnly() {
        let result = BackgroundRefreshScheduler.decideTaskType(
            interval: .fifteenMinutes,
            network: .wifiOnly,
            power: .anytime
        )
        #expect(result == .processing)
    }

    // MARK: - Charging Only constraint → processing (regardless of interval)

    @Test("15 min + any network + charging only → processing")
    func fifteenMinutesChargingOnly() {
        let result = BackgroundRefreshScheduler.decideTaskType(
            interval: .fifteenMinutes,
            network: .wifiAndCellular,
            power: .chargingOnly
        )
        #expect(result == .processing)
    }

    // MARK: - Long interval → processing even without constraints

    @Test("2 hours + any network + any power → processing")
    func twoHoursAnyAny() {
        let result = BackgroundRefreshScheduler.decideTaskType(
            interval: .twoHours,
            network: .wifiAndCellular,
            power: .anytime
        )
        #expect(result == .processing)
    }

    @Test("8 hours + any network + any power → processing")
    func eightHoursAnyAny() {
        let result = BackgroundRefreshScheduler.decideTaskType(
            interval: .eightHours,
            network: .wifiAndCellular,
            power: .anytime
        )
        #expect(result == .processing)
    }

    // MARK: - All-constraints combined → processing

    @Test("8 hours + Wi-Fi only + charging only → processing")
    func eightHoursAllConstrained() {
        let result = BackgroundRefreshScheduler.decideTaskType(
            interval: .eightHours,
            network: .wifiOnly,
            power: .chargingOnly
        )
        #expect(result == .processing)
    }
}
