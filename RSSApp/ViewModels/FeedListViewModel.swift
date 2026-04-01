import Foundation
import os

@MainActor
@Observable
final class FeedListViewModel {

    private static let logger = Logger(
        subsystem: "com.nicholas-lonsinger.rss-app",
        category: "FeedListViewModel"
    )

    private(set) var feeds: [SubscribedFeed] = []
    var errorMessage: String?

    private let feedStorage: FeedStoring

    init(feedStorage: FeedStoring = FeedStorageService()) {
        self.feedStorage = feedStorage
    }

    func loadFeeds() {
        do {
            feeds = try feedStorage.loadFeeds()
            errorMessage = nil
            Self.logger.debug("Loaded \(self.feeds.count, privacy: .public) feeds")
        } catch {
            errorMessage = "Unable to load your feeds."
            Self.logger.error("Failed to load feeds: \(error, privacy: .public)")
        }
    }

    func removeFeed(_ feed: SubscribedFeed) {
        let previousFeeds = feeds
        feeds.removeAll { $0.id == feed.id }
        do {
            try feedStorage.saveFeeds(feeds)
            Self.logger.notice("Removed feed '\(feed.title, privacy: .public)'")
        } catch {
            feeds = previousFeeds
            errorMessage = "Unable to save changes."
            Self.logger.error("Failed to persist feed removal: \(error, privacy: .public)")
        }
    }

    func removeFeed(at offsets: IndexSet) {
        let previousFeeds = feeds
        let removed = offsets.map { feeds[$0] }
        feeds.remove(atOffsets: offsets)
        do {
            try feedStorage.saveFeeds(feeds)
            for feed in removed {
                Self.logger.notice("Removed feed '\(feed.title, privacy: .public)'")
            }
        } catch {
            feeds = previousFeeds
            errorMessage = "Unable to save changes."
            Self.logger.error("Failed to persist feed removal: \(error, privacy: .public)")
        }
    }
}
