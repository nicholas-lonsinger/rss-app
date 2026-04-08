import Foundation

/// The serialization format of a parsed feed. Exposed so callers (e.g. the
/// add-feed flow) can offer Atom discovery only when the user subscribed to an
/// RSS feed.
enum FeedFormat: Sendable {
    case rss
    case atom
}

struct RSSFeed: Sendable {
    let title: String
    let link: URL?
    let feedDescription: String
    let articles: [Article]
    let lastUpdated: Date?
    let imageURL: URL?
    let format: FeedFormat
}
