import Foundation

/// Controls how the app icon badge displays unread article counts.
enum AppBadgeMode: String, CaseIterable, Identifiable, Sendable {
    /// Badge shows the total number of unread articles (e.g., 42).
    case count

    /// Badge shows a fixed indicator (badge count of 1) when any unread articles exist,
    /// hidden when all are read.
    case indicator

    /// No badge displayed; badge count is set to 0.
    case off

    var id: String { rawValue }

    var displayLabel: String {
        switch self {
        case .count: return "Count"
        case .indicator: return "Indicator"
        case .off: return "Off"
        }
    }

    static let defaultMode: AppBadgeMode = .count
}
