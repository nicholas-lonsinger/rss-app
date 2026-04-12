import Foundation
import UIKit
@testable import RSSApp

final class MockFeedIconService: FeedIconResolving, @unchecked Sendable {

    var candidateURLs: [URL] = []
    /// Controls the `cacheIcon` result — nil means failure, an analysis value
    /// means success. Defaults to a `dark`-background analysis, matching the
    /// pre-classifier behavior where the black tile is always rendered.
    var cacheAnalysisResult: CachedIconAnalysis? = CachedIconAnalysis(backgroundStyle: .dark)
    var cachedFileURL: URL?
    var loadValidatedIconResult: UIImage?
    /// When set, `loadValidatedIcon` returns this on the second and subsequent calls.
    /// Used to simulate on-view resolution: first call returns nil (cache miss), then
    /// after `resolveAndCacheIcon` runs, the second call returns the resolved image.
    var loadValidatedIconResultAfterResolve: UIImage?
    var resolveCallCount = 0
    var cacheCallCount = 0
    var resolveAndCacheCallCount = 0
    /// Controls the `resolveAndCacheIcon` result — nil means failure, otherwise
    /// the tuple of the resolved URL and the analysis to return.
    var resolveAndCacheResult: (url: URL, analysis: CachedIconAnalysis)?
    var deleteCallCount = 0
    var loadValidatedIconCallCount = 0
    var resolveAndCacheFeedIDs: [UUID] = []

    func resolveIconCandidates(feedSiteURL: URL?, feedImageURL: URL?) async -> [URL] {
        resolveCallCount += 1
        return candidateURLs
    }

    func cacheIcon(from remoteURL: URL, feedID: UUID) async -> CachedIconAnalysis? {
        cacheCallCount += 1
        return cacheAnalysisResult
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

    func resolveAndCacheIcon(feedSiteURL: URL?, feedImageURL: URL?, feedID: UUID) async -> (url: URL, analysis: CachedIconAnalysis)? {
        resolveAndCacheCallCount += 1
        resolveAndCacheFeedIDs.append(feedID)
        return resolveAndCacheResult
    }

    func deleteCachedIcon(for feedID: UUID) {
        deleteCallCount += 1
    }
}
