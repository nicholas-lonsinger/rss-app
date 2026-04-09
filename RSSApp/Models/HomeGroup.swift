import Foundation

/// Represents a built-in top-level group on the Home screen.
///
/// The four fixed cases cover the built-in groups. User-created groups
/// (`PersistentFeedGroup`) are rendered in a separate section of `HomeView`
/// and navigate via `GroupDestination`, keeping this enum as a simple
/// `CaseIterable` without associated values.
enum HomeGroup: Hashable, Identifiable, CaseIterable {
    case allArticles
    case unreadArticles
    case savedArticles
    case allFeeds

    var id: String {
        switch self {
        case .allArticles: return "all-articles"
        case .unreadArticles: return "unread-articles"
        case .savedArticles: return "saved-articles"
        case .allFeeds: return "all-feeds"
        }
    }

    var title: String {
        switch self {
        case .allArticles: return "All Articles"
        case .unreadArticles: return "Unread Articles"
        case .savedArticles: return "Saved Articles"
        case .allFeeds: return "All Feeds"
        }
    }

    var systemImage: String {
        switch self {
        case .allArticles: return "doc.text"
        case .unreadArticles: return "envelope.badge"
        case .savedArticles: return "bookmark.fill"
        case .allFeeds: return "list.bullet"
        }
    }
}
