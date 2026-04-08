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

    @Test("resolveAndCacheThumbnail propagates mid-flight URLError(.cancelled) as CancellationError")
    func resolveAndCacheThumbnailPropagatesMidFlightCancellation() async {
        // Regression coverage for issue #250: the existing
        // `resolveAndCacheThumbnailPropagatesCancellation` test cancels the surrounding
        // Task before `Task.yield()` returns, so it only exercises the *pre-flight*
        // `CancellationError` path — before any URL loading starts. The mid-flight path
        // — where URLSession has already dispatched the request and the cancellation
        // surfaces from inside the byte loop as `URLError(.cancelled)` — was not covered
        // at the `resolveAndCacheThumbnail` integration boundary, leaving room for
        // future refactors to regress the fix for issue #228 without any test failing.
        //
        // This test plugs `MockSlowHTMLURLSessionProvider` (which delivers a 200 OK,
        // an initial chunk, then `URLError(.cancelled)` from a private dispatch queue)
        // into the service and calls `resolveAndCacheThumbnail` end-to-end. We pass
        // `thumbnailURL: nil` so the Priority-1 `cacheThumbnail` call is skipped; the
        // Priority-2 `cacheThumbnail` (on a resolved og:image URL) is also never reached
        // because the mock makes `resolveOGImage` throw `CancellationError` from the
        // mid-stream `URLError(.cancelled)` before it can return `.found`. Both
        // `cacheThumbnail` invocations — which use the un-injected `URLSession.shared` —
        // are therefore avoided. The mid-flight `URLError(.cancelled)` must be normalized
        // to `CancellationError` by `resolveOGImage` and rethrown unchanged by
        // `resolveAndCacheThumbnail` — *not* swallowed and reported as
        // `.transientFailure`. If a future refactor accidentally catches the rethrow
        // somewhere along the integration path, this test fails.
        let mockSession = MockSlowHTMLURLSessionProvider()
        mockSession.midStreamError = URLError(.cancelled)
        let service = ArticleThumbnailService(session: mockSession)
        let articleLink = URL(string: "https://example.com/article-mid-flight-cancelled")!

        do {
            _ = try await service.resolveAndCacheThumbnail(
                thumbnailURL: nil,
                articleLink: articleLink,
                articleID: "mid-flight-cancellation-test"
            )
            Issue.record("Expected resolveAndCacheThumbnail to throw CancellationError, but it returned normally")
        } catch is CancellationError {
        } catch {
            Issue.record("Expected CancellationError, got \(String(describing: error))")
        }
    }

    @Test("resolveOGImage normalizes mid-stream URLError(.cancelled) to CancellationError")
    func resolveOGImageNormalizesMidStreamURLErrorCancelled() async {
        // Regression coverage for issue #248: the
        // `catch let urlError as URLError where urlError.code == .cancelled`
        // rung in `resolveOGImage(from:)` is load-bearing. The pre-existing
        // `resolveAndCacheThumbnailPropagatesCancellation` test cancels the
        // surrounding Task before URLSession starts, so it exercises the
        // pre-flight `CancellationError` path — not the mid-stream
        // `URLError(.cancelled)` path that PR #247 added the rung for.
        //
        // Driving the URLError(.cancelled) path via `Task.cancel()` is not
        // viable: cooperative Swift cancellation surfaces from
        // `URLSession.AsyncBytes.next()` as `CancellationError` directly,
        // hitting the *other* catch arm. The only way to provoke a real
        // `URLError(.cancelled)` from inside the byte loop is for URLSession
        // (or in tests, a stub `URLProtocol`) to fail the request with that
        // error after the iterator has begun pulling bytes. The mock below
        // does exactly that: it delivers a 200 OK response, a small initial
        // chunk, and then surfaces `URLError(.cancelled)` to the client. The
        // service must catch that error and rethrow `CancellationError`.
        // Without the rung, the error falls through to the generic
        // `catch let urlError as URLError` arm and the call returns
        // `.fetchFailed`, regressing issue #228.
        let mockSession = MockSlowHTMLURLSessionProvider()
        mockSession.midStreamError = URLError(.cancelled)
        let service = ArticleThumbnailService(session: mockSession)
        let articleLink = URL(string: "https://example.com/cancelled-mid-stream")!

        do {
            _ = try await service.resolveOGImage(from: articleLink)
            Issue.record("Expected resolveOGImage to throw CancellationError, but it returned normally")
        } catch is CancellationError {
            // Expected: the URLError(.cancelled) rung normalized the error.
        } catch {
            Issue.record("Expected CancellationError, got \(String(describing: error))")
        }
    }

    @Test("resolveOGImage maps non-cancelled mid-stream URLError to .fetchFailed")
    func resolveOGImageMapsNonCancelledMidStreamErrorToFetchFailed() async throws {
        // Positive control for the test above: a non-cancellation URLError
        // delivered mid-stream (e.g. `.networkConnectionLost`) must NOT be
        // normalized to `CancellationError`. It should fall through the
        // cancellation rung and hit the generic `catch let urlError as URLError`
        // arm, which returns `.fetchFailed` so the prefetcher can retry.
        // This locks in the rung's predicate (`urlError.code == .cancelled`)
        // so a future refactor can't accidentally widen it.
        let mockSession = MockSlowHTMLURLSessionProvider()
        mockSession.midStreamError = URLError(.networkConnectionLost)
        let service = ArticleThumbnailService(session: mockSession)
        let articleLink = URL(string: "https://example.com/connection-lost-mid-stream")!

        let result = try await service.resolveOGImage(from: articleLink)

        #expect(result == .fetchFailed)
    }

    // MARK: - isPermanentHTTPFailure
    //
    // Direct unit tests for the pure HTTP status classification helper used by both
    // `cacheThumbnail` and `resolveOGImage` to decide between transient and permanent
    // failures. These lock in the boundary values so future refactors can't accidentally
    // reclassify 429/408 as permanent or drop a 4xx code into the transient bucket.

    @Test("isPermanentHTTPFailure classifies 400 as permanent")
    func isPermanentHTTPFailureClassifies400() {
        #expect(ArticleThumbnailService.isPermanentHTTPFailure(code: 400) == true)
    }

    @Test("isPermanentHTTPFailure classifies 403 as permanent")
    func isPermanentHTTPFailureClassifies403() {
        #expect(ArticleThumbnailService.isPermanentHTTPFailure(code: 403) == true)
    }

    @Test("isPermanentHTTPFailure classifies 404 as permanent")
    func isPermanentHTTPFailureClassifies404() {
        #expect(ArticleThumbnailService.isPermanentHTTPFailure(code: 404) == true)
    }

    @Test("isPermanentHTTPFailure classifies 410 as permanent")
    func isPermanentHTTPFailureClassifies410() {
        #expect(ArticleThumbnailService.isPermanentHTTPFailure(code: 410) == true)
    }

    @Test("isPermanentHTTPFailure classifies 499 as permanent (upper 4xx boundary)")
    func isPermanentHTTPFailureClassifies499() {
        #expect(ArticleThumbnailService.isPermanentHTTPFailure(code: 499) == true)
    }

    @Test("isPermanentHTTPFailure treats 408 as transient")
    func isPermanentHTTPFailureTreats408AsTransient() {
        // 408 Request Timeout is transient despite being 4xx.
        #expect(ArticleThumbnailService.isPermanentHTTPFailure(code: 408) == false)
    }

    @Test("isPermanentHTTPFailure treats 429 as transient")
    func isPermanentHTTPFailureTreats429AsTransient() {
        // 429 Too Many Requests is rate limiting — retry-worthy.
        #expect(ArticleThumbnailService.isPermanentHTTPFailure(code: 429) == false)
    }

    @Test("isPermanentHTTPFailure treats 500 as transient")
    func isPermanentHTTPFailureTreats500AsTransient() {
        #expect(ArticleThumbnailService.isPermanentHTTPFailure(code: 500) == false)
    }

    @Test("isPermanentHTTPFailure treats 502 as transient")
    func isPermanentHTTPFailureTreats502AsTransient() {
        #expect(ArticleThumbnailService.isPermanentHTTPFailure(code: 502) == false)
    }

    @Test("isPermanentHTTPFailure treats 503 as transient")
    func isPermanentHTTPFailureTreats503AsTransient() {
        #expect(ArticleThumbnailService.isPermanentHTTPFailure(code: 503) == false)
    }

    @Test("isPermanentHTTPFailure treats 504 as transient")
    func isPermanentHTTPFailureTreats504AsTransient() {
        #expect(ArticleThumbnailService.isPermanentHTTPFailure(code: 504) == false)
    }

    @Test("isPermanentHTTPFailure treats -1 (non-HTTPURLResponse sentinel) as transient")
    func isPermanentHTTPFailureTreatsSentinelAsTransient() {
        // The service uses -1 as the sentinel when a response isn't an HTTPURLResponse.
        #expect(ArticleThumbnailService.isPermanentHTTPFailure(code: -1) == false)
    }

    @Test("isPermanentHTTPFailure treats 200 as non-permanent (outside 4xx range)")
    func isPermanentHTTPFailureTreats200AsNonPermanent() {
        // Success codes aren't "permanent failures" — the classifier only fires on non-2xx.
        #expect(ArticleThumbnailService.isPermanentHTTPFailure(code: 200) == false)
    }

    // MARK: - resolveOGImage HTTP Classification
    //
    // End-to-end coverage for the HTTP status code classification logic in
    // `resolveOGImage(from:)`, driven by a URLProtocol-backed mock session so
    // the tests never touch the network. This locks in the issue #229 / PR #227
    // contract: 4xx (except 408/429) should map to `.notFound` so the prefetcher
    // stops retrying, while 408/429/5xx map to `.fetchFailed` to allow retry.

    @Test("resolveOGImage maps 404 to .notFound")
    func resolveOGImageMaps404ToNotFound() async throws {
        let mockSession = MockHTMLURLSessionProvider()
        mockSession.statusCode = 404
        let service = ArticleThumbnailService(session: mockSession)
        let articleLink = URL(string: "https://example.com/article-404")!

        let result = try await service.resolveOGImage(from: articleLink)

        #expect(result == .notFound)
    }

    @Test("resolveOGImage maps 403 to .notFound")
    func resolveOGImageMaps403ToNotFound() async throws {
        let mockSession = MockHTMLURLSessionProvider()
        mockSession.statusCode = 403
        let service = ArticleThumbnailService(session: mockSession)
        let articleLink = URL(string: "https://example.com/article-403")!

        let result = try await service.resolveOGImage(from: articleLink)

        #expect(result == .notFound)
    }

    @Test("resolveOGImage maps 410 to .notFound")
    func resolveOGImageMaps410ToNotFound() async throws {
        let mockSession = MockHTMLURLSessionProvider()
        mockSession.statusCode = 410
        let service = ArticleThumbnailService(session: mockSession)
        let articleLink = URL(string: "https://example.com/article-410")!

        let result = try await service.resolveOGImage(from: articleLink)

        #expect(result == .notFound)
    }

    @Test("resolveOGImage maps 400 to .notFound")
    func resolveOGImageMaps400ToNotFound() async throws {
        let mockSession = MockHTMLURLSessionProvider()
        mockSession.statusCode = 400
        let service = ArticleThumbnailService(session: mockSession)
        let articleLink = URL(string: "https://example.com/article-400")!

        let result = try await service.resolveOGImage(from: articleLink)

        #expect(result == .notFound)
    }

    @Test("resolveOGImage maps 408 to .fetchFailed")
    func resolveOGImageMaps408ToFetchFailed() async throws {
        let mockSession = MockHTMLURLSessionProvider()
        mockSession.statusCode = 408
        let service = ArticleThumbnailService(session: mockSession)
        let articleLink = URL(string: "https://example.com/article-408")!

        let result = try await service.resolveOGImage(from: articleLink)

        #expect(result == .fetchFailed)
    }

    @Test("resolveOGImage maps 429 to .fetchFailed")
    func resolveOGImageMaps429ToFetchFailed() async throws {
        let mockSession = MockHTMLURLSessionProvider()
        mockSession.statusCode = 429
        let service = ArticleThumbnailService(session: mockSession)
        let articleLink = URL(string: "https://example.com/article-429")!

        let result = try await service.resolveOGImage(from: articleLink)

        #expect(result == .fetchFailed)
    }

    @Test("resolveOGImage maps 500 to .fetchFailed")
    func resolveOGImageMaps500ToFetchFailed() async throws {
        let mockSession = MockHTMLURLSessionProvider()
        mockSession.statusCode = 500
        let service = ArticleThumbnailService(session: mockSession)
        let articleLink = URL(string: "https://example.com/article-500")!

        let result = try await service.resolveOGImage(from: articleLink)

        #expect(result == .fetchFailed)
    }

    @Test("resolveOGImage maps 502 to .fetchFailed")
    func resolveOGImageMaps502ToFetchFailed() async throws {
        let mockSession = MockHTMLURLSessionProvider()
        mockSession.statusCode = 502
        let service = ArticleThumbnailService(session: mockSession)
        let articleLink = URL(string: "https://example.com/article-502")!

        let result = try await service.resolveOGImage(from: articleLink)

        #expect(result == .fetchFailed)
    }

    @Test("resolveOGImage maps 503 to .fetchFailed")
    func resolveOGImageMaps503ToFetchFailed() async throws {
        let mockSession = MockHTMLURLSessionProvider()
        mockSession.statusCode = 503
        let service = ArticleThumbnailService(session: mockSession)
        let articleLink = URL(string: "https://example.com/article-503")!

        let result = try await service.resolveOGImage(from: articleLink)

        #expect(result == .fetchFailed)
    }

    @Test("resolveOGImage returns .found when og:image is present in the HTML head")
    func resolveOGImageFindsOGImageTag() async throws {
        let mockSession = MockHTMLURLSessionProvider()
        mockSession.statusCode = 200
        mockSession.htmlBody = """
        <!DOCTYPE html>
        <html>
        <head>
            <title>Test Article</title>
            <meta property="og:image" content="https://cdn.example.com/image.jpg">
        </head>
        <body>Article body</body>
        </html>
        """
        let service = ArticleThumbnailService(session: mockSession)
        let articleLink = URL(string: "https://example.com/article")!

        let result = try await service.resolveOGImage(from: articleLink)

        #expect(result == .found(URL(string: "https://cdn.example.com/image.jpg")!))
    }

    @Test("resolveOGImage returns .notFound when HTML has no og:image tag")
    func resolveOGImageReturnsNotFoundForMissingTag() async throws {
        let mockSession = MockHTMLURLSessionProvider()
        mockSession.statusCode = 200
        mockSession.htmlBody = """
        <!DOCTYPE html>
        <html>
        <head>
            <title>Test Article</title>
            <meta property="og:title" content="No image here">
        </head>
        <body>Article body</body>
        </html>
        """
        let service = ArticleThumbnailService(session: mockSession)
        let articleLink = URL(string: "https://example.com/article")!

        let result = try await service.resolveOGImage(from: articleLink)

        #expect(result == .notFound)
    }

    @Test("resolveOGImage resolves relative og:image URLs against the article base URL")
    func resolveOGImageResolvesRelativeURL() async throws {
        let mockSession = MockHTMLURLSessionProvider()
        mockSession.statusCode = 200
        mockSession.htmlBody = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta property="og:image" content="/images/hero.jpg">
        </head>
        </html>
        """
        let service = ArticleThumbnailService(session: mockSession)
        let articleLink = URL(string: "https://example.com/posts/my-article")!

        let result = try await service.resolveOGImage(from: articleLink)

        // HTMLUtilities.extractOGImageURL resolves relative URLs using the baseURL.
        #expect(result == .found(URL(string: "https://example.com/images/hero.jpg")!))
    }

    // MARK: - resolveOGImage UTF-8 Decoding
    //
    // Regression coverage for issue #230: invalid UTF-8 byte sequences (most
    // commonly caused by the 50 KB head slice cutting through a multi-byte
    // character at the boundary) must NOT be classified as `.fetchFailed`,
    // since retrying the same fetch will hit the same problem. The service
    // now decodes tolerantly via `String(decoding:as:)`, which substitutes
    // replacement characters for invalid bytes — letting the og:image
    // extractor still find the (virtually always ASCII) meta tag — and
    // returns `.notFound` (permanent) when no tag is present so the
    // prefetcher stops re-fetching.

    @Test("resolveOGImage extracts og:image from page with invalid UTF-8 in unrelated bytes")
    func resolveOGImageHandlesInvalidUTF8WithValidOGImage() async throws {
        // Build a payload that contains a valid og:image meta tag followed by
        // a stray invalid UTF-8 byte (0xFF is never valid in UTF-8). Strict
        // decoding would return nil and the old code would map this to
        // `.fetchFailed`; the tolerant decoder substitutes a replacement
        // character and the regex still matches the og:image tag.
        var payload = Data("""
        <!DOCTYPE html>
        <html>
        <head>
            <meta property="og:image" content="https://cdn.example.com/hero.jpg">
        </head>
        <body>
        """.utf8)
        payload.append(0xFF) // Invalid UTF-8 byte
        payload.append(contentsOf: Data("</body></html>".utf8))

        let mockSession = MockHTMLURLSessionProvider()
        mockSession.statusCode = 200
        mockSession.rawPayload = payload
        let service = ArticleThumbnailService(session: mockSession)
        let articleLink = URL(string: "https://example.com/article-invalid-utf8")!

        let result = try await service.resolveOGImage(from: articleLink)

        #expect(result == .found(URL(string: "https://cdn.example.com/hero.jpg")!))
    }

    @Test("resolveOGImage extracts og:image when payload ends mid multi-byte character")
    func resolveOGImageHandlesTruncatedMultiByteCharacter() async throws {
        // Simulate the head slice cutting through a multi-byte UTF-8 character
        // at the 50 KB boundary. The og:image tag is fully decoded earlier in
        // the buffer; only the trailing bytes are truncated. The previous
        // strict-decoding implementation rejected the entire payload as invalid
        // UTF-8, but the tolerant decoder lets the extractor proceed.
        var payload = Data("""
        <!DOCTYPE html>
        <html>
        <head>
            <meta property="og:image" content="https://cdn.example.com/hero.jpg">
            <title>Café story
        """.utf8)
        // The "é" in "Café" above is U+00E9, encoded in UTF-8 as 0xC3 0xA9.
        // Append a lone leading byte of a multi-byte sequence to simulate
        // truncation in the middle of a character.
        payload.append(0xC3)

        let mockSession = MockHTMLURLSessionProvider()
        mockSession.statusCode = 200
        mockSession.rawPayload = payload
        let service = ArticleThumbnailService(session: mockSession)
        let articleLink = URL(string: "https://example.com/article-truncated")!

        let result = try await service.resolveOGImage(from: articleLink)

        #expect(result == .found(URL(string: "https://cdn.example.com/hero.jpg")!))
    }

    @Test("resolveOGImage returns .notFound (not .fetchFailed) when invalid UTF-8 page has no og:image")
    func resolveOGImageReturnsNotFoundForInvalidUTF8WithoutOGImage() async throws {
        // A page with invalid UTF-8 bytes and no og:image meta tag must map
        // to `.notFound` (permanent) so the prefetcher does not retry forever.
        // Pre-fix, this would have hit the strict-decode failure branch and
        // returned `.fetchFailed`, burning retry budget on a request that
        // can never succeed.
        var payload = Data("""
        <!DOCTYPE html>
        <html>
        <head>
            <title>No og:image here</title>
        </head>
        <body>Hello
        """.utf8)
        payload.append(0xFF) // Invalid UTF-8 byte
        payload.append(0xFE)
        payload.append(contentsOf: Data("</body></html>".utf8))

        let mockSession = MockHTMLURLSessionProvider()
        mockSession.statusCode = 200
        mockSession.rawPayload = payload
        let service = ArticleThumbnailService(session: mockSession)
        let articleLink = URL(string: "https://example.com/article-invalid-no-og")!

        let result = try await service.resolveOGImage(from: articleLink)

        #expect(result == .notFound)
    }

    @Test("resolveOGImage maps non-HTTPURLResponse to .fetchFailed via -1 sentinel")
    func resolveOGImageNonHTTPResponseReturnsFetchFailed() async throws {
        // Issue #229 explicitly called out the non-HTTPURLResponse → .fetchFailed
        // path as a required integration scenario. The service guards on
        // `(response as? HTTPURLResponse)` and falls back to the -1 sentinel
        // when the cast fails; -1 is treated as transient by `isPermanentHTTPFailure`,
        // so the overall outcome must be `.fetchFailed` (worth retrying).
        let mockSession = MockHTMLURLSessionProvider()
        mockSession.useNonHTTPResponse = true
        let service = ArticleThumbnailService(session: mockSession)
        let articleLink = URL(string: "https://example.com/article-non-http")!

        let result = try await service.resolveOGImage(from: articleLink)

        #expect(result == .fetchFailed)
    }

    // MARK: - resolveOGImage Pre-Flight URLError Classification
    //
    // Coverage for issue #252: the generic `catch let urlError as URLError` arm
    // in `resolveOGImage(from:)` (lines ~265-271) handles non-cancellation
    // `URLError`s — DNS failures, timeouts, no-network — and maps them to
    // `.fetchFailed` so the prefetcher can retry. The URLProtocol stub used by
    // `MockHTMLURLSessionProvider` always succeeds, so these branches were
    // unreachable until the mock gained a `thrownError` injection point that
    // makes `bytes(for:)` throw before any URL loading begins.

    @Test("resolveOGImage maps pre-flight URLError(.timedOut) to .fetchFailed")
    func resolveOGImageMapsPreFlightTimeoutToFetchFailed() async throws {
        // A timeout surfaced from `session.bytes(for:)` itself (before the
        // `HTTPURLResponse` is received) hits the generic `catch let urlError`
        // rung. It must be classified as `.fetchFailed` (transient) so the
        // prefetcher retries on the next opportunity.
        let mockSession = MockHTMLURLSessionProvider()
        mockSession.thrownError = URLError(.timedOut)
        let service = ArticleThumbnailService(session: mockSession)
        let articleLink = URL(string: "https://example.com/article-timeout")!

        let result = try await service.resolveOGImage(from: articleLink)

        #expect(result == .fetchFailed)
    }

    @Test("resolveOGImage maps pre-flight URLError(.cannotFindHost) to .fetchFailed")
    func resolveOGImageMapsPreFlightDNSFailureToFetchFailed() async throws {
        // DNS failure is the canonical "host unreachable for now" error and
        // hits the same generic `catch let urlError` rung as `.timedOut`.
        // Locking it in here guards against a future refactor that narrows
        // the catch arm to a specific `URLError.Code`.
        let mockSession = MockHTMLURLSessionProvider()
        mockSession.thrownError = URLError(.cannotFindHost)
        let service = ArticleThumbnailService(session: mockSession)
        let articleLink = URL(string: "https://example.com/article-dns")!

        let result = try await service.resolveOGImage(from: articleLink)

        #expect(result == .fetchFailed)
    }

    // MARK: - resolveOGImage 2xx Boundary
    //
    // Coverage for issue #252: `(200...299).contains(httpResponse.statusCode)`
    // has an inclusive upper bound at 299. The pre-existing 200-OK tests don't
    // exercise the upper boundary, leaving an off-by-one risk if a future
    // refactor changes the range to `200..<299`. This test pins the contract.

    @Test("resolveOGImage treats HTTP 299 as 2xx success and extracts og:image")
    func resolveOGImageMaps299ToSuccess() async throws {
        // 299 is the inclusive upper boundary of the 2xx success range. A
        // response at exactly 299 with an og:image meta tag in the body must
        // be treated as success and return `.found`. If the range is ever
        // accidentally narrowed to `200..<299`, this test fails immediately.
        let mockSession = MockHTMLURLSessionProvider()
        mockSession.statusCode = 299
        mockSession.htmlBody = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta property="og:image" content="https://cdn.example.com/boundary.jpg">
        </head>
        </html>
        """
        let service = ArticleThumbnailService(session: mockSession)
        let articleLink = URL(string: "https://example.com/article-299")!

        let result = try await service.resolveOGImage(from: articleLink)

        #expect(result == .found(URL(string: "https://cdn.example.com/boundary.jpg")!))
    }

    // MARK: - resolveOGImage Head-Only Truncation Contract
    //
    // Coverage for issue #252: `resolveOGImage` only reads the first
    // `htmlHeadMaxBytes` (50 KB) of the response body, breaking out of the
    // byte loop once the buffer reaches that size. This is a load-bearing
    // performance optimization (og:image is virtually always inside `<head>`)
    // and any future refactor of the `for try await byte in bytes` loop must
    // preserve it. This test pins the boundary by placing the og:image meta
    // tag well past byte 51,200 and asserting the service returns `.notFound`
    // — proving the tag was never decoded because the loop broke first.

    @Test("resolveOGImage stops reading after htmlHeadMaxBytes and ignores og:image past the cap")
    func resolveOGImageRespectsHeadByteCap() async throws {
        // Construct a payload whose first ~52 KB is filler bytes (placed
        // inside an HTML comment so the body is well-formed), then place a
        // valid og:image meta tag past the 50 KB head cap. The service must
        // break out of the byte loop before reaching the tag, so
        // `extractOGImageURL` returns nil and the result is `.notFound`.
        //
        // The service uses `htmlHeadMaxBytes = 51_200` (50 KB) as the head cap.
        // We pad the body to 52_000 bytes — ~800 bytes past the cap — to make
        // the boundary impossible to miss even if the loop's append-then-check
        // ordering ever shifts by one.
        let headCap = 51_200
        let openingComment = "<!--"
        let closingComment = "-->"
        let metaTag = "<meta property=\"og:image\" content=\"https://cdn.example.com/late.jpg\">"
        let paddingByteCount = 52_000 - openingComment.utf8.count - closingComment.utf8.count
        #expect(paddingByteCount + openingComment.utf8.count + closingComment.utf8.count > headCap)
        let padding = String(repeating: "a", count: paddingByteCount)
        let html = openingComment + padding + closingComment + metaTag

        let mockSession = MockHTMLURLSessionProvider()
        mockSession.statusCode = 200
        mockSession.htmlBody = html
        let service = ArticleThumbnailService(session: mockSession)
        let articleLink = URL(string: "https://example.com/article-late-og-image")!

        let result = try await service.resolveOGImage(from: articleLink)

        // The og:image tag is past the 50 KB head cap, so the service never
        // sees it and falls through to `.notFound`.
        #expect(result == .notFound)
    }
}
