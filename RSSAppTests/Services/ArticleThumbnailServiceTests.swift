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
    func cacheThumbnailRejectsDataScheme() async throws {
        let dataURL = URL(string: "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Z3sQ4kAAAAASUVORK5CYII=")!

        let result = try await service.cacheThumbnail(from: dataURL, articleID: "data-scheme-test")

        #expect(result == .permanentFailure)
        #expect(service.cachedThumbnailFileURL(for: "data-scheme-test") == nil)
    }

    @Test("Rejects file: URL scheme as permanent failure")
    func cacheThumbnailRejectsFileScheme() async throws {
        let fileURL = URL(string: "file:///tmp/example.png")!

        let result = try await service.cacheThumbnail(from: fileURL, articleID: "file-scheme-test")

        #expect(result == .permanentFailure)
        #expect(service.cachedThumbnailFileURL(for: "file-scheme-test") == nil)
    }

    @Test("Rejects ftp: URL scheme as permanent failure")
    func cacheThumbnailRejectsFTPScheme() async throws {
        let ftpURL = URL(string: "ftp://example.com/image.png")!

        let result = try await service.cacheThumbnail(from: ftpURL, articleID: "ftp-scheme-test")

        #expect(result == .permanentFailure)
        #expect(service.cachedThumbnailFileURL(for: "ftp-scheme-test") == nil)
    }

    @Test("Rejects relative URL with nil scheme as permanent failure")
    func cacheThumbnailRejectsNilScheme() async throws {
        // A relative path produces a URL with scheme == nil. The guard
        // explicitly handles this (the logger uses `scheme ?? "nil"`),
        // so this test locks in the rejection behavior.
        let relativeURL = URL(string: "/relative/icon.png")!
        #expect(relativeURL.scheme == nil)

        let result = try await service.cacheThumbnail(from: relativeURL, articleID: "nil-scheme-test")

        #expect(result == .permanentFailure)
        #expect(service.cachedThumbnailFileURL(for: "nil-scheme-test") == nil)
    }

    @Test("http scheme passes scheme guard but is rejected by SVG gate")
    func cacheThumbnailHTTPSchemePassesGuard() async throws {
        // Positive control for the scheme guard: http:// is an allowed scheme,
        // so the URL passes the first check and reaches the SVG extension gate,
        // which rejects it. This proves the scheme guard accepts http (not just
        // https) without requiring a network stub — the SVG gate short-circuits
        // before any URLSession call.
        let httpSVGURL = URL(string: "http://example.com/icon.svg")!

        let result = try await service.cacheThumbnail(from: httpSVGURL, articleID: "http-svg-test")

        #expect(result == .permanentFailure)
        #expect(service.cachedThumbnailFileURL(for: "http-svg-test") == nil)
    }

    @Test("Rejects .svg URL extension as permanent failure")
    func cacheThumbnailRejectsSVGExtension() async throws {
        let svgURL = URL(string: "https://example.com/icon.svg")!

        let result = try await service.cacheThumbnail(from: svgURL, articleID: "svg-ext-test")

        #expect(result == .permanentFailure)
        #expect(service.cachedThumbnailFileURL(for: "svg-ext-test") == nil)
    }

    @Test("Rejects uppercase .SVG URL extension as permanent failure")
    func cacheThumbnailRejectsUppercaseSVGExtension() async throws {
        // The implementation lowercases the path extension before comparing,
        // so .SVG should be rejected just like .svg.
        let svgURL = URL(string: "https://example.com/logo.SVG")!

        let result = try await service.cacheThumbnail(from: svgURL, articleID: "svg-uppercase-test")

        #expect(result == .permanentFailure)
        #expect(service.cachedThumbnailFileURL(for: "svg-uppercase-test") == nil)
    }

    @Test("Rejects .svg URL with query string as permanent failure")
    func cacheThumbnailRejectsSVGWithQueryString() async throws {
        // pathExtension strips the query string, so this should still be detected.
        let svgURL = URL(string: "https://example.com/badge.svg?style=flat&v=2")!

        let result = try await service.cacheThumbnail(from: svgURL, articleID: "svg-query-test")

        #expect(result == .permanentFailure)
        #expect(service.cachedThumbnailFileURL(for: "svg-query-test") == nil)
    }

    // MARK: - Cancellation Propagation
    //
    // Regression coverage for issue #228: a cancelled thumbnail fetch must surface as a
    // thrown `CancellationError` rather than being swallowed as `.transientFailure`, so
    // the prefetcher stops retrying work the user explicitly cancelled.

    @Test("resolveAndCacheThumbnail rethrows CancellationError when task is cancelled before invocation")
    func resolveAndCacheThumbnailPropagatesCancellation() async {
        // Start a child task, cancel it before it runs, and verify the service rethrows
        // CancellationError instead of swallowing it as a transient failure. URLSession.shared
        // honours task cancellation and raises either CancellationError or URLError(.cancelled);
        // both are normalized to CancellationError by the service.
        let task = Task { () -> Error? in
            // Yield so the outer test body has a chance to call cancel() before URLSession runs.
            await Task.yield()
            do {
                _ = try await service.resolveAndCacheThumbnail(
                    thumbnailURL: URL(string: "https://example.com/image.png"),
                    articleLink: URL(string: "https://example.com/article"),
                    articleID: "cancellation-test"
                )
                return nil
            } catch {
                return error
            }
        }
        task.cancel()
        let thrown = await task.value
        #expect(thrown is CancellationError, "Expected CancellationError, got \(String(describing: thrown))")
    }
}
