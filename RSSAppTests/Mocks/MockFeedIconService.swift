import Foundation
import UIKit
@testable import RSSApp

final class MockFeedIconService: FeedIconResolving, @unchecked Sendable {

    var candidateURLs: [URL] = []
    /// Controls the `cacheIcon` result — nil means failure, a non-nil value
    /// means success with that background style. Defaults to `.dark` to match
    /// the pre-classifier behavior where the black tile was always rendered.
    var cacheBackgroundStyleResult: FeedIconBackgroundStyle? = .dark
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
    /// the tuple of the resolved URL and the background style to return.
    var resolveAndCacheResult: (url: URL, backgroundStyle: FeedIconBackgroundStyle)?
    /// Controls the `classifyCachedIconBackgroundStyle` result — nil means
    /// "couldn't classify" (default). Used to test the issue #342 back-fill
    /// path in `FeedRefreshService.resolveAndCacheIconIfNeeded`.
    var classifyCachedIconResult: FeedIconBackgroundStyle?
    var classifyCachedIconCallCount = 0
    var classifyCachedIconFeedIDs: [UUID] = []
    var deleteCallCount = 0
    var loadValidatedIconCallCount = 0
    var resolveAndCacheFeedIDs: [UUID] = []

    func resolveIconCandidates(feedSiteURL: URL?, feedImageURL: URL?) async -> [URL] {
        resolveCallCount += 1
        return candidateURLs
    }

    func cacheIcon(from remoteURL: URL, feedID: UUID) async -> FeedIconBackgroundStyle? {
        cacheCallCount += 1
        return cacheBackgroundStyleResult
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

    func resolveAndCacheIcon(feedSiteURL: URL?, feedImageURL: URL?, feedID: UUID) async -> (url: URL, backgroundStyle: FeedIconBackgroundStyle)? {
        resolveAndCacheCallCount += 1
        resolveAndCacheFeedIDs.append(feedID)
        return resolveAndCacheResult
    }

    func classifyCachedIconBackgroundStyle(for feedID: UUID) async -> FeedIconBackgroundStyle? {
        classifyCachedIconCallCount += 1
        classifyCachedIconFeedIDs.append(feedID)
        return classifyCachedIconResult
    }

    func deleteCachedIcon(for feedID: UUID) {
        deleteCallCount += 1
    }
}
