import Foundation

// MARK: - URLSessionBytesProviding

/// Abstracts URLSession's `bytes(for:)` so `ClaudeAPIService` and `GeminiAPIService`
/// can be tested with controlled SSE line sequences without hitting the network.
protocol URLSessionBytesProviding: Sendable {
    func bytes(for request: URLRequest, delegate: (any URLSessionTaskDelegate)?) async throws -> (URLSession.AsyncBytes, URLResponse)
}

extension URLSessionBytesProviding {
    func bytes(for request: URLRequest) async throws -> (URLSession.AsyncBytes, URLResponse) {
        try await bytes(for: request, delegate: nil)
    }
}

extension URLSession: URLSessionBytesProviding {}

// MARK: - URLSessionDataProviding

/// Abstracts URLSession's `data(for:)` so services like `GeminiModelService`
/// can be tested with controlled response payloads without hitting the network.
protocol URLSessionDataProviding: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: URLSessionDataProviding {}
