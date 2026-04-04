import Foundation

/// Represents a top-level group on the Home screen.
///
/// The three fixed cases cover the initial launch groups. The enum-based approach
/// accommodates future user-created groups (e.g., folders, tags) by adding new cases
/// with associated values.
enum HomeGroup: Hashable, Identifiable, CaseIterable {
    case allArticles
    case unreadArticles
    case allFeeds

    var id: String {
        switch self {
        case .allArticles: return "all-articles"
        case .unreadArticles: return "unread-articles"
        case .allFeeds: return "all-feeds"
        }
    }

    var title: String {
        switch self {
        case .allArticles: return "All Articles"
        case .unreadArticles: return "Unread Articles"
        case .allFeeds: return "All Feeds"
        }
    }

    var systemImage: String {
        switch self {
        case .allArticles: return "doc.text"
        case .unreadArticles: return "envelope.badge"
        case .allFeeds: return "list.bullet"
        }
    }
}
