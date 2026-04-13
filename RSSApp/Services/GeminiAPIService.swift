import Foundation
import os

struct GeminiAPIService: AIServicing {

    private static let logger = Logger(category: "GeminiAPIService")

    private static let baseURL = "https://generativelanguage.googleapis.com/v1beta/models"
    /// Maximum number of consecutive `.decodeFailed` results before the stream is
    /// terminated. Mirrors the threshold in `ClaudeAPIService`.
    private static let consecutiveDecodeFailureThreshold = 5

    private let session: any URLSessionBytesProviding

    init(session: any URLSessionBytesProviding = URLSession.shared) {
        self.session = session
    }

    func sendMessage(
        systemPrompt: String,
        messages: [ChatMessage],
        model: String,
        maxTokens: Int,
        apiKey: String
    ) async throws -> AsyncThrowingStream<String, Error> {
        guard !apiKey.isEmpty else {
            throw AIServiceError.missingAPIKey
        }

        let urlString = "\(Self.baseURL)/\(model):streamGenerateContent?alt=sse"
        guard let url = URL(string: urlString) else {
            Self.logger.fault("Failed to construct Gemini API URL from '\(urlString, privacy: .public)'")
            assertionFailure("Failed to construct Gemini API URL")
            throw AIServiceError.invalidURL
        }

        let request = try buildRequest(url: url, apiKey: apiKey, systemPrompt: systemPrompt, messages: messages, maxTokens: maxTokens)
        Self.logger.debug("sendMessage() called with \(messages.count, privacy: .public) messages, model=\(model, privacy: .public), maxTokens=\(maxTokens, privacy: .public)")

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let (bytes, response) = try await self.session.bytes(for: request)
                    guard let httpResponse = response as? HTTPURLResponse else {
                        continuation.finish(throwing: AIServiceError.httpError(statusCode: 0))
                        return
                    }
                    guard (200..<300).contains(httpResponse.statusCode) else {
                        Self.logger.error("Gemini API returned HTTP \(httpResponse.statusCode, privacy: .public)")
                        continuation.finish(throwing: AIServiceError.httpError(statusCode: httpResponse.statusCode))
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
                                continuation.finish(throwing: AIServiceError.excessiveDecodeFailures(count: consecutiveDecodeFailures))
                                return
                            }
                        }
                    }
                    Self.logger.info("Gemini stream finished")
                    continuation.finish()
                } catch {
                    Self.logger.error("Gemini stream error: \(error, privacy: .public)")
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Internal helpers (internal for testability)

    func buildRequest(url: URL, apiKey: String, systemPrompt: String, messages: [ChatMessage], maxTokens: Int) throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        let geminiMessages = messages.map { msg in
            // Exhaustive switch so the compiler flags any new ChatMessage.Role cases.
            let role: String
            switch msg.role {
            case .assistant: role = "model"
            case .user: role = "user"
            }
            return GeminiContent(role: role, parts: [GeminiPart(text: msg.content)])
        }

        let body = GeminiRequest(
            contents: geminiMessages,
            systemInstruction: GeminiSystemInstruction(parts: [GeminiPart(text: systemPrompt)]),
            generationConfig: GeminiGenerationConfig(maxOutputTokens: maxTokens)
        )
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        request.httpBody = try encoder.encode(body)
        return request
    }

    func parseSSELine(_ json: String) throws -> SSEParseResult {
        guard let data = json.data(using: .utf8) else {
            Self.logger.warning("SSE line could not be encoded to UTF-8 data")
            return .decodeFailed
        }

        let response: GeminiStreamResponse
        do {
            response = try JSONDecoder().decode(GeminiStreamResponse.self, from: data)
        } catch {
            Self.logger.warning("Failed to decode Gemini SSE JSON: \(error, privacy: .public). Input: \(json, privacy: .private)")
            return .decodeFailed
        }

        if let errorObj = response.error {
            let message = errorObj.message ?? "Unknown server error"
            let status = errorObj.status ?? "unknown"
            Self.logger.error("Gemini API stream error (status=\(status, privacy: .public)): \(message, privacy: .public). Raw: \(json, privacy: .private)")
            throw AIServiceError.serverError(message: message)
        }

        guard let text = response.candidates?.first?.content?.parts?.first?.text,
              !text.isEmpty else {
            return .skipped
        }

        return .text(text)
    }
}

// MARK: - Codable request types

private struct GeminiRequest: Encodable {
    let contents: [GeminiContent]
    let systemInstruction: GeminiSystemInstruction
    let generationConfig: GeminiGenerationConfig
}

private struct GeminiContent: Codable {
    let role: String
    let parts: [GeminiPart]
}

private struct GeminiPart: Codable {
    let text: String
}

private struct GeminiGenerationConfig: Encodable {
    let maxOutputTokens: Int
}

private struct GeminiSystemInstruction: Encodable {
    let parts: [GeminiPart]
}

// MARK: - Codable response types

private struct GeminiStreamResponse: Decodable {
    let candidates: [GeminiCandidate]?
    let error: GeminiStreamError?
}

private struct GeminiStreamError: Decodable {
    let code: Int?
    let message: String?
    let status: String?
}

private struct GeminiCandidate: Decodable {
    let content: GeminiResponseContent?
}

/// Separate response-side content type so `parts` can be optional
/// (Gemini may omit the field in some stream events).
private struct GeminiResponseContent: Decodable {
    let role: String?
    let parts: [GeminiPart]?
}
