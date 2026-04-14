import Foundation
@testable import RSSApp

/// A `URLSessionDataProviding` mock that returns a configurable JSON payload and
/// HTTP status code without hitting the network.
///
/// Uses a custom `URLProtocol` subclass so the returned `(Data, URLResponse)` pair
/// is a real Foundation object — no wrapper types or protocol signature changes needed.
/// Per-request data is keyed by a unique identifier injected via a custom HTTP header,
/// making concurrent test execution safe.
// RATIONALE: @unchecked Sendable is safe because this mock is only used in
// single-threaded test contexts where properties are set before the async call.
final class MockURLSessionDataProvider: URLSessionDataProviding, @unchecked Sendable {

    /// Raw JSON payload to return in the response body.
    var jsonPayload: Data = Data()

    /// HTTP status code for the mock response (default 200).
    var statusCode: Int = 200

    /// When set, the mock throws this error instead of returning a response.
    var throwError: Error?

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        if let error = throwError {
            throw error
        }

        let requestID = UUID().uuidString

        MockDataURLProtocol.store(
            requestID: requestID,
            payload: jsonPayload,
            statusCode: statusCode
        )

        var mutableRequest = request
        mutableRequest.setValue(requestID, forHTTPHeaderField: MockDataURLProtocol.requestIDHeader)

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockDataURLProtocol.self]
        let session = URLSession(configuration: config)

        return try await session.data(for: mutableRequest)
    }
}

// MARK: - URLProtocol subclass

/// Intercepts requests tagged with the mock request-ID header and returns the
/// corresponding JSON payload from a thread-safe in-memory store.
final class MockDataURLProtocol: URLProtocol {

    static let requestIDHeader = "X-MockData-RequestID"

    // MARK: - Thread-safe per-request store

    private struct RequestData {
        let payload: Data
        let statusCode: Int
    }

    // RATIONALE: nonisolated(unsafe) is acceptable here because all access goes
    // through the synchronized `storeQueue` dispatch queue below.
    nonisolated(unsafe) private static var requestStore: [String: RequestData] = [:]
    private static let storeQueue = DispatchQueue(label: "MockDataURLProtocol.storeQueue")

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
            assertionFailure("MockDataURLProtocol: request missing \(Self.requestIDHeader) header")
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        guard let data = Self.retrieve(requestID: requestID) else {
            assertionFailure("MockDataURLProtocol: no stored data for requestID '\(requestID)'")
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        guard let url = request.url else {
            assertionFailure("MockDataURLProtocol: request has no URL")
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        guard let response = HTTPURLResponse(
            url: url,
            statusCode: data.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        ) else {
            assertionFailure("MockDataURLProtocol: failed to create HTTPURLResponse")
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
