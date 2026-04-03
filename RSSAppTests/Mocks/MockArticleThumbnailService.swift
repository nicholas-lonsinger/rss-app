import Foundation
@testable import RSSApp

final class MockArticleThumbnailService: ArticleThumbnailCaching, @unchecked Sendable {

    var cacheResult = true
    var cachedFileURL: URL?
    var cacheCallCount = 0
    var deleteCallCount = 0
    var cachedArticleIDs: [String] = []

    func cacheThumbnail(from remoteURL: URL, articleID: String) async -> Bool {
        cacheCallCount += 1
        cachedArticleIDs.append(articleID)
        return cacheResult
    }

    func cachedThumbnailFileURL(for articleID: String) -> URL? {
        cachedFileURL
    }

    func deleteCachedThumbnail(for articleID: String) {
        deleteCallCount += 1
    }
}
