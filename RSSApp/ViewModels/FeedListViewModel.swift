import Foundation
import os

@MainActor
@Observable
final class FeedListViewModel {

    private static let logger = Logger(
        subsystem: "com.nicholas-lonsinger.rss-app",
        category: "FeedListViewModel"
    )

    var feeds: [SubscribedFeed] = []

    private let feedStorage: FeedStoring

    init(feedStorage: FeedStoring = FeedStorageService()) {
        self.feedStorage = feedStorage
    }

    func loadFeeds() {
        feeds = feedStorage.loadFeeds()
        Self.logger.debug("Loaded \(self.feeds.count, privacy: .public) feeds")
    }

    func removeFeed(_ feed: SubscribedFeed) {
        feeds.removeAll { $0.id == feed.id }
        feedStorage.saveFeeds(feeds)
        Self.logger.notice("Removed feed '\(feed.title, privacy: .public)'")
    }

    func removeFeed(at offsets: IndexSet) {
        let removed = offsets.map { feeds[$0] }
        feeds.remove(atOffsets: offsets)
        feedStorage.saveFeeds(feeds)
        for feed in removed {
            Self.logger.notice("Removed feed '\(feed.title, privacy: .public)'")
        }
    }
}
