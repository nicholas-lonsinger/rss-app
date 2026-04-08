import Foundation
@testable import RSSApp

/// A `URLSessionBytesProviding` mock that streams an HTML body and then
/// surfaces an error mid-stream so a test can exercise the
/// `catch let urlError as URLError where urlError.code == .cancelled` rung
/// in `ArticleThumbnailService.resolveOGImage(from:)` directly.
///
/// Unlike `MockHTMLURLSessionProvider` (which delivers the entire payload
/// synchronously inside `startLoading()`), this provider:
///   1. Delivers a 200 OK `HTTPURLResponse` so
///      `try await session.bytes(for:)` returns and the byte loop begins.
///   2. Delivers a small initial chunk so the byte iterator has actually
///      pulled bytes through the loop body.
///   3. Fails the request with a configurable error (default
///      `URLError(.cancelled)`) on a private dispatch queue, so the iterating
///      caller observes that error from inside its `for try await byte in bytes`
///      loop.
///
/// This is the cleanest way to exercise the `URLError(.cancelled)` rung without
/// involving Swift Task cancellation. With Task cancellation, the iterator
/// throws `CancellationError` directly via cooperative cancellation at the
/// suspension point, which exercises the *other* catch arm and can never
/// reach the URLError(.cancelled) one. Using a real URLSession to provoke
/// `URLError(.cancelled)` mid-stream would require either real network I/O
/// (flaky, slow, requires connectivity) or driving `URLSessionDataTask.cancel()`
/// directly (no public bridge from AsyncBytes back to its data task). Driving
/// the failure through a custom URLProtocol that calls `didFailWithError`
/// avoids both problems and matches the production behavior surfaced in
/// issue #228.
///
/// Issue #248 tracked the missing test coverage for the load-bearing rung.
// RATIONALE: @unchecked Sendable is safe because this mock is only used in
// single-threaded test contexts where properties are set before the async call.
final class MockSlowHTMLURLSessionProvider: URLSessionBytesProviding, @unchecked Sendable {

    /// Initial bytes delivered to the URL loading client before the failure.
    /// Defaults to a few bytes of HTML so the byte iterator has actually pulled
    /// at least one chunk through the loop body before the error surfaces.
    var initialChunk: Data = Data("<!DOCTYPE html>\n<html>".utf8)

    /// Error to deliver to the client after the initial chunk. Defaults to
    /// `URLError(.cancelled)`, which is the production behavior issue #228
    /// fixed and PR #247 hardened with the load-bearing catch rung.
    var midStreamError: URLError = URLError(.cancelled)

    /// Delay between sending the initial chunk and the failure, in nanoseconds.
    /// A small delay (10 ms) gives `URLSession.AsyncBytes` time to deliver the
    /// initial chunk to the byte iterator before the error lands.
    var failureDelayNanoseconds: UInt64 = 10_000_000

    func bytes(for request: URLRequest, delegate: (any URLSessionTaskDelegate)? = nil) async throws -> (URLSession.AsyncBytes, URLResponse) {
        let requestID = UUID().uuidString

        MockSlowHTMLURLProtocol.store(
            requestID: requestID,
            initialChunk: initialChunk,
            midStreamError: midStreamError,
            failureDelayNanoseconds: failureDelayNanoseconds
        )

        var mutableRequest = request
        mutableRequest.setValue(requestID, forHTTPHeaderField: MockSlowHTMLURLProtocol.requestIDHeader)

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockSlowHTMLURLProtocol.self]
        let session = URLSession(configuration: config)

        return try await session.bytes(for: mutableRequest)
    }
}

// MARK: - URLProtocol subclass

/// Intercepts requests tagged with the slow-mock request-ID header and
/// delivers a small initial chunk followed by a configurable error
/// (default `URLError(.cancelled)`), so the iterating caller observes
/// the error from inside its `for try await byte in bytes` loop.
// RATIONALE: No explicit `@unchecked Sendable` — URLProtocol's Sendable
// conformance is marked unavailable in the iOS 26 SDK, and re-declaring it on
// the subclass emits a "conformance already unavailable" warning. The mock is
// only used in single-threaded test contexts, so the subclass's lack of
// Sendable conformance is acceptable.
final class MockSlowHTMLURLProtocol: URLProtocol {

    static let requestIDHeader = "X-MockSlowHTML-RequestID"

    // MARK: - Per-request configuration

    /// Configuration for a single in-flight request. Stored in the per-request
    /// dictionary keyed by request ID and looked up inside `startLoading()`.
    struct RequestConfig: Sendable {
        let initialChunk: Data
        let midStreamError: URLError
        let failureDelayNanoseconds: UInt64
    }

    // MARK: - Thread-safe per-request store

    // RATIONALE: nonisolated(unsafe) is acceptable here because all access goes
    // through the synchronized `storeQueue` dispatch queue below.
    nonisolated(unsafe) private static var requestStore: [String: RequestConfig] = [:]
    private static let storeQueue = DispatchQueue(label: "MockSlowHTMLURLProtocol.storeQueue")

    static func store(
        requestID: String,
        initialChunk: Data,
        midStreamError: URLError,
        failureDelayNanoseconds: UInt64
    ) {
        storeQueue.sync {
            requestStore[requestID] = RequestConfig(
                initialChunk: initialChunk,
                midStreamError: midStreamError,
                failureDelayNanoseconds: failureDelayNanoseconds
            )
        }
    }

    private static func retrieve(requestID: String) -> RequestConfig? {
        storeQueue.sync {
            requestStore.removeValue(forKey: requestID)
        }
    }

    /// Private serial queue for delivering chunks. One queue per protocol
    /// instance keeps deliveries ordered.
    private let deliveryQueue = DispatchQueue(label: "MockSlowHTMLURLProtocol.delivery")

    // MARK: - URLProtocol overrides

    override class func canInit(with request: URLRequest) -> Bool {
        request.value(forHTTPHeaderField: requestIDHeader) != nil
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let requestID = request.value(forHTTPHeaderField: Self.requestIDHeader) else {
            assertionFailure("MockSlowHTMLURLProtocol: request missing \(Self.requestIDHeader) header")
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        guard let config = Self.retrieve(requestID: requestID) else {
            assertionFailure("MockSlowHTMLURLProtocol: no stored data for requestID '\(requestID)'")
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        guard let url = request.url else {
            assertionFailure("MockSlowHTMLURLProtocol: request has no URL")
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        guard let httpResponse = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/html; charset=utf-8"]
        ) else {
            assertionFailure("MockSlowHTMLURLProtocol: failed to create HTTPURLResponse")
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }

        // Send headers + initial chunk immediately so the caller's
        // `try await session.bytes(for:)` returns and the byte iteration
        // loop has data to consume.
        client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: config.initialChunk)

        // After a short delay (so the byte iterator has actually pulled the
        // initial chunk through `for try await byte in bytes`), surface the
        // configured error to the client. URLSession then propagates it to
        // the AsyncBytes iterator, which throws it from `next()`.
        let delayNanoseconds = config.failureDelayNanoseconds
        let error = config.midStreamError
        // RATIONALE: `self` is non-Sendable (URLProtocol's Sendable conformance is
        // marked unavailable under iOS 26), but DispatchQueue.asyncAfter requires a
        // @Sendable closure. `nonisolated(unsafe)` bypasses the check; the mock is
        // only used in single-threaded test contexts per the class-level RATIONALE.
        nonisolated(unsafe) let capturedSelf = self
        deliveryQueue.asyncAfter(deadline: .now() + .nanoseconds(Int(min(UInt64(Int.max), delayNanoseconds)))) {
            capturedSelf.client?.urlProtocol(capturedSelf, didFailWithError: error)
        }
    }

    // RATIONALE: Nothing to clean up — the failure is delivered on a private
    // dispatch queue and URLSession will tear down the data task on its own
    // after `didFailWithError`.
    override func stopLoading() {}
}
