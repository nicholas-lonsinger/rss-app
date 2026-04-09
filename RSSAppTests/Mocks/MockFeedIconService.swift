import Foundation
import UIKit
@testable import RSSApp

final class MockFeedIconService: FeedIconResolving, @unchecked Sendable {

    var candidateURLs: [URL] = []
    var cacheResult = true
    var cachedFileURL: URL?
    var loadValidatedIconResult: UIImage?
    /// When set, `loadValidatedIcon` returns this on the second and subsequent calls.
    /// Used to simulate on-view resolution: first call returns nil (cache miss), then
    /// after `resolveAndCacheIcon` runs, the second call returns the resolved image.
    var loadValidatedIconResultAfterResolve: UIImage?
    var resolveCallCount = 0
    var cacheCallCount = 0
    var resolveAndCacheCallCount = 0
    var resolveAndCacheResult: URL?
    var deleteCallCount = 0
    var loadValidatedIconCallCount = 0
    var resolveAndCacheFeedIDs: [UUID] = []

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

    func loadValidatedIcon(for feedID: UUID) async -> UIImage? {
        loadValidatedIconCallCount += 1
        // After resolveAndCacheIcon has been called, return the post-resolve result
        // to simulate the icon now being available in cache.
        if resolveAndCacheCallCount > 0, let afterResolve = loadValidatedIconResultAfterResolve {
            return afterResolve
        }
        return loadValidatedIconResult
    }

    func resolveAndCacheIcon(feedSiteURL: URL?, feedImageURL: URL?, feedID: UUID) async -> URL? {
        resolveAndCacheCallCount += 1
        resolveAndCacheFeedIDs.append(feedID)
        return resolveAndCacheResult
    }

    func deleteCachedIcon(for feedID: UUID) {
        deleteCallCount += 1
    }
}
