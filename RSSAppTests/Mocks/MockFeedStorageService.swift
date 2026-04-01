import Foundation
@testable import RSSApp

final class MockFeedStorageService: FeedStoring, @unchecked Sendable {
    var feeds: [SubscribedFeed] = []
    var errorToThrow: (any Error)?

    func loadFeeds() throws -> [SubscribedFeed] {
        if let error = errorToThrow { throw error }
        return feeds
    }

    func saveFeeds(_ newFeeds: [SubscribedFeed]) throws {
        if let error = errorToThrow { throw error }
        feeds = newFeeds
    }
}
