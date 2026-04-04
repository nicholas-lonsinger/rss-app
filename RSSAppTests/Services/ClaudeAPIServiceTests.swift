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
    func parseTextDelta() {
        let service = ClaudeAPIService(defaults: makeTestDefaults())
        let json = #"{"type":"content_block_delta","delta":{"type":"text_delta","text":"Hello"}}"#
        #expect(service.parseSSELine(json) == "Hello")
    }

    @Test("parseSSELine returns nil for non-delta event types")
    func parseNonDelta() {
        let service = ClaudeAPIService(defaults: makeTestDefaults())
        let json = #"{"type":"message_start","message":{"id":"abc"}}"#
        #expect(service.parseSSELine(json) == nil)
    }

    @Test("parseSSELine returns nil for malformed JSON")
    func parseMalformed() {
        let service = ClaudeAPIService(defaults: makeTestDefaults())
        #expect(service.parseSSELine("not json at all") == nil)
    }

    @Test("parseSSELine returns nil for content_block_delta with no text field")
    func parseDeltaNoText() {
        let service = ClaudeAPIService(defaults: makeTestDefaults())
        let json = #"{"type":"content_block_delta","delta":{"type":"input_json_delta","partial_json":"{}"}}"#
        #expect(service.parseSSELine(json) == nil)
    }
}
