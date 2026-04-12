import Foundation
@testable import RSSApp

final class MockOPMLService: OPMLServing, @unchecked Sendable {
    var entriesToReturn: [OPMLFeedEntry] = []
    var parseSkippedCountToReturn: Int = 0
    var dataToReturn = Data()
    var errorToThrow: (any Error)?
    var lastGeneratedGroupedFeeds: [GroupedFeed]?

    func parseOPML(_ data: Data) throws -> OPMLParseResult {
        if let error = errorToThrow { throw error }
        return OPMLParseResult(entries: entriesToReturn, parseSkippedCount: parseSkippedCountToReturn)
    }

    func generateOPML(from feeds: [SubscribedFeed]) throws -> Data {
        if let error = errorToThrow { throw error }
        return dataToReturn
    }

    func generateOPML(from groupedFeeds: [GroupedFeed]) throws -> Data {
        if let error = errorToThrow { throw error }
        lastGeneratedGroupedFeeds = groupedFeeds
        return dataToReturn
    }
}
