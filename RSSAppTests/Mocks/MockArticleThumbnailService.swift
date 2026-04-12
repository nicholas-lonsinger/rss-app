import Foundation
@testable import RSSApp

// RATIONALE: @unchecked Sendable is safe because all mutable state is protected by `lock`.
// ThumbnailPrefetchService calls resolveAndCacheThumbnail from concurrent task group children,
// so the lock is required to prevent data races on counters and arrays.
final class MockArticleThumbnailService: ArticleThumbnailCaching, @unchecked Sendable {

    private let lock = NSLock()

    var cacheResult: ThumbnailCacheResult = .cached
    var resolveResult: ThumbnailCacheResult = .cached
    /// When `true`, `cacheThumbnail` and `resolveAndCacheThumbnail` throw `CancellationError`
    /// instead of returning. Used to exercise cancellation propagation paths.
    var throwCancellation = false
    var cachedFileURL: URL?

    private var _cacheCallCount = 0
    private var _resolveCallCount = 0
    private var _deleteCallCount = 0
    private var _cachedArticleIDs: [String] = []
    private var _deletedArticleIDs: [String] = []

    var cacheCallCount: Int { lock.withLock { _cacheCallCount } }
    var resolveCallCount: Int { lock.withLock { _resolveCallCount } }
    var deleteCallCount: Int { lock.withLock { _deleteCallCount } }
    var cachedArticleIDs: [String] { lock.withLock { _cachedArticleIDs } }
    var deletedArticleIDs: [String] { lock.withLock { _deletedArticleIDs } }

    func cacheThumbnail(from remoteURL: URL, articleID: String) async throws(CancellationError) -> ThumbnailCacheResult {
        lock.withLock {
            _cacheCallCount += 1
            _cachedArticleIDs.append(articleID)
        }
        if throwCancellation {
            throw CancellationError()
        }
        return cacheResult
    }

    func resolveAndCacheThumbnail(thumbnailURL: URL?, articleLink: URL?, articleID: String) async throws(CancellationError) -> ThumbnailCacheResult {
        lock.withLock {
            _resolveCallCount += 1
            _cachedArticleIDs.append(articleID)
        }
        if throwCancellation {
            throw CancellationError()
        }
        return resolveResult
    }

    func cachedThumbnailFileURL(for articleID: String) -> URL? {
        cachedFileURL
    }

    func deleteCachedThumbnail(for articleID: String) {
        lock.withLock {
            _deleteCallCount += 1
            _deletedArticleIDs.append(articleID)
        }
    }
}
