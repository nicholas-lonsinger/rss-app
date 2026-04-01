import Foundation
import os

protocol FeedStoring: Sendable {
    func loadFeeds() throws -> [SubscribedFeed]
    func saveFeeds(_ feeds: [SubscribedFeed]) throws
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

    func loadFeeds() throws -> [SubscribedFeed] {
        Self.logger.debug("Loading subscribed feeds")
        guard let data = defaults.data(forKey: Self.storageKey) else {
            Self.logger.debug("No stored feeds found")
            return []
        }

        let feeds = try JSONDecoder().decode([SubscribedFeed].self, from: data)
        Self.logger.debug("Loaded \(feeds.count, privacy: .public) feeds")
        return feeds
    }

    func saveFeeds(_ feeds: [SubscribedFeed]) throws {
        let data = try JSONEncoder().encode(feeds)
        defaults.set(data, forKey: Self.storageKey)
        Self.logger.debug("Saved \(feeds.count, privacy: .public) feeds")
    }
}
