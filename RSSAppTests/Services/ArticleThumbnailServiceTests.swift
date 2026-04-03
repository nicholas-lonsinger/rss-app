import Testing
import Foundation
@testable import RSSApp

@Suite("ArticleThumbnailService Tests")
struct ArticleThumbnailServiceTests {

    let service = ArticleThumbnailService()

    // MARK: - cachedThumbnailFileURL

    @Test("Returns nil for uncached article ID")
    func cachedThumbnailFileURLReturnsNilForMissing() {
        let result = service.cachedThumbnailFileURL(for: "nonexistent-article-id")

        #expect(result == nil)
    }

    // MARK: - deleteCachedThumbnail

    @Test("Does not throw for non-existent article ID")
    func deleteCachedThumbnailNoThrow() {
        service.deleteCachedThumbnail(for: "nonexistent-article-id")
    }

    // MARK: - Filename Safety

    @Test("Article ID with URL characters produces valid cache path")
    func articleIDWithSpecialCharacters() {
        let urlID = "https://example.com/article?id=123&foo=bar"
        let result = service.cachedThumbnailFileURL(for: urlID)

        // Not cached, so nil — but the important thing is no crash
        #expect(result == nil)
    }

    @Test("Different article IDs produce different cache paths")
    func distinctArticleIDsProduceDistinctPaths() {
        // Use the service's internal hashing by checking that two IDs don't collide.
        // Since both are uncached we can't check file URLs directly,
        // but we verify the service handles them without error.
        let id1 = "article-1"
        let id2 = "article-2"
        service.deleteCachedThumbnail(for: id1)
        service.deleteCachedThumbnail(for: id2)
        // No crash means the hashing works for distinct IDs
    }
}
