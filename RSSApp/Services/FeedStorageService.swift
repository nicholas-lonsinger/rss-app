import Foundation
import os

protocol FeedStoring: Sendable {
    func loadFeeds() -> [SubscribedFeed]
    func saveFeeds(_ feeds: [SubscribedFeed])
    func addFeed(_ feed: SubscribedFeed)
    func removeFeed(withID id: UUID)
}

// RATIONALE: @unchecked Sendable because UserDefaults is thread-safe but not marked Sendable in Swift 6.
struct FeedStorageService: FeedStoring, @unchecked Sendable {

    private static let logger = Logger(
        subsystem: "com.nicholas-lonsinger.rss-app",
        category: "FeedStorageService"
    )

    private static let storageKey = "subscribedFeeds"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadFeeds() -> [SubscribedFeed] {
        Self.logger.debug("Loading subscribed feeds")
        guard let data = defaults.data(forKey: Self.storageKey) else {
            Self.logger.debug("No stored feeds found")
            return []
        }

        do {
            let feeds = try JSONDecoder().decode([SubscribedFeed].self, from: data)
            Self.logger.debug("Loaded \(feeds.count, privacy: .public) feeds")
            return feeds
        } catch {
            Self.logger.error("Failed to decode stored feeds: \(error, privacy: .public)")
            return []
        }
    }

    func saveFeeds(_ feeds: [SubscribedFeed]) {
        do {
            let data = try JSONEncoder().encode(feeds)
            defaults.set(data, forKey: Self.storageKey)
            Self.logger.debug("Saved \(feeds.count, privacy: .public) feeds")
        } catch {
            Self.logger.error("Failed to encode feeds: \(error, privacy: .public)")
        }
    }

    func addFeed(_ feed: SubscribedFeed) {
        var feeds = loadFeeds()
        feeds.append(feed)
        saveFeeds(feeds)
        Self.logger.notice("Added feed '\(feed.title, privacy: .public)'")
    }

    func removeFeed(withID id: UUID) {
        var feeds = loadFeeds()
        feeds.removeAll { $0.id == id }
        saveFeeds(feeds)
        Self.logger.notice("Removed feed with ID \(id, privacy: .public)")
    }
}
