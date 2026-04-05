import Foundation
@testable import RSSApp

/// A `URLSessionBytesProviding` mock that yields controlled SSE lines without
/// hitting the network.
///
/// Uses a custom `URLProtocol` subclass so the returned `URLSession.AsyncBytes`
/// is a real Foundation object — no wrapper types or protocol signature changes needed.
/// Per-request data is keyed by a unique identifier injected via a custom HTTP header,
/// making concurrent test execution safe.
// RATIONALE: @unchecked Sendable is safe because this mock is only used in
// single-threaded test contexts where properties are set before the async call.
final class MockURLSessionBytesProvider: URLSessionBytesProviding, @unchecked Sendable {

    /// Raw lines to feed through the byte stream, joined by newlines.
    var lines: [String] = []

    /// HTTP status code for the mock response (default 200).
    var statusCode: Int = 200

    func bytes(for request: URLRequest, delegate: (any URLSessionTaskDelegate)? = nil) async throws -> (URLSession.AsyncBytes, URLResponse) {
        let payload = lines.joined(separator: "\n")
        let requestID = UUID().uuidString

        // Register payload and status in the thread-safe store.
        MockSSEURLProtocol.store(
            requestID: requestID,
            payload: Data(payload.utf8),
            statusCode: statusCode
        )

        // Inject the request ID via a custom header so the URLProtocol instance
        // can look up the correct payload even when tests run concurrently.
        var mutableRequest = request
        mutableRequest.setValue(requestID, forHTTPHeaderField: MockSSEURLProtocol.requestIDHeader)

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockSSEURLProtocol.self]
        let session = URLSession(configuration: config)

        return try await session.bytes(for: mutableRequest)
    }
}

// MARK: - URLProtocol subclass

/// Intercepts requests tagged with the mock request-ID header and returns the
/// corresponding payload from a thread-safe in-memory store.
final class MockSSEURLProtocol: URLProtocol {

    static let requestIDHeader = "X-MockSSE-RequestID"

    // MARK: - Thread-safe per-request store

    private struct RequestData {
        let payload: Data
        let statusCode: Int
    }

    // RATIONALE: nonisolated(unsafe) is acceptable here because all access goes
    // through the synchronized `storeQueue` dispatch queue below.
    nonisolated(unsafe) private static var requestStore: [String: RequestData] = [:]
    nonisolated(unsafe) private static let storeQueue = DispatchQueue(label: "MockSSEURLProtocol.storeQueue")

    static func store(requestID: String, payload: Data, statusCode: Int) {
        storeQueue.sync {
            requestStore[requestID] = RequestData(payload: payload, statusCode: statusCode)
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
            assertionFailure("MockSSEURLProtocol: request missing \(Self.requestIDHeader) header")
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        guard let data = Self.retrieve(requestID: requestID) else {
            assertionFailure("MockSSEURLProtocol: no stored data for requestID '\(requestID)'")
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        guard let url = request.url else {
            assertionFailure("MockSSEURLProtocol: request has no URL")
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        guard let response = HTTPURLResponse(
            url: url,
            statusCode: data.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/event-stream"]
        ) else {
            assertionFailure("MockSSEURLProtocol: failed to create HTTPURLResponse")
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data.payload)
        client?.urlProtocolDidFinishLoading(self)
    }

    // RATIONALE: Data is delivered synchronously in startLoading(); nothing to cancel.
    override func stopLoading() {}
}
