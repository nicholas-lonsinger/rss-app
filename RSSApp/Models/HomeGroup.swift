import Foundation

/// Represents a top-level item on the Home screen.
///
/// The fixed cases cover the built-in groups. The `.feedGroup` associated
/// value represents a user-created group whose feeds' articles are displayed
/// in a cross-feed list filtered to that group.
enum HomeGroup: Hashable, Identifiable {
    case allArticles
    case unreadArticles
    case savedArticles
    case feedGroup(PersistentFeedGroup)
    case allFeeds

    var id: String {
        switch self {
        case .allArticles: return "all-articles"
        case .unreadArticles: return "unread-articles"
        case .savedArticles: return "saved-articles"
        case .feedGroup(let group): return "group-\(group.id.uuidString)"
        case .allFeeds: return "all-feeds"
        }
    }

    var title: String {
        switch self {
        case .allArticles: return "All Articles"
        case .unreadArticles: return "Unread Articles"
        case .savedArticles: return "Saved Articles"
        case .feedGroup(let group): return group.name
        case .allFeeds: return "All Feeds"
        }
    }

    var systemImage: String {
        switch self {
        case .allArticles: return "doc.text"
        case .unreadArticles: return "envelope.badge"
        case .savedArticles: return "bookmark.fill"
        case .feedGroup: return "folder"
        case .allFeeds: return "list.bullet"
        }
    }
}
