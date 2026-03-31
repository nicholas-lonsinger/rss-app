import Foundation

struct RSSFeed: Sendable {
    let title: String
    let link: URL?
    let feedDescription: String
    let articles: [Article]
}
