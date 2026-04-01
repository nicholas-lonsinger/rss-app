import Foundation
@testable import RSSApp

final class MockFeedStorageService: FeedStoring, @unchecked Sendable {
    var feeds: [SubscribedFeed] = []

    func loadFeeds() -> [SubscribedFeed] {
        feeds
    }

    func saveFeeds(_ newFeeds: [SubscribedFeed]) {
        feeds = newFeeds
    }

    func addFeed(_ feed: SubscribedFeed) {
        feeds.append(feed)
    }

    func removeFeed(withID id: UUID) {
        feeds.removeAll { $0.id == id }
    }
}
