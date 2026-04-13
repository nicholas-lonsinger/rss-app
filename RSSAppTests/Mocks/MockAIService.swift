import Foundation
@testable import RSSApp

// RATIONALE: @unchecked Sendable is safe because this mock is only used in
// single-threaded test contexts where properties are set before the async call.
final class MockAIService: AIServicing, @unchecked Sendable {
    var chunks: [String] = []
    var errorToThrow: Error?

    /// Captures the last values passed to `sendMessage` for assertion in tests.
    var capturedModel: String?
    var capturedMaxTokens: Int?
    var capturedAPIKey: String?

    func sendMessage(
        systemPrompt: String,
        messages: [ChatMessage],
        model: String,
        maxTokens: Int,
        apiKey: String
    ) async throws -> AsyncThrowingStream<String, Error> {
        capturedModel = model
        capturedMaxTokens = maxTokens
        capturedAPIKey = apiKey
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
