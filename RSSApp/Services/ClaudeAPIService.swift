import Foundation
import os

protocol ClaudeAPIServicing: Sendable {
    func sendMessage(
        systemPrompt: String,
        messages: [ChatMessage],
        apiKey: String
    ) async throws -> AsyncThrowingStream<String, Error>
}

/// Abstracts URLSession's `bytes(for:)` so `ClaudeAPIService.sendMessage` can be
/// tested with controlled SSE line sequences without hitting the network.
protocol URLSessionBytesProviding: Sendable {
    func bytes(for request: URLRequest, delegate: (any URLSessionTaskDelegate)?) async throws -> (URLSession.AsyncBytes, URLResponse)
}

extension URLSessionBytesProviding {
    func bytes(for request: URLRequest) async throws -> (URLSession.AsyncBytes, URLResponse) {
        try await bytes(for: request, delegate: nil)
    }
}

extension URLSession: URLSessionBytesProviding {}

enum ClaudeAPIError: Error, Sendable, LocalizedError {
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

/// Result of parsing a single SSE data line.
///
/// Distinguishes between successfully extracted text, intentionally skipped
/// non-delta event types, and actual JSON decode failures so the caller can
/// count only real failures toward the consecutive-failure threshold.
enum SSEParseResult: Sendable, Equatable {
    /// Successfully extracted text content from a `content_block_delta` event.
    case text(String)
    /// The event was a known non-delta type (e.g., `message_start`, `content_block_stop`)
    /// or a delta with no text field — not a decode failure.
    case skipped
    /// The JSON could not be decoded at all, indicating a possible format change.
    case decodeFailed
}

struct ClaudeAPIService: ClaudeAPIServicing {

    private static let logger = Logger(category: "ClaudeAPIService")

    private static let apiURL = "https://api.anthropic.com/v1/messages"
    /// Maximum number of consecutive `.decodeFailed` results from `parseSSELine` before the
    /// stream is terminated with `ClaudeAPIError.excessiveDecodeFailures`. Only actual JSON
    /// decode failures count toward this threshold — intentionally skipped non-delta events
    /// (`.skipped`) do not increment the counter.
    private static let consecutiveDecodeFailureThreshold = 5

    // MARK: - UserDefaults keys and defaults

    static let modelDefaultsKey = "claude_model_identifier"
    static let maxTokensDefaultsKey = "claude_max_tokens"
    static let defaultModel = "claude-haiku-4-5-20251001"
    static let defaultMaxTokens = 4096

    // RATIONALE: UserDefaults is thread-safe but not marked Sendable in the ObjC headers.
    // nonisolated(unsafe) is appropriate here since UserDefaults operations are internally synchronized.
    private nonisolated(unsafe) let defaults: UserDefaults
    private let session: any URLSessionBytesProviding

    init(defaults: UserDefaults = .standard, session: any URLSessionBytesProviding = URLSession.shared) {
        self.defaults = defaults
        self.session = session
    }

    /// The current model identifier, read from UserDefaults at call time.
    var model: String {
        guard let stored = defaults.string(forKey: Self.modelDefaultsKey), !stored.isEmpty else {
            return Self.defaultModel
        }
        return stored
    }

    /// The current max tokens, read from UserDefaults at call time.
    var maxTokens: Int {
        let stored = defaults.integer(forKey: Self.maxTokensDefaultsKey)
        return stored > 0 ? stored : Self.defaultMaxTokens
    }

    func sendMessage(
        systemPrompt: String,
        messages: [ChatMessage],
        apiKey: String
    ) async throws -> AsyncThrowingStream<String, Error> {
        guard !apiKey.isEmpty else {
            throw ClaudeAPIError.missingAPIKey
        }
        guard let url = URL(string: Self.apiURL) else {
            Self.logger.fault("Failed to construct Claude API URL from '\(Self.apiURL, privacy: .public)'")
            assertionFailure("Failed to construct Claude API URL")
            throw ClaudeAPIError.invalidURL
        }

        let request = try buildRequest(url: url, apiKey: apiKey, systemPrompt: systemPrompt, messages: messages)
        Self.logger.debug("sendMessage() called with \(messages.count, privacy: .public) messages, model=\(model, privacy: .public), maxTokens=\(maxTokens, privacy: .public)")

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let (bytes, response) = try await self.session.bytes(for: request)
                    guard let httpResponse = response as? HTTPURLResponse else {
                        continuation.finish(throwing: ClaudeAPIError.httpError(statusCode: 0))
                        return
                    }
                    guard (200..<300).contains(httpResponse.statusCode) else {
                        Self.logger.error("Claude API returned HTTP \(httpResponse.statusCode, privacy: .public)")
                        continuation.finish(throwing: ClaudeAPIError.httpError(statusCode: httpResponse.statusCode))
                        return
                    }

                    var consecutiveDecodeFailures = 0
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let json = String(line.dropFirst(6))
                        guard json != "[DONE]" else { break }
                        switch try parseSSELine(json) {
                        case .text(let chunk):
                            consecutiveDecodeFailures = 0
                            continuation.yield(chunk)
                        case .skipped:
                            break
                        case .decodeFailed:
                            consecutiveDecodeFailures += 1
                            Self.logger.debug("Consecutive decode failure #\(consecutiveDecodeFailures, privacy: .public). JSON: \(json, privacy: .private)")
                            if consecutiveDecodeFailures >= Self.consecutiveDecodeFailureThreshold {
                                Self.logger.error("Exceeded consecutive decode failure threshold (\(Self.consecutiveDecodeFailureThreshold, privacy: .public) failures)")
                                continuation.finish(throwing: ClaudeAPIError.excessiveDecodeFailures(count: consecutiveDecodeFailures))
                                return
                            }
                        }
                    }
                    Self.logger.info("Claude stream finished")
                    continuation.finish()
                } catch {
                    Self.logger.error("Claude stream error: \(error, privacy: .public)")
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Internal helpers (internal for testability)

    func buildRequest(url: URL, apiKey: String, systemPrompt: String, messages: [ChatMessage]) throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        let body = ClaudeRequest(
            model: model,
            maxTokens: maxTokens,
            system: systemPrompt,
            messages: messages.map { ClaudeRequestMessage(role: $0.role.rawValue, content: $0.content) },
            stream: true
        )
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    func parseSSELine(_ json: String) throws -> SSEParseResult {
        guard let data = json.data(using: .utf8) else {
            Self.logger.warning("SSE line could not be encoded to UTF-8 data")
            return .decodeFailed
        }

        let event: ClaudeStreamEvent
        do {
            event = try JSONDecoder().decode(ClaudeStreamEvent.self, from: data)
        } catch {
            Self.logger.warning("Failed to decode SSE JSON: \(error, privacy: .public). Input: \(json, privacy: .private)")
            return .decodeFailed
        }

        if event.type == "error" {
            if event.error == nil {
                Self.logger.warning("Server sent error event with no error object")
            } else if event.error?.message == nil || event.error?.type == nil {
                Self.logger.warning("Server error event missing fields — message: \(event.error?.message == nil ? "nil" : "present", privacy: .public), type: \(event.error?.type == nil ? "nil" : "present", privacy: .public)")
            }
            let errorMessage = event.error?.message ?? "Unknown server error"
            let errorType = event.error?.type ?? "unknown"
            Self.logger.error("Claude API stream error (type=\(errorType, privacy: .public)): \(errorMessage, privacy: .public). Raw: \(json, privacy: .private)")
            throw ClaudeAPIError.serverError(message: errorMessage)
        }

        guard event.type == "content_block_delta" else {
            return .skipped
        }

        guard let text = event.delta?.text else {
            return .skipped
        }

        return .text(text)
    }
}

// MARK: - Codable request/response types

struct ClaudeRequest: Encodable {
    let model: String
    let maxTokens: Int
    let system: String
    let messages: [ClaudeRequestMessage]
    let stream: Bool

    enum CodingKeys: String, CodingKey {
        case model
        case maxTokens = "max_tokens"
        case system
        case messages
        case stream
    }
}

struct ClaudeRequestMessage: Encodable {
    let role: String
    let content: String
}

struct ClaudeStreamEvent: Decodable {
    let type: String
    let delta: ClaudeStreamDelta?
    let error: ClaudeStreamError?
}

struct ClaudeStreamError: Decodable {
    let type: String?
    let message: String?
}

struct ClaudeStreamDelta: Decodable {
    let type: String?
    let text: String?
}
