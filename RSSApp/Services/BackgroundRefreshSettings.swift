import Foundation
import os

// MARK: - Interval

/// Supported background refresh intervals. Values are stored in seconds.
enum BackgroundRefreshInterval: Int, CaseIterable, Identifiable, Sendable {
    case fifteenMinutes = 900
    case thirtyMinutes = 1_800
    case oneHour = 3_600
    case twoHours = 7_200
    case fourHours = 14_400
    case eightHours = 28_800

    var id: Int { rawValue }

    var displayLabel: String {
        switch self {
        case .fifteenMinutes: return "15 minutes"
        case .thirtyMinutes: return "30 minutes"
        case .oneHour: return "1 hour"
        case .twoHours: return "2 hours"
        case .fourHours: return "4 hours"
        case .eightHours: return "8 hours"
        }
    }

    /// Seconds between scheduled refreshes. Used as `earliestBeginDate` offset.
    var timeInterval: TimeInterval { TimeInterval(rawValue) }

    static let `default`: BackgroundRefreshInterval = .oneHour
}

// MARK: - Network requirement

/// Network type required for background refresh to execute.
enum BackgroundRefreshNetworkRequirement: String, CaseIterable, Identifiable, Sendable {
    case wifiOnly
    case wifiAndCellular

    var id: String { rawValue }

    var displayLabel: String {
        switch self {
        case .wifiOnly: return "Wi-Fi Only"
        case .wifiAndCellular: return "Wi-Fi & Cellular"
        }
    }

    static let `default`: BackgroundRefreshNetworkRequirement = .wifiOnly
}

// MARK: - Power requirement

/// Power state required for background refresh to execute.
enum BackgroundRefreshPowerRequirement: String, CaseIterable, Identifiable, Sendable {
    case chargingOnly
    case anytime

    var id: String { rawValue }

    var displayLabel: String {
        switch self {
        case .chargingOnly: return "Charging Only"
        case .anytime: return "Anytime"
        }
    }

    static let `default`: BackgroundRefreshPowerRequirement = .chargingOnly
}

// MARK: - Settings Namespace

/// Persists the user's background refresh preferences (enabled toggle,
/// interval, network requirement, power requirement) in `UserDefaults`.
///
/// Defaults match issue #76: enabled, 1 hour, Wi-Fi Only, Charging Only.
enum BackgroundRefreshSettings {

    private static let logger = Logger(category: "BackgroundRefreshSettings")

    private static let enabledKey = "backgroundRefreshEnabled"
    private static let intervalKey = "backgroundRefreshIntervalSeconds"
    private static let networkRequirementKey = "backgroundRefreshNetworkRequirement"
    private static let powerRequirementKey = "backgroundRefreshPowerRequirement"

    /// Whether background refresh should run at all. Defaults to `true`.
    static var isEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: enabledKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: enabledKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: enabledKey)
            logger.notice("Background refresh enabled changed to \(newValue, privacy: .public)")
        }
    }

    /// Minimum interval between refreshes. Defaults to `.oneHour`. Unknown
    /// stored values fall back to the default so a corrupt preference cannot
    /// cause scheduling to stall.
    static var interval: BackgroundRefreshInterval {
        get {
            guard UserDefaults.standard.object(forKey: intervalKey) != nil else {
                return .default
            }
            let stored = UserDefaults.standard.integer(forKey: intervalKey)
            return BackgroundRefreshInterval(rawValue: stored) ?? .default
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: intervalKey)
            logger.notice("Background refresh interval changed to \(newValue.displayLabel, privacy: .public)")
        }
    }

    /// Network type required. Defaults to `.wifiOnly`.
    static var networkRequirement: BackgroundRefreshNetworkRequirement {
        get {
            guard let stored = UserDefaults.standard.string(forKey: networkRequirementKey),
                  let value = BackgroundRefreshNetworkRequirement(rawValue: stored) else {
                return .default
            }
            return value
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: networkRequirementKey)
            logger.notice("Background refresh network requirement changed to \(newValue.displayLabel, privacy: .public)")
        }
    }

    /// Power state required. Defaults to `.chargingOnly`.
    static var powerRequirement: BackgroundRefreshPowerRequirement {
        get {
            guard let stored = UserDefaults.standard.string(forKey: powerRequirementKey),
                  let value = BackgroundRefreshPowerRequirement(rawValue: stored) else {
                return .default
            }
            return value
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: powerRequirementKey)
            logger.notice("Background refresh power requirement changed to \(newValue.displayLabel, privacy: .public)")
        }
    }
}
