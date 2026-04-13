import Foundation
import Testing
@testable import RSSApp

@Suite("ClaudeAPIService")
struct ClaudeAPIServiceTests {

    // MARK: - Request building

    @Test("buildRequest sets correct headers and HTTP method")
    func requestHeaders() throws {
        let service = ClaudeAPIService()
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        let request = try service.buildRequest(
            url: url,
            apiKey: "sk-test-key",
            systemPrompt: "You are helpful.",
            messages: [],
            model: "claude-haiku-4-5-20251001",
            maxTokens: 4096
        )
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "x-api-key") == "sk-test-key")
        #expect(request.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
        #expect(request.value(forHTTPHeaderField: "content-type") == "application/json")
    }

    @Test("buildRequest body encodes correct JSON structure")
    func requestBodyEncoding() throws {
        let service = ClaudeAPIService()
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        let messages = [ChatMessage(role: .user, content: "Hello")]
        let request = try service.buildRequest(
            url: url,
            apiKey: "key",
            systemPrompt: "system",
            messages: messages,
            model: "claude-haiku-4-5-20251001",
            maxTokens: 4096
        )
        let body = try #require(request.httpBody)
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        #expect(json?["model"] as? String == "claude-haiku-4-5-20251001")
        #expect(json?["max_tokens"] as? Int == 4096)
        #expect(json?["stream"] as? Bool == true)
        #expect(json?["system"] as? String == "system")
        let msgs = try #require(json?["messages"] as? [[String: String]])
        #expect(msgs.first?["role"] == "user")
        #expect(msgs.first?["content"] == "Hello")
    }

    @Test("buildRequest body encodes custom model and maxTokens")
    func requestBodyEncodingCustom() throws {
        let service = ClaudeAPIService()
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        let request = try service.buildRequest(
            url: url,
            apiKey: "key",
            systemPrompt: "system",
            messages: [ChatMessage(role: .user, content: "Hello")],
            model: "claude-opus-4-20250115",
            maxTokens: 8192
        )
        let body = try #require(request.httpBody)
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        #expect(json?["model"] as? String == "claude-opus-4-20250115")
        #expect(json?["max_tokens"] as? Int == 8192)
    }

    // MARK: - SSE parsing

    @Test("parseSSELine returns .text for content_block_delta event with text")
    func parseTextDelta() throws {
        let service = ClaudeAPIService()
        let json = #"{"type":"content_block_delta","delta":{"type":"text_delta","text":"Hello"}}"#
        #expect(try service.parseSSELine(json) == .text("Hello"))
    }

    @Test("parseSSELine returns .skipped for non-delta event types")
    func parseNonDelta() throws {
        let service = ClaudeAPIService()
        let json = #"{"type":"message_start","message":{"id":"abc"}}"#
        #expect(try service.parseSSELine(json) == .skipped)
    }

    @Test("parseSSELine returns .decodeFailed for malformed JSON")
    func parseMalformed() throws {
        let service = ClaudeAPIService()
        #expect(try service.parseSSELine("not json at all") == .decodeFailed)
    }

    @Test("parseSSELine returns .skipped for content_block_delta with no text field")
    func parseDeltaNoText() throws {
        let service = ClaudeAPIService()
        let json = #"{"type":"content_block_delta","delta":{"type":"input_json_delta","partial_json":"{}"}}"#
        #expect(try service.parseSSELine(json) == .skipped)
    }

    // MARK: - SSE error event handling

    @Test("parseSSELine throws serverError for error event with message")
    func parseErrorEvent() {
        let service = ClaudeAPIService()
        let json = #"{"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#
        #expect(throws: AIServiceError.self) {
            try service.parseSSELine(json)
        }
    }

    @Test("parseSSELine throws serverError with the error message from the event")
    func parseErrorEventMessage() {
        let service = ClaudeAPIService()
        let json = #"{"type":"error","error":{"type":"rate_limit_error","message":"Rate limit exceeded"}}"#
        do {
            _ = try service.parseSSELine(json)
            Issue.record("Expected parseSSELine to throw")
        } catch let error as AIServiceError {
            guard case .serverError(let message) = error else {
                Issue.record("Expected serverError, got \(error)")
                return
            }
            #expect(message == "Rate limit exceeded")
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("parseSSELine throws serverError with fallback message when error object has no message")
    func parseErrorEventNoMessage() {
        let service = ClaudeAPIService()
        let json = #"{"type":"error","error":{"type":"internal_error"}}"#
        do {
            _ = try service.parseSSELine(json)
            Issue.record("Expected parseSSELine to throw")
        } catch let error as AIServiceError {
            guard case .serverError(let message) = error else {
                Issue.record("Expected serverError, got \(error)")
                return
            }
            #expect(message == "Unknown server error")
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("parseSSELine throws serverError with fallback message when error object is absent")
    func parseErrorEventNoErrorObject() {
        let service = ClaudeAPIService()
        let json = #"{"type":"error"}"#
        do {
            _ = try service.parseSSELine(json)
            Issue.record("Expected parseSSELine to throw")
        } catch let error as AIServiceError {
            guard case .serverError(let message) = error else {
                Issue.record("Expected serverError, got \(error)")
                return
            }
            #expect(message == "Unknown server error")
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    // MARK: - LocalizedError conformance

    @Test("localizedDescription returns server message for serverError")
    func localizedDescriptionServerError() {
        let error = AIServiceError.serverError(message: "Rate limit exceeded")
        #expect(error.localizedDescription == "Rate limit exceeded")
    }

    @Test("localizedDescription returns descriptive message for httpError")
    func localizedDescriptionHTTPError() {
        let error = AIServiceError.httpError(statusCode: 429)
        #expect(error.localizedDescription == "The server returned HTTP 429.")
    }

    @Test("localizedDescription returns descriptive message for missingAPIKey")
    func localizedDescriptionMissingAPIKey() {
        let error = AIServiceError.missingAPIKey
        #expect(error.localizedDescription == "No API key configured.")
    }

    @Test("localizedDescription returns descriptive message for invalidURL")
    func localizedDescriptionInvalidURL() {
        let error = AIServiceError.invalidURL
        #expect(error.localizedDescription == "The API URL is invalid.")
    }

    @Test("localizedDescription returns descriptive message for excessiveDecodeFailures")
    func localizedDescriptionExcessiveDecodeFailures() {
        let error = AIServiceError.excessiveDecodeFailures(count: 5)
        #expect(error.localizedDescription == "Unable to read the AI response (5 consecutive events could not be decoded). Please try again or check for app updates.")
    }

    // MARK: - SSEParseResult discrimination

    @Test("parseSSELine returns .skipped for all known non-delta SSE event types")
    func parseNonDeltaEventsReturnSkipped() throws {
        let service = ClaudeAPIService()
        let knownNonDeltaEvents = [
            #"{"type":"message_start","message":{"id":"msg_123"}}"#,
            #"{"type":"content_block_start","index":0,"content_block":{"type":"text"}}"#,
            #"{"type":"content_block_stop","index":0}"#,
            #"{"type":"message_delta","delta":{"stop_reason":"end_turn"}}"#,
            #"{"type":"message_stop"}"#,
        ]
        for json in knownNonDeltaEvents {
            #expect(try service.parseSSELine(json) == .skipped)
        }
    }
}
