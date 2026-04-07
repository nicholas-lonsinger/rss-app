import Foundation
@testable import RSSApp

// RATIONALE: @unchecked Sendable is safe because the mock is only used in sequential
// test methods within a single test actor — no concurrent mutation occurs.
final class MockArticleThumbnailService: ArticleThumbnailCaching, @unchecked Sendable {

    var cacheResult: ThumbnailCacheResult = .cached
    var resolveResult: ThumbnailCacheResult = .cached
    /// When `true`, `cacheThumbnail` and `resolveAndCacheThumbnail` throw `CancellationError`
    /// instead of returning. Used to exercise cancellation propagation paths.
    var throwCancellation = false
    var cachedFileURL: URL?
    var cacheCallCount = 0
    var resolveCallCount = 0
    var deleteCallCount = 0
    var cachedArticleIDs: [String] = []
    var deletedArticleIDs: [String] = []

    func cacheThumbnail(from remoteURL: URL, articleID: String) async throws(CancellationError) -> ThumbnailCacheResult {
        cacheCallCount += 1
        cachedArticleIDs.append(articleID)
        if throwCancellation {
            throw CancellationError()
        }
        return cacheResult
    }

    func resolveAndCacheThumbnail(thumbnailURL: URL?, articleLink: URL?, articleID: String) async throws(CancellationError) -> ThumbnailCacheResult {
        resolveCallCount += 1
        cachedArticleIDs.append(articleID)
        if throwCancellation {
            throw CancellationError()
        }
        return resolveResult
    }

    func cachedThumbnailFileURL(for articleID: String) -> URL? {
        cachedFileURL
    }

    func deleteCachedThumbnail(for articleID: String) {
        deleteCallCount += 1
        deletedArticleIDs.append(articleID)
    }
}
