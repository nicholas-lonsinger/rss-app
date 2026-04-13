import Foundation

// MARK: - AIServicing

/// Provider-agnostic interface for streaming AI message responses.
///
/// Both `ClaudeAPIService` and `GeminiAPIService` conform to this protocol.
/// Consumers (e.g. `DiscussionViewModel`) use this protocol so they never
/// reference a concrete provider implementation.
///
/// All configuration (`model`, `maxTokens`, `apiKey`) is passed explicitly
/// at call time rather than read from UserDefaults inside the service. This
/// keeps services stateless and makes them trivially testable.
protocol AIServicing: Sendable {
    func sendMessage(
        systemPrompt: String,
        messages: [ChatMessage],
        model: String,
        maxTokens: Int,
        apiKey: String
    ) async throws -> AsyncThrowingStream<String, Error>
}

// MARK: - AIServiceError

/// Provider-agnostic error type thrown by all `AIServicing` implementations.
///
/// Replaces the former `ClaudeAPIError` with the same cases so error handling
/// in view models and tests does not need to know which provider produced the error.
enum AIServiceError: Error, Sendable, LocalizedError {
    case invalidURL
    case httpError(statusCode: Int)
    case missingAPIKey
    case serverError(message: String)
    case excessiveDecodeFailures(count: Int)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "The API URL is invalid."
        case .httpError(let statusCode):
            "The server returned HTTP \(statusCode)."
        case .missingAPIKey:
            "No API key configured."
        case .serverError(let message):
            message
        case .excessiveDecodeFailures(let count):
            "Unable to read the AI response (\(count) consecutive events could not be decoded). Please try again or check for app updates."
        }
    }
}

// MARK: - AIServiceFactory

/// Returns the appropriate `AIServicing` implementation for the given provider.
enum AIServiceFactory {
    static func service(for provider: AIProvider) -> any AIServicing {
        switch provider {
        case .claude: ClaudeAPIService()
        case .gemini: GeminiAPIService()
        }
    }
}
