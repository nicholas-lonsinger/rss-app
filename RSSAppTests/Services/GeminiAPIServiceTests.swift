import Foundation
import Testing
@testable import RSSApp

@Suite("GeminiAPIService")
struct GeminiAPIServiceTests {

    // MARK: - Request building

    @Test("buildRequest sets x-goog-api-key header")
    func requestAuthHeader() throws {
        let service = GeminiAPIService()
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:streamGenerateContent?alt=sse")!
        let request = try service.buildRequest(
            url: url,
            apiKey: "AIzaSy-test-key",
            systemPrompt: "You are helpful.",
            messages: [],
            maxTokens: 8192
        )
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "x-goog-api-key") == "AIzaSy-test-key")
        #expect(request.value(forHTTPHeaderField: "content-type") == "application/json")
    }

    @Test("buildRequest body encodes contents array with correct roles")
    func requestBodyRoleMapping() throws {
        let service = GeminiAPIService()
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:streamGenerateContent?alt=sse")!
        let messages = [
            ChatMessage(role: .user, content: "Hello"),
            ChatMessage(role: .assistant, content: "Hi there"),
        ]
        let request = try service.buildRequest(
            url: url,
            apiKey: "key",
            systemPrompt: "system prompt",
            messages: messages,
            maxTokens: 1024
        )
        let body = try #require(request.httpBody)
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]

        // Contents array
        let contents = try #require(json?["contents"] as? [[String: Any]])
        #expect(contents.count == 2)
        #expect(contents[0]["role"] as? String == "user")
        #expect(contents[1]["role"] as? String == "model")  // assistant → model

        // System instruction (snake_case via .convertToSnakeCase encoder strategy)
        let sysInstruction = try #require(json?["system_instruction"] as? [String: Any])
        let sysParts = try #require(sysInstruction["parts"] as? [[String: Any]])
        #expect(sysParts.first?["text"] as? String == "system prompt")

        // Generation config (snake_case via .convertToSnakeCase encoder strategy)
        let genConfig = try #require(json?["generation_config"] as? [String: Any])
        #expect(genConfig["max_output_tokens"] as? Int == 1024)
    }

    @Test("buildRequest encodes message parts correctly")
    func requestBodyPartContent() throws {
        let service = GeminiAPIService()
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:streamGenerateContent?alt=sse")!
        let messages = [ChatMessage(role: .user, content: "What is this?")]
        let request = try service.buildRequest(
            url: url,
            apiKey: "key",
            systemPrompt: "system",
            messages: messages,
            maxTokens: 4096
        )
        let body = try #require(request.httpBody)
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        let contents = try #require(json?["contents"] as? [[String: Any]])
        let parts = try #require(contents.first?["parts"] as? [[String: Any]])
        #expect(parts.first?["text"] as? String == "What is this?")
    }

    // MARK: - SSE parsing

    @Test("parseSSELine returns .text for candidate with text content")
    func parseTextChunk() throws {
        let service = GeminiAPIService()
        let json = """
        {"candidates":[{"content":{"role":"model","parts":[{"text":"Hello world"}]}}]}
        """
        #expect(try service.parseSSELine(json) == .text("Hello world"))
    }

    @Test("parseSSELine returns .skipped for candidate with empty text")
    func parseEmptyText() throws {
        let service = GeminiAPIService()
        let json = """
        {"candidates":[{"content":{"role":"model","parts":[{"text":""}]}}]}
        """
        #expect(try service.parseSSELine(json) == .skipped)
    }

    @Test("parseSSELine returns .skipped when candidates array is empty")
    func parseMissingCandidates() throws {
        let service = GeminiAPIService()
        let json = """
        {"candidates":[]}
        """
        #expect(try service.parseSSELine(json) == .skipped)
    }

    @Test("parseSSELine returns .decodeFailed for malformed JSON")
    func parseMalformed() throws {
        let service = GeminiAPIService()
        #expect(try service.parseSSELine("not json at all") == .decodeFailed)
    }

    @Test("parseSSELine returns .skipped when parts array is missing")
    func parseMissingParts() throws {
        let service = GeminiAPIService()
        let json = """
        {"candidates":[{"content":{"role":"model"}}]}
        """
        #expect(try service.parseSSELine(json) == .skipped)
    }

    @Test("parseSSELine throws serverError for error event")
    func parseErrorEvent() {
        let service = GeminiAPIService()
        let json = """
        {"error":{"code":429,"message":"Quota exceeded","status":"RESOURCE_EXHAUSTED"}}
        """
        #expect(throws: AIServiceError.self) {
            try service.parseSSELine(json)
        }
    }
}
