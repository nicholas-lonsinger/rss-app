import Foundation
import Testing
@testable import RSSApp

@Suite("ClaudeAPIService")
struct ClaudeAPIServiceTests {

    private let service = ClaudeAPIService()

    // MARK: - Request building

    @Test("buildRequest sets correct headers and HTTP method")
    func requestHeaders() throws {
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

    @Test("buildRequest body encodes correct JSON structure")
    func requestBodyEncoding() throws {
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
        #expect(json?["model"] as? String == "claude-sonnet-4-6")
        #expect(json?["max_tokens"] as? Int == 1024)
        #expect(json?["stream"] as? Bool == true)
        #expect(json?["system"] as? String == "system")
        let msgs = try #require(json?["messages"] as? [[String: String]])
        #expect(msgs.first?["role"] == "user")
        #expect(msgs.first?["content"] == "Hello")
    }

    // MARK: - SSE parsing

    @Test("parseSSELine extracts text from content_block_delta event")
    func parseTextDelta() {
        let json = #"{"type":"content_block_delta","delta":{"type":"text_delta","text":"Hello"}}"#
        #expect(service.parseSSELine(json) == "Hello")
    }

    @Test("parseSSELine returns nil for non-delta event types")
    func parseNonDelta() {
        let json = #"{"type":"message_start","message":{"id":"abc"}}"#
        #expect(service.parseSSELine(json) == nil)
    }

    @Test("parseSSELine returns nil for malformed JSON")
    func parseMalformed() {
        #expect(service.parseSSELine("not json at all") == nil)
    }

    @Test("parseSSELine returns nil for content_block_delta with no text field")
    func parseDeltaNoText() {
        let json = #"{"type":"content_block_delta","delta":{"type":"input_json_delta","partial_json":"{}"}}"#
        #expect(service.parseSSELine(json) == nil)
    }
}
