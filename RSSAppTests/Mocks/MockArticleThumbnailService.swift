import Foundation
@testable import RSSApp

// RATIONALE: @unchecked Sendable is safe because the mock is only used in sequential
// test methods within a single test actor — no concurrent mutation occurs.
final class MockArticleThumbnailService: ArticleThumbnailCaching, @unchecked Sendable {

    var cacheResult = true
    var resolveResult = true
    var cachedFileURL: URL?
    var cacheCallCount = 0
    var resolveCallCount = 0
    var deleteCallCount = 0
    var cachedArticleIDs: [String] = []
    var deletedArticleIDs: [String] = []

    func cacheThumbnail(from remoteURL: URL, articleID: String) async -> Bool {
        cacheCallCount += 1
        cachedArticleIDs.append(articleID)
        return cacheResult
    }

    func resolveAndCacheThumbnail(thumbnailURL: URL?, articleLink: URL?, articleID: String) async -> Bool {
        resolveCallCount += 1
        cachedArticleIDs.append(articleID)
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
