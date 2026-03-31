import Foundation
@testable import RSSApp

// RATIONALE: @unchecked Sendable is safe because this mock is only used in
// single-threaded test contexts where properties are set before the async call.
final class MockFeedFetchingService: FeedFetching, @unchecked Sendable {
    var feedToReturn: RSSFeed?
    var errorToThrow: (any Error)?

    func fetchFeed(from url: URL) async throws -> RSSFeed {
        if let error = errorToThrow { throw error }
        guard let feed = feedToReturn else {
            throw FeedFetchingError.invalidResponse(statusCode: 0)
        }
        return feed
    }
}
