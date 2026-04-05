import Foundation
import Testing
@testable import RSSApp

@Suite("ClaudeAPIService")
struct ClaudeAPIServiceTests {

    /// Creates a test-specific UserDefaults suite to avoid polluting the real defaults.
    private func makeTestDefaults() -> UserDefaults {
        let suiteName = "com.rssapp.test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    // MARK: - Request building

    @Test("buildRequest sets correct headers and HTTP method")
    func requestHeaders() throws {
        let service = ClaudeAPIService(defaults: makeTestDefaults())
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        let request = try service.buildRequest(
            url: url,
            apiKey: "sk-test-key",
            systemPrompt: "You are helpful.",
            messages: []
        )
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "x-api-key") == "sk-test-key")
        #expect(request.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
        #expect(request.value(forHTTPHeaderField: "content-type") == "application/json")
    }

    @Test("buildRequest body encodes correct JSON structure with defaults")
    func requestBodyEncodingDefaults() throws {
        let service = ClaudeAPIService(defaults: makeTestDefaults())
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        let messages = [ChatMessage(role: .user, content: "Hello")]
        let request = try service.buildRequest(
            url: url,
            apiKey: "key",
            systemPrompt: "system",
            messages: messages
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

    @Test("buildRequest body uses custom model and maxTokens from UserDefaults")
    func requestBodyEncodingCustom() throws {
        let defaults = makeTestDefaults()
        defaults.set("claude-opus-4-20250115", forKey: ClaudeAPIService.modelDefaultsKey)
        defaults.set(8192, forKey: ClaudeAPIService.maxTokensDefaultsKey)
        let service = ClaudeAPIService(defaults: defaults)
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        let request = try service.buildRequest(
            url: url,
            apiKey: "key",
            systemPrompt: "system",
            messages: [ChatMessage(role: .user, content: "Hello")]
        )
        let body = try #require(request.httpBody)
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        #expect(json?["model"] as? String == "claude-opus-4-20250115")
        #expect(json?["max_tokens"] as? Int == 8192)
    }

    // MARK: - UserDefaults reading

    @Test("model returns default when UserDefaults has no stored value")
    func modelDefaultValue() {
        let service = ClaudeAPIService(defaults: makeTestDefaults())
        #expect(service.model == "claude-haiku-4-5-20251001")
    }

    @Test("model returns stored value from UserDefaults")
    func modelStoredValue() {
        let defaults = makeTestDefaults()
        defaults.set("claude-sonnet-4-20250514", forKey: ClaudeAPIService.modelDefaultsKey)
        let service = ClaudeAPIService(defaults: defaults)
        #expect(service.model == "claude-sonnet-4-20250514")
    }

    @Test("model returns default when stored value is empty string")
    func modelEmptyString() {
        let defaults = makeTestDefaults()
        defaults.set("", forKey: ClaudeAPIService.modelDefaultsKey)
        let service = ClaudeAPIService(defaults: defaults)
        #expect(service.model == "claude-haiku-4-5-20251001")
    }

    @Test("maxTokens returns default when UserDefaults has no stored value")
    func maxTokensDefaultValue() {
        let service = ClaudeAPIService(defaults: makeTestDefaults())
        #expect(service.maxTokens == 4096)
    }

    @Test("maxTokens returns stored value from UserDefaults")
    func maxTokensStoredValue() {
        let defaults = makeTestDefaults()
        defaults.set(2048, forKey: ClaudeAPIService.maxTokensDefaultsKey)
        let service = ClaudeAPIService(defaults: defaults)
        #expect(service.maxTokens == 2048)
    }

    @Test("maxTokens returns default when stored value is 0")
    func maxTokensZero() {
        let defaults = makeTestDefaults()
        defaults.set(0, forKey: ClaudeAPIService.maxTokensDefaultsKey)
        let service = ClaudeAPIService(defaults: defaults)
        #expect(service.maxTokens == 4096)
    }

    @Test("maxTokens returns default when stored value is negative")
    func maxTokensNegative() {
        let defaults = makeTestDefaults()
        defaults.set(-100, forKey: ClaudeAPIService.maxTokensDefaultsKey)
        let service = ClaudeAPIService(defaults: defaults)
        #expect(service.maxTokens == 4096)
    }

    @Test("changes to UserDefaults are reflected immediately without reinit")
    func dynamicReading() {
        let defaults = makeTestDefaults()
        let service = ClaudeAPIService(defaults: defaults)
        #expect(service.model == "claude-haiku-4-5-20251001")
        defaults.set("claude-opus-4-20250115", forKey: ClaudeAPIService.modelDefaultsKey)
        #expect(service.model == "claude-opus-4-20250115")
    }

    // MARK: - SSE parsing

    @Test("parseSSELine extracts text from content_block_delta event")
    func parseTextDelta() throws {
        let service = ClaudeAPIService(defaults: makeTestDefaults())
        let json = #"{"type":"content_block_delta","delta":{"type":"text_delta","text":"Hello"}}"#
        #expect(try service.parseSSELine(json) == "Hello")
    }

    @Test("parseSSELine returns nil for non-delta event types")
    func parseNonDelta() throws {
        let service = ClaudeAPIService(defaults: makeTestDefaults())
        let json = #"{"type":"message_start","message":{"id":"abc"}}"#
        #expect(try service.parseSSELine(json) == nil)
    }

    @Test("parseSSELine returns nil for malformed JSON")
    func parseMalformed() throws {
        let service = ClaudeAPIService(defaults: makeTestDefaults())
        #expect(try service.parseSSELine("not json at all") == nil)
    }

    @Test("parseSSELine returns nil for content_block_delta with no text field")
    func parseDeltaNoText() throws {
        let service = ClaudeAPIService(defaults: makeTestDefaults())
        let json = #"{"type":"content_block_delta","delta":{"type":"input_json_delta","partial_json":"{}"}}"#
        #expect(try service.parseSSELine(json) == nil)
    }

    // MARK: - SSE error event handling

    @Test("parseSSELine throws serverError for error event with message")
    func parseErrorEvent() {
        let service = ClaudeAPIService(defaults: makeTestDefaults())
        let json = #"{"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#
        #expect(throws: ClaudeAPIError.self) {
            try service.parseSSELine(json)
        }
    }

    @Test("parseSSELine throws serverError with the error message from the event")
    func parseErrorEventMessage() {
        let service = ClaudeAPIService(defaults: makeTestDefaults())
        let json = #"{"type":"error","error":{"type":"rate_limit_error","message":"Rate limit exceeded"}}"#
        do {
            _ = try service.parseSSELine(json)
            Issue.record("Expected parseSSELine to throw")
        } catch let error as ClaudeAPIError {
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
        let service = ClaudeAPIService(defaults: makeTestDefaults())
        let json = #"{"type":"error","error":{"type":"internal_error"}}"#
        do {
            _ = try service.parseSSELine(json)
            Issue.record("Expected parseSSELine to throw")
        } catch let error as ClaudeAPIError {
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
        let service = ClaudeAPIService(defaults: makeTestDefaults())
        let json = #"{"type":"error"}"#
        do {
            _ = try service.parseSSELine(json)
            Issue.record("Expected parseSSELine to throw")
        } catch let error as ClaudeAPIError {
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
        let error = ClaudeAPIError.serverError(message: "Rate limit exceeded")
        #expect(error.localizedDescription == "Rate limit exceeded")
    }

    @Test("localizedDescription returns descriptive message for httpError")
    func localizedDescriptionHTTPError() {
        let error = ClaudeAPIError.httpError(statusCode: 429)
        #expect(error.localizedDescription == "The server returned HTTP 429.")
    }

    @Test("localizedDescription returns descriptive message for missingAPIKey")
    func localizedDescriptionMissingAPIKey() {
        let error = ClaudeAPIError.missingAPIKey
        #expect(error.localizedDescription == "No API key configured.")
    }

    @Test("localizedDescription returns descriptive message for invalidURL")
    func localizedDescriptionInvalidURL() {
        let error = ClaudeAPIError.invalidURL
        #expect(error.localizedDescription == "The API URL is invalid.")
    }

    @Test("localizedDescription returns descriptive message for excessiveDecodeFailures")
    func localizedDescriptionExcessiveDecodeFailures() {
        let error = ClaudeAPIError.excessiveDecodeFailures(count: 5)
        #expect(error.localizedDescription == "Failed to decode 5 consecutive server events. The response format may have changed.")
    }

    // MARK: - Consecutive decode failure threshold

    @Test("consecutiveDecodeFailureThreshold is 5")
    func consecutiveDecodeFailureThreshold() {
        #expect(ClaudeAPIService.consecutiveDecodeFailureThreshold == 5)
    }

    @Test("parseSSELine returns nil for non-delta events without affecting caller state")
    func parseNonDeltaEventsReturnNil() throws {
        let service = ClaudeAPIService(defaults: makeTestDefaults())
        // These known event types should return nil (not throw) and would
        // increment a caller's consecutive-failure counter
        let knownNonDeltaEvents = [
            #"{"type":"message_start","message":{"id":"msg_123"}}"#,
            #"{"type":"content_block_start","index":0,"content_block":{"type":"text"}}"#,
            #"{"type":"content_block_stop","index":0}"#,
            #"{"type":"message_delta","delta":{"stop_reason":"end_turn"}}"#,
            #"{"type":"message_stop"}"#,
        ]
        for json in knownNonDeltaEvents {
            #expect(try service.parseSSELine(json) == nil)
        }
    }

    @Test("parseSSELine returns text for content_block_delta, allowing caller to reset failure counter")
    func parseDeltaResetsCounter() throws {
        let service = ClaudeAPIService(defaults: makeTestDefaults())
        let delta = #"{"type":"content_block_delta","delta":{"type":"text_delta","text":"chunk"}}"#
        let result = try service.parseSSELine(delta)
        #expect(result == "chunk")
    }

    @Test("excessiveDecodeFailures includes count in error description")
    func excessiveDecodeFailuresCount() {
        let error7 = ClaudeAPIError.excessiveDecodeFailures(count: 7)
        #expect(error7.localizedDescription.contains("7"))
        let error10 = ClaudeAPIError.excessiveDecodeFailures(count: 10)
        #expect(error10.localizedDescription.contains("10"))
    }
}
