import Foundation
import Testing
@testable import RSSApp

/// Integration tests for `ClaudeAPIService.sendMessage` that exercise the
/// consecutive decode failure counter, stream completion, and SSE line routing
/// end-to-end — using `MockURLSessionBytesProvider` to inject controlled SSE
/// line sequences without network access.
@Suite("ClaudeAPIService — sendMessage integration")
struct ClaudeAPIServiceSendMessageTests {

    /// Helper: collects all yielded chunks from the stream, or throws if the stream errors.
    private func collectStream(_ stream: AsyncThrowingStream<String, Error>) async throws -> [String] {
        var chunks: [String] = []
        for try await chunk in stream {
            chunks.append(chunk)
        }
        return chunks
    }

    /// Helper: builds SSE data lines from raw JSON strings.
    private func sseLines(_ jsonLines: [String]) -> [String] {
        jsonLines.map { "data: \($0)" }
    }

    /// A valid `content_block_delta` SSE JSON that yields the given text.
    private func textDeltaJSON(_ text: String) -> String {
        #"{"type":"content_block_delta","delta":{"type":"text_delta","text":"\#(text)"}}"#
    }

    /// A known non-delta SSE JSON (message_start) that parses as `.skipped`.
    private var skippedJSON: String {
        #"{"type":"message_start","message":{"id":"msg_test"}}"#
    }

    /// Malformed JSON that parses as `.decodeFailed`.
    private var decodeFailedJSON: String {
        "not valid json"
    }

    private func makeSendMessage(mock: MockURLSessionBytesProvider) async throws -> AsyncThrowingStream<String, Error> {
        let service = ClaudeAPIService(session: mock)
        return try await service.sendMessage(
            systemPrompt: "test",
            messages: [ChatMessage(role: .user, content: "hi")],
            model: "claude-haiku-4-5-20251001",
            maxTokens: 4096,
            apiKey: "sk-test"
        )
    }

    // MARK: - Threshold reached: consecutive .decodeFailed triggers error

    @Test("sendMessage throws excessiveDecodeFailures after 5 consecutive decode failures")
    func consecutiveDecodeFailuresReachThreshold() async throws {
        let mock = MockURLSessionBytesProvider()
        mock.lines = sseLines(Array(repeating: decodeFailedJSON, count: 5))
        let stream = try await makeSendMessage(mock: mock)

        await #expect(throws: AIServiceError.self) {
            _ = try await collectStream(stream)
        }
    }

    @Test("excessiveDecodeFailures reports correct count")
    func excessiveDecodeFailuresCount() async throws {
        let mock = MockURLSessionBytesProvider()
        mock.lines = sseLines(Array(repeating: decodeFailedJSON, count: 5))
        let stream = try await makeSendMessage(mock: mock)

        do {
            _ = try await collectStream(stream)
            Issue.record("Expected stream to throw")
        } catch let error as AIServiceError {
            guard case .excessiveDecodeFailures(let count) = error else {
                Issue.record("Expected excessiveDecodeFailures, got \(error)")
                return
            }
            #expect(count == 5)
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("sendMessage does not throw when decode failures are below threshold")
    func decodeFailuresBelowThreshold() async throws {
        let mock = MockURLSessionBytesProvider()
        // 4 failures (below threshold of 5), then stream ends normally
        mock.lines = sseLines(Array(repeating: decodeFailedJSON, count: 4))
        let stream = try await makeSendMessage(mock: mock)

        let chunks = try await collectStream(stream)
        #expect(chunks.isEmpty)
    }

    // MARK: - .text resets the counter

    @Test("text event resets consecutive decode failure counter")
    func textResetsCounter() async throws {
        let mock = MockURLSessionBytesProvider()
        // 4 failures, then a text event resets the counter, then 4 more failures — should NOT trigger error
        var lines: [String] = []
        lines.append(contentsOf: Array(repeating: decodeFailedJSON, count: 4))
        lines.append(textDeltaJSON("reset"))
        lines.append(contentsOf: Array(repeating: decodeFailedJSON, count: 4))
        mock.lines = sseLines(lines)
        let stream = try await makeSendMessage(mock: mock)

        let chunks = try await collectStream(stream)
        #expect(chunks == ["reset"])
    }

    @Test("text event resets counter — threshold still triggers after reset")
    func textResetsCounterThenThresholdReached() async throws {
        let mock = MockURLSessionBytesProvider()
        // 4 failures, text resets, then 5 failures — should trigger error
        var lines: [String] = []
        lines.append(contentsOf: Array(repeating: decodeFailedJSON, count: 4))
        lines.append(textDeltaJSON("reset"))
        lines.append(contentsOf: Array(repeating: decodeFailedJSON, count: 5))
        mock.lines = sseLines(lines)
        let stream = try await makeSendMessage(mock: mock)

        do {
            _ = try await collectStream(stream)
            Issue.record("Expected stream to throw")
        } catch let error as AIServiceError {
            guard case .excessiveDecodeFailures(let count) = error else {
                Issue.record("Expected excessiveDecodeFailures, got \(error)")
                return
            }
            #expect(count == 5)
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    // MARK: - .skipped does not increment counter

    @Test("skipped events do not increment the decode failure counter")
    func skippedDoesNotIncrementCounter() async throws {
        let mock = MockURLSessionBytesProvider()
        // Interleave skipped events among decode failures — should not push over the threshold
        var lines: [String] = []
        lines.append(contentsOf: Array(repeating: decodeFailedJSON, count: 4))
        lines.append(skippedJSON)
        lines.append(skippedJSON)
        lines.append(skippedJSON)
        // Still only 4 consecutive failures — skipped events don't reset or increment
        mock.lines = sseLines(lines)
        let stream = try await makeSendMessage(mock: mock)

        // Should complete without error since only 4 consecutive failures occurred
        let chunks = try await collectStream(stream)
        #expect(chunks.isEmpty)
    }

    @Test("skipped events between decode failures preserve consecutive count")
    func skippedBetweenFailuresPreservesCount() async throws {
        let mock = MockURLSessionBytesProvider()
        // 3 failures, skipped, 2 more failures — total 5 consecutive (skipped doesn't reset)
        var lines: [String] = []
        lines.append(contentsOf: Array(repeating: decodeFailedJSON, count: 3))
        lines.append(skippedJSON)
        lines.append(contentsOf: Array(repeating: decodeFailedJSON, count: 2))
        mock.lines = sseLines(lines)
        let stream = try await makeSendMessage(mock: mock)

        await #expect(throws: AIServiceError.self) {
            _ = try await collectStream(stream)
        }
    }

    // MARK: - Mixed sequences

    @Test("mixed sequence: text chunks are yielded and decode failures counted correctly")
    func mixedSequence() async throws {
        let mock = MockURLSessionBytesProvider()
        var lines: [String] = []
        lines.append(skippedJSON)                  // skipped
        lines.append(textDeltaJSON("Hello"))        // text — counter stays 0
        lines.append(decodeFailedJSON)              // failure 1
        lines.append(decodeFailedJSON)              // failure 2
        lines.append(textDeltaJSON(" world"))       // text — resets to 0
        lines.append(skippedJSON)                  // skipped
        lines.append(decodeFailedJSON)              // failure 1
        mock.lines = sseLines(lines)
        let stream = try await makeSendMessage(mock: mock)

        let chunks = try await collectStream(stream)
        #expect(chunks == ["Hello", " world"])
    }

    // MARK: - Normal stream completion

    @Test("sendMessage yields text chunks and finishes cleanly with no failures")
    func normalStreamCompletion() async throws {
        let mock = MockURLSessionBytesProvider()
        mock.lines = sseLines([
            skippedJSON,
            textDeltaJSON("Hello"),
            textDeltaJSON(" world"),
            skippedJSON,
        ])
        let stream = try await makeSendMessage(mock: mock)

        let chunks = try await collectStream(stream)
        #expect(chunks == ["Hello", " world"])
    }

    @Test("sendMessage handles [DONE] sentinel and stops reading")
    func doneSentinelStopsStream() async throws {
        let mock = MockURLSessionBytesProvider()
        mock.lines = [
            "data: " + textDeltaJSON("before"),
            "data: [DONE]",
            "data: " + textDeltaJSON("after"),   // should never be reached
        ]
        let stream = try await makeSendMessage(mock: mock)

        let chunks = try await collectStream(stream)
        #expect(chunks == ["before"])
    }

    @Test("sendMessage ignores lines without data: prefix")
    func nonDataLinesIgnored() async throws {
        let mock = MockURLSessionBytesProvider()
        mock.lines = [
            "event: message_start",
            "data: " + textDeltaJSON("included"),
            ": comment line",
            "data: " + textDeltaJSON(" too"),
        ]
        let stream = try await makeSendMessage(mock: mock)

        let chunks = try await collectStream(stream)
        #expect(chunks == ["included", " too"])
    }

    // MARK: - HTTP error handling

    @Test("sendMessage throws httpError for non-2xx status codes")
    func httpErrorStatusCode() async throws {
        let mock = MockURLSessionBytesProvider()
        mock.statusCode = 429
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
            #expect(statusCode == 429)
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    // MARK: - Server error event propagation

    @Test("sendMessage propagates server error events from the stream")
    func serverErrorEventPropagation() async throws {
        let mock = MockURLSessionBytesProvider()
        mock.lines = sseLines([
            textDeltaJSON("partial"),
            #"{"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#,
        ])
        let stream = try await makeSendMessage(mock: mock)

        do {
            _ = try await collectStream(stream)
            Issue.record("Expected stream to throw")
        } catch let error as AIServiceError {
            guard case .serverError(let message) = error else {
                Issue.record("Expected serverError, got \(error)")
                return
            }
            #expect(message == "Overloaded")
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }
}
