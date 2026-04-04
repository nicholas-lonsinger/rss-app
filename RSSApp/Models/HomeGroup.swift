import Foundation

/// Represents a top-level group on the Home screen.
///
/// The three fixed cases cover the initial launch groups. If user-created groups
/// (e.g., folders, tags) are needed in the future, the design would likely move to
/// a protocol or struct-based approach, since `CaseIterable` conformance cannot be
/// synthesized for enums with associated values.
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
