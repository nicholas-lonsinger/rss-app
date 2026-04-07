import Foundation
@testable import RSSApp

/// A `URLSessionBytesProviding` mock that returns a configurable HTTP status and
/// HTML body for any request, without hitting the network.
///
/// Used to drive `ArticleThumbnailService.resolveOGImage(from:)` through its
/// HTTP classification paths (4xx permanent, 408/429/5xx transient, 200 with or
/// without og:image). Uses a dedicated `URLProtocol` subclass so the returned
/// `URLSession.AsyncBytes` is a real Foundation object. Per-request data is
/// keyed by a unique ID injected via a custom HTTP header, making concurrent
/// test execution safe.
// RATIONALE: @unchecked Sendable is safe because this mock is only used in
// single-threaded test contexts where properties are set before the async call.
final class MockHTMLURLSessionProvider: URLSessionBytesProviding, @unchecked Sendable {

    /// HTML body returned when the response status is 2xx. Ignored for non-2xx
    /// codes since the service short-circuits before reading bytes.
    var htmlBody: String = ""

    /// HTTP status code for the mock response (default 200).
    var statusCode: Int = 200

    /// When `true`, the protocol delivers a plain `URLResponse` instead of an
    /// `HTTPURLResponse`. This drives the `(response as? HTTPURLResponse)` cast
    /// failure branch in `resolveOGImage`, where the response can't be classified
    /// and falls back to the `-1` sentinel for `isPermanentHTTPFailure`.
    var useNonHTTPResponse: Bool = false

    func bytes(for request: URLRequest, delegate: (any URLSessionTaskDelegate)? = nil) async throws -> (URLSession.AsyncBytes, URLResponse) {
        let requestID = UUID().uuidString

        MockHTMLURLProtocol.store(
            requestID: requestID,
            payload: Data(htmlBody.utf8),
            statusCode: statusCode,
            useNonHTTPResponse: useNonHTTPResponse
        )

        var mutableRequest = request
        mutableRequest.setValue(requestID, forHTTPHeaderField: MockHTMLURLProtocol.requestIDHeader)

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockHTMLURLProtocol.self]
        let session = URLSession(configuration: config)

        return try await session.bytes(for: mutableRequest)
    }
}

// MARK: - URLProtocol subclass

/// Intercepts requests tagged with the mock request-ID header and returns the
/// corresponding HTML payload from a thread-safe in-memory store.
final class MockHTMLURLProtocol: URLProtocol {

    static let requestIDHeader = "X-MockHTML-RequestID"

    // MARK: - Thread-safe per-request store

    private struct RequestData {
        let payload: Data
        let statusCode: Int
        let useNonHTTPResponse: Bool
    }

    // RATIONALE: nonisolated(unsafe) is acceptable here because all access goes
    // through the synchronized `storeQueue` dispatch queue below.
    nonisolated(unsafe) private static var requestStore: [String: RequestData] = [:]
    nonisolated(unsafe) private static let storeQueue = DispatchQueue(label: "MockHTMLURLProtocol.storeQueue")

    static func store(requestID: String, payload: Data, statusCode: Int, useNonHTTPResponse: Bool = false) {
        storeQueue.sync {
            requestStore[requestID] = RequestData(
                payload: payload,
                statusCode: statusCode,
                useNonHTTPResponse: useNonHTTPResponse
            )
        }
    }

    private static func retrieve(requestID: String) -> RequestData? {
        storeQueue.sync {
            requestStore.removeValue(forKey: requestID)
        }
    }

    // MARK: - URLProtocol overrides

    override class func canInit(with request: URLRequest) -> Bool {
        request.value(forHTTPHeaderField: requestIDHeader) != nil
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let requestID = request.value(forHTTPHeaderField: Self.requestIDHeader) else {
            assertionFailure("MockHTMLURLProtocol: request missing \(Self.requestIDHeader) header")
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        guard let data = Self.retrieve(requestID: requestID) else {
            assertionFailure("MockHTMLURLProtocol: no stored data for requestID '\(requestID)'")
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        guard let url = request.url else {
            assertionFailure("MockHTMLURLProtocol: request has no URL")
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let response: URLResponse
        if data.useNonHTTPResponse {
            // Deliver a plain URLResponse so the `(response as? HTTPURLResponse)`
            // cast in `resolveOGImage` fails and the service falls back to the
            // -1 sentinel branch of `isPermanentHTTPFailure`.
            response = URLResponse(
                url: url,
                mimeType: "text/html",
                expectedContentLength: data.payload.count,
                textEncodingName: "utf-8"
            )
        } else {
            guard let httpResponse = HTTPURLResponse(
                url: url,
                statusCode: data.statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "text/html; charset=utf-8"]
            ) else {
                assertionFailure("MockHTMLURLProtocol: failed to create HTTPURLResponse")
                client?.urlProtocol(self, didFailWithError: URLError(.unknown))
                return
            }
            response = httpResponse
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data.payload)
        client?.urlProtocolDidFinishLoading(self)
    }

    // RATIONALE: Data is delivered synchronously in startLoading(); nothing to cancel.
    override func stopLoading() {}
}
