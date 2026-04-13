import BackgroundTasks
import Foundation
import os

/// Which `BGTaskScheduler` task flavor a given `BackgroundRefreshSettings`
/// combination maps to. `BGAppRefreshTask` is best for frequent short windows;
/// `BGProcessingTask` supports `requiresNetworkConnectivity` /
/// `requiresExternalPower`, so any constraint tightening beyond the default
/// "any network, any power" pushes us to it. Note that
/// `requiresNetworkConnectivity` only guarantees *some* network, not Wi-Fi —
/// runtime Wi-Fi enforcement is handled by `BackgroundRefreshCoordinator`.
enum BackgroundTaskType: Sendable, Equatable {
    case appRefresh
    case processing
}

/// Registers background task launch handlers with `BGTaskScheduler` and
/// submits refresh requests based on the user's `BackgroundRefreshSettings`.
///
/// Registration must happen in `RSSAppApp.init()` before the App's
/// `application(_:didFinishLaunchingWithOptions:)` returns — iOS rejects any
/// `submit(_:)` for an unregistered identifier. Both task identifiers are
/// always registered at launch even if background refresh is disabled, so a
/// later enable can `submit` without needing to re-register.
enum BackgroundRefreshScheduler {

    private static let logger = Logger(category: "BackgroundRefreshScheduler")

    /// Guards against double-registration. `BGTaskScheduler.register` is
    /// single-shot per identifier per process launch; a second call with the
    /// same identifier crashes the framework. Today only `RSSAppApp.init()`
    /// calls this, but the flag makes a future refactor that accidentally
    /// calls it twice fail loudly with an `assertionFailure` instead of
    /// crashing inside BackgroundTasks.
    ///
    /// RATIONALE: `nonisolated(unsafe)` is correct here because
    /// `registerLaunchHandlers` is only ever called from `RSSAppApp.init()`,
    /// which runs on `@MainActor` (the `App` protocol is `@MainActor`). The
    /// guard logic runs before any `Task` has been spawned from the
    /// coordinator, so there is no concurrent reader. The runtime
    /// `assertionFailure` catches future refactors that accidentally add a
    /// second call.
    nonisolated(unsafe) private static var registered = false

    /// Task identifier for `BGAppRefreshTaskRequest`. Must also appear in
    /// `BGTaskSchedulerPermittedIdentifiers` in Info.plist.
    static let appRefreshTaskIdentifier = "com.nicholas-lonsinger.rss-app.refresh"

    /// Task identifier for `BGProcessingTaskRequest`. Must also appear in
    /// `BGTaskSchedulerPermittedIdentifiers` in Info.plist.
    static let processingTaskIdentifier = "com.nicholas-lonsinger.rss-app.refresh.processing"

    // MARK: - Registration

    /// Registers both task identifiers with `BGTaskScheduler`. Must be called
    /// from `RSSAppApp.init()` before `didFinishLaunchingWithOptions` returns.
    ///
    /// - Parameter coordinator: The coordinator that handles launched tasks.
    ///   Captured strongly because the coordinator is owned by `RSSAppApp` for
    ///   the entire process lifetime — there is no release path that would
    ///   leave a launch handler referring to a deallocated coordinator.
    static func registerLaunchHandlers(coordinator: BackgroundRefreshCoordinator) {
        guard !registered else {
            logger.fault("registerLaunchHandlers called twice — BGTaskScheduler.register is single-shot per identifier and will crash on re-registration")
            assertionFailure("BackgroundRefreshScheduler.registerLaunchHandlers called twice")
            return
        }
        registered = true

        let appRefreshRegistered = BGTaskScheduler.shared.register(
            forTaskWithIdentifier: appRefreshTaskIdentifier,
            using: nil
        ) { task in
            coordinator.handle(task)
        }

        let processingRegistered = BGTaskScheduler.shared.register(
            forTaskWithIdentifier: processingTaskIdentifier,
            using: nil
        ) { task in
            coordinator.handle(task)
        }

        if !appRefreshRegistered {
            // RATIONALE: BGTaskScheduler.register always returns false on Simulator
            // (Apple does not support BGTaskScheduler there). assertionFailure is
            // suppressed on Simulator to avoid crashing every debug launch for an
            // expected, non-actionable condition; the .fault log is downgraded to
            // .debug so it remains visible when streaming but doesn't pollute the
            // console on routine runs.
            #if targetEnvironment(simulator)
            logger.debug("BGAppRefreshTask registration returned false on Simulator (expected — BGTaskScheduler is unavailable on Simulator)")
            #else
            logger.fault("Failed to register BGAppRefreshTask identifier '\(appRefreshTaskIdentifier, privacy: .public)' — check Info.plist BGTaskSchedulerPermittedIdentifiers")
            assertionFailure("Failed to register BGAppRefreshTask identifier '\(appRefreshTaskIdentifier)': check Info.plist BGTaskSchedulerPermittedIdentifiers")
            #endif
        }
        if !processingRegistered {
            // RATIONALE: Same as appRefreshRegistered above — expected false on Simulator.
            #if targetEnvironment(simulator)
            logger.debug("BGProcessingTask registration returned false on Simulator (expected — BGTaskScheduler is unavailable on Simulator)")
            #else
            logger.fault("Failed to register BGProcessingTask identifier '\(processingTaskIdentifier, privacy: .public)' — check Info.plist BGTaskSchedulerPermittedIdentifiers")
            assertionFailure("Failed to register BGProcessingTask identifier '\(processingTaskIdentifier)': check Info.plist BGTaskSchedulerPermittedIdentifiers")
            #endif
        }
        logger.notice("Background task launch handlers registered")
    }

    // MARK: - Scheduling

    /// Submits a refresh request using the current `BackgroundRefreshSettings`.
    /// If background refresh is disabled, cancels any pending requests instead.
    ///
    /// Call from `RSSAppApp` after launch, after a completed refresh (to seed
    /// the next cycle), and after the user changes any background refresh
    /// setting.
    ///
    /// - Throws: Rethrows any error from `BGTaskScheduler.submit(_:)`. Callers
    ///   that react to user input (the settings view) should catch and
    ///   surface the error; launch-seed and post-run re-seed callers can
    ///   silently log.
    static func scheduleNextRefresh(now: Date = Date()) throws {
        guard BackgroundRefreshSettings.isEnabled else {
            logger.debug("scheduleNextRefresh() called while disabled; cancelling all")
            cancelAll()
            return
        }

        let interval = BackgroundRefreshSettings.interval
        let network = BackgroundRefreshSettings.networkRequirement
        let power = BackgroundRefreshSettings.powerRequirement
        let taskType = decideTaskType(interval: interval, network: network, power: power)
        let earliestBegin = now.addingTimeInterval(interval.timeInterval)

        // Cancel the unused identifier so only the chosen one is queued.
        switch taskType {
        case .appRefresh:
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: processingTaskIdentifier)
            let request = BGAppRefreshTaskRequest(identifier: appRefreshTaskIdentifier)
            request.earliestBeginDate = earliestBegin
            try submit(request)
        case .processing:
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: appRefreshTaskIdentifier)
            let request = BGProcessingTaskRequest(identifier: processingTaskIdentifier)
            request.earliestBeginDate = earliestBegin
            request.requiresNetworkConnectivity = true
            request.requiresExternalPower = (power == .chargingOnly)
            try submit(request)
        }
    }

    /// Cancels all pending refresh task requests. Called when the user toggles
    /// background refresh off or uninstalls the feature.
    static func cancelAll() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: appRefreshTaskIdentifier)
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: processingTaskIdentifier)
        logger.notice("Background refresh task requests cancelled")
    }

    // MARK: - Decision Logic

    /// Pure function mapping a settings combination to the task flavor that
    /// best supports it. Exercised by `BackgroundRefreshSchedulerTests`.
    ///
    /// Rule:
    /// - If the user requires Wi-Fi Only OR Charging Only: use
    ///   `BGProcessingTask`, which supports `requiresNetworkConnectivity`
    ///   and `requiresExternalPower`. Note: `requiresNetworkConnectivity`
    ///   only guarantees that *some* network is reachable — it does not
    ///   constrain the task to Wi-Fi. Runtime Wi-Fi enforcement lives in
    ///   `BackgroundRefreshCoordinator.handle(_:)`, which checks the current
    ///   `NWPath` via `NetworkMonitorService.currentPathIsWiFi()` before
    ///   dispatching the refresh loop.
    /// - Otherwise, if the interval is 1 hour or shorter: use
    ///   `BGAppRefreshTask`, which the system schedules more frequently for
    ///   short refresh windows.
    /// - Otherwise (long interval with no constraint tightening): use
    ///   `BGProcessingTask`, which is better suited to infrequent long-window
    ///   wakeups.
    static func decideTaskType(
        interval: BackgroundRefreshInterval,
        network: BackgroundRefreshNetworkRequirement,
        power: BackgroundRefreshPowerRequirement
    ) -> BackgroundTaskType {
        if network == .wifiOnly || power == .chargingOnly {
            return .processing
        }
        switch interval {
        case .fifteenMinutes, .thirtyMinutes, .oneHour:
            return .appRefresh
        case .twoHours, .fourHours, .eightHours:
            return .processing
        }
    }

    // MARK: - Private

    private static func submit(_ request: BGTaskRequest) throws {
        do {
            try BGTaskScheduler.shared.submit(request)
            logger.notice("Submitted background refresh request '\(request.identifier, privacy: .public)' earliestBeginDate=\(request.earliestBeginDate?.description ?? "nil", privacy: .public)")
        } catch let error as BGTaskScheduler.Error where error.code == .unavailable {
            // .unavailable is expected on Simulator and when the user has disabled
            // Background App Refresh in Settings — neither is a bug. Log at .debug
            // so it's visible when actively streaming logs but doesn't surface as
            // an error in routine operation.
            logger.debug("Background refresh submission unavailable for '\(request.identifier, privacy: .public)' (Simulator or Background App Refresh disabled in Settings): \(error, privacy: .public)")
            throw error
        } catch {
            logger.error("Failed to submit background refresh request '\(request.identifier, privacy: .public)': \(error, privacy: .public)")
            throw error
        }
    }
}
