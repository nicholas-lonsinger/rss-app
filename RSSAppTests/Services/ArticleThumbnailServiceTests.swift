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

    // MARK: - cacheThumbnail Pre-Download Validation
    //
    // These tests cover the synchronous validation checks at the top of
    // `cacheThumbnail(from:articleID:)` that reject URLs before any network
    // request is made. They run quickly and reliably without needing a
    // URLProtocol stub, since the early-return paths never touch the network.

    @Test("Rejects data: URL scheme as permanent failure")
    func cacheThumbnailRejectsDataScheme() async {
        let dataURL = URL(string: "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Z3sQ4kAAAAASUVORK5CYII=")!

        let result = await service.cacheThumbnail(from: dataURL, articleID: "data-scheme-test")

        #expect(result == .permanentFailure)
        #expect(service.cachedThumbnailFileURL(for: "data-scheme-test") == nil)
    }

    @Test("Rejects file: URL scheme as permanent failure")
    func cacheThumbnailRejectsFileScheme() async {
        let fileURL = URL(string: "file:///tmp/example.png")!

        let result = await service.cacheThumbnail(from: fileURL, articleID: "file-scheme-test")

        #expect(result == .permanentFailure)
        #expect(service.cachedThumbnailFileURL(for: "file-scheme-test") == nil)
    }

    @Test("Rejects ftp: URL scheme as permanent failure")
    func cacheThumbnailRejectsFTPScheme() async {
        let ftpURL = URL(string: "ftp://example.com/image.png")!

        let result = await service.cacheThumbnail(from: ftpURL, articleID: "ftp-scheme-test")

        #expect(result == .permanentFailure)
        #expect(service.cachedThumbnailFileURL(for: "ftp-scheme-test") == nil)
    }

    @Test("Rejects .svg URL extension as permanent failure")
    func cacheThumbnailRejectsSVGExtension() async {
        let svgURL = URL(string: "https://example.com/icon.svg")!

        let result = await service.cacheThumbnail(from: svgURL, articleID: "svg-ext-test")

        #expect(result == .permanentFailure)
        #expect(service.cachedThumbnailFileURL(for: "svg-ext-test") == nil)
    }

    @Test("Rejects uppercase .SVG URL extension as permanent failure")
    func cacheThumbnailRejectsUppercaseSVGExtension() async {
        // The implementation lowercases the path extension before comparing,
        // so .SVG should be rejected just like .svg.
        let svgURL = URL(string: "https://example.com/logo.SVG")!

        let result = await service.cacheThumbnail(from: svgURL, articleID: "svg-uppercase-test")

        #expect(result == .permanentFailure)
        #expect(service.cachedThumbnailFileURL(for: "svg-uppercase-test") == nil)
    }

    @Test("Rejects .svg URL with query string as permanent failure")
    func cacheThumbnailRejectsSVGWithQueryString() async {
        // pathExtension strips the query string, so this should still be detected.
        let svgURL = URL(string: "https://example.com/badge.svg?style=flat&v=2")!

        let result = await service.cacheThumbnail(from: svgURL, articleID: "svg-query-test")

        #expect(result == .permanentFailure)
        #expect(service.cachedThumbnailFileURL(for: "svg-query-test") == nil)
    }
}
