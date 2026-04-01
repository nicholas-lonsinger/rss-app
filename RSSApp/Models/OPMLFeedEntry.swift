import Foundation

struct OPMLFeedEntry: Sendable, Equatable {
    let title: String
    let feedURL: URL
    let siteURL: URL?
    let description: String
}
