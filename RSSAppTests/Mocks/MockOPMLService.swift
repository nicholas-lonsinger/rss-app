import Foundation
@testable import RSSApp

final class MockOPMLService: OPMLServing, @unchecked Sendable {
    var entriesToReturn: [OPMLFeedEntry] = []
    var dataToReturn = Data()
    var errorToThrow: (any Error)?

    func parseOPML(_ data: Data) throws -> [OPMLFeedEntry] {
        if let error = errorToThrow { throw error }
        return entriesToReturn
    }

    func generateOPML(from feeds: [SubscribedFeed]) throws -> Data {
        if let error = errorToThrow { throw error }
        return dataToReturn
    }
}
