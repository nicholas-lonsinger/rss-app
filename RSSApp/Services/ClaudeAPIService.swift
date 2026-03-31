import Foundation
import os

protocol ClaudeAPIServicing: Sendable {
    func sendMessage(
        systemPrompt: String,
        messages: [ChatMessage],
        apiKey: String
    ) async throws -> AsyncThrowingStream<String, Error>
}

enum ClaudeAPIError: Error, Sendable {
    case invalidURL
    case httpError(statusCode: Int)
    case missingAPIKey
}

struct ClaudeAPIService: ClaudeAPIServicing {

    private static let logger = Logger(
        subsystem: "com.nicholas-lonsinger.rss-app",
        category: "ClaudeAPIService"
    )

    private static let apiURL = "https://api.anthropic.com/v1/messages"
    private static let model = "claude-sonnet-4-6"
    private static let maxTokens = 1024

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
        Self.logger.debug("sendMessage() called with \(messages.count, privacy: .public) messages")

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let httpResponse = response as? HTTPURLResponse else {
                        continuation.finish(throwing: ClaudeAPIError.httpError(statusCode: 0))
                        return
                    }
                    guard (200..<300).contains(httpResponse.statusCode) else {
                        Self.logger.error("Claude API returned HTTP \(httpResponse.statusCode, privacy: .public)")
                        continuation.finish(throwing: ClaudeAPIError.httpError(statusCode: httpResponse.statusCode))
                        return
                    }

                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let json = String(line.dropFirst(6))
                        guard json != "[DONE]" else { break }
                        if let chunk = parseSSELine(json) {
                            continuation.yield(chunk)
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
            model: Self.model,
            maxTokens: Self.maxTokens,
            system: systemPrompt,
            messages: messages.map { ClaudeRequestMessage(role: $0.role.rawValue, content: $0.content) },
            stream: true
        )
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    func parseSSELine(_ json: String) -> String? {
        guard let data = json.data(using: .utf8),
              let event = try? JSONDecoder().decode(ClaudeStreamEvent.self, from: data),
              event.type == "content_block_delta",
              let text = event.delta?.text else {
            return nil
        }
        return text
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
}

struct ClaudeStreamDelta: Decodable {
    let type: String?
    let text: String?
}
