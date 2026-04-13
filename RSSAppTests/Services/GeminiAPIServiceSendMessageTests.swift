import Foundation
import Testing
@testable import RSSApp

/// Integration tests for `GeminiAPIService.sendMessage` using
/// `MockURLSessionBytesProvider` to inject controlled SSE line sequences.
@Suite("GeminiAPIService — sendMessage integration")
struct GeminiAPIServiceSendMessageTests {

    private func collectStream(_ stream: AsyncThrowingStream<String, Error>) async throws -> [String] {
        var chunks: [String] = []
        for try await chunk in stream {
            chunks.append(chunk)
        }
        return chunks
    }

    private func sseLines(_ jsonLines: [String]) -> [String] {
        jsonLines.map { "data: \($0)" }
    }

    private func textChunkJSON(_ text: String) -> String {
        // Escaping: replace " with \" in the text parameter
        let escaped = text.replacingOccurrences(of: "\"", with: "\\\"")
        return """
        {"candidates":[{"content":{"role":"model","parts":[{"text":"\(escaped)"}]}}]}
        """
    }

    private var malformedJSON: String { "not valid json" }

    private func makeSendMessage(mock: MockURLSessionBytesProvider) async throws -> AsyncThrowingStream<String, Error> {
        let service = GeminiAPIService(session: mock)
        return try await service.sendMessage(
            systemPrompt: "test",
            messages: [ChatMessage(role: .user, content: "hi")],
            model: "gemini-2.5-flash",
            maxTokens: 8192,
            apiKey: "AIzaSy-test"
        )
    }

    // MARK: - Normal stream completion

    @Test("sendMessage yields text chunks and finishes cleanly")
    func normalStreamCompletion() async throws {
        let mock = MockURLSessionBytesProvider()
        mock.lines = sseLines([
            textChunkJSON("Hello"),
            textChunkJSON(" world"),
        ])
        let stream = try await makeSendMessage(mock: mock)
        let chunks = try await collectStream(stream)
        #expect(chunks == ["Hello", " world"])
    }

    @Test("sendMessage handles empty candidates gracefully")
    func emptyCandidatesSkipped() async throws {
        let mock = MockURLSessionBytesProvider()
        mock.lines = sseLines([
            #"{"candidates":[]}"#,
            textChunkJSON("after"),
        ])
        let stream = try await makeSendMessage(mock: mock)
        let chunks = try await collectStream(stream)
        #expect(chunks == ["after"])
    }

    // MARK: - Decode failure threshold

    @Test("sendMessage throws excessiveDecodeFailures after 5 consecutive decode failures")
    func consecutiveDecodeFailuresThreshold() async throws {
        let mock = MockURLSessionBytesProvider()
        mock.lines = sseLines(Array(repeating: malformedJSON, count: 5))
        let stream = try await makeSendMessage(mock: mock)

        await #expect(throws: AIServiceError.self) {
            _ = try await collectStream(stream)
        }
    }

    @Test("sendMessage does not throw when decode failures are below threshold")
    func decodeFailuresBelowThreshold() async throws {
        let mock = MockURLSessionBytesProvider()
        mock.lines = sseLines(Array(repeating: malformedJSON, count: 4))
        let stream = try await makeSendMessage(mock: mock)

        let chunks = try await collectStream(stream)
        #expect(chunks.isEmpty)
    }

    @Test("text event resets consecutive decode failure counter")
    func textResetsCounter() async throws {
        let mock = MockURLSessionBytesProvider()
        var lines: [String] = []
        lines.append(contentsOf: Array(repeating: malformedJSON, count: 4))
        lines.append(textChunkJSON("reset"))
        lines.append(contentsOf: Array(repeating: malformedJSON, count: 4))
        mock.lines = sseLines(lines)
        let stream = try await makeSendMessage(mock: mock)

        let chunks = try await collectStream(stream)
        #expect(chunks == ["reset"])
    }

    // MARK: - HTTP error handling

    @Test("sendMessage throws httpError for non-2xx status codes")
    func httpErrorStatusCode() async throws {
        let mock = MockURLSessionBytesProvider()
        mock.statusCode = 401
        mock.lines = []
        let stream = try await makeSendMessage(mock: mock)

        do {
            _ = try await collectStream(stream)
            Issue.record("Expected stream to throw")
        } catch let error as AIServiceError {
            guard case .httpError(let statusCode) = error else {
                Issue.record("Expected httpError, got \(error)")
                return
            }
            #expect(statusCode == 401)
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    // MARK: - Missing API key

    @Test("sendMessage throws missingAPIKey when apiKey is empty")
    func missingAPIKey() async throws {
        let service = GeminiAPIService()
        await #expect(throws: AIServiceError.self) {
            _ = try await service.sendMessage(
                systemPrompt: "test",
                messages: [],
                model: "gemini-2.5-flash",
                maxTokens: 1024,
                apiKey: ""
            )
        }
    }
}
