import Foundation
@testable import RSSApp

// RATIONALE: @unchecked Sendable is safe because this mock is only used in
// single-threaded test contexts where properties are set before the async call.
final class MockClaudeAPIService: ClaudeAPIServicing, @unchecked Sendable {
    var chunks: [String] = []
    var errorToThrow: Error?

    func sendMessage(
        systemPrompt: String,
        messages: [ChatMessage],
        apiKey: String
    ) async throws -> AsyncThrowingStream<String, Error> {
        if let error = errorToThrow { throw error }
        let chunks = self.chunks
        return AsyncThrowingStream { continuation in
            for chunk in chunks {
                continuation.yield(chunk)
            }
            continuation.finish()
        }
    }
}
