import Foundation
@testable import RSSApp

final class MockFeedIconService: FeedIconResolving, @unchecked Sendable {

    var candidateURLs: [URL] = []
    var cacheResult = true
    var cachedFileURL: URL?
    var resolveCallCount = 0
    var cacheCallCount = 0
    var resolveAndCacheCallCount = 0
    var resolveAndCacheResult: URL?
    var deleteCallCount = 0

    func resolveIconCandidates(feedSiteURL: URL?, feedImageURL: URL?) async -> [URL] {
        resolveCallCount += 1
        return candidateURLs
    }

    func cacheIcon(from remoteURL: URL, feedID: UUID) async -> Bool {
        cacheCallCount += 1
        return cacheResult
    }

    func cachedIconFileURL(for feedID: UUID) -> URL? {
        cachedFileURL
    }

    func resolveAndCacheIcon(feedSiteURL: URL?, feedImageURL: URL?, feedID: UUID) async -> URL? {
        resolveAndCacheCallCount += 1
        return resolveAndCacheResult
    }

    func deleteCachedIcon(for feedID: UUID) {
        deleteCallCount += 1
    }
}
