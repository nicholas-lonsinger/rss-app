import Foundation
import Testing
@testable import RSSApp

@Suite("GeminiModelService")
struct GeminiModelServiceTests {

    // MARK: - Helpers

    private func makeService(mock: MockURLSessionDataProvider) -> GeminiModelService {
        GeminiModelService(session: mock)
    }

    private func makePayload(_ models: [[String: Any]]) throws -> Data {
        let body: [String: Any] = ["models": models]
        return try JSONSerialization.data(withJSONObject: body)
    }

    private func modelJSON(
        name: String,
        displayName: String? = nil,
        supportedMethods: [String]? = nil
    ) -> [String: Any] {
        var dict: [String: Any] = ["name": name]
        if let displayName { dict["displayName"] = displayName }
        if let supportedMethods { dict["supportedGenerationMethods"] = supportedMethods }
        return dict
    }

    // MARK: - Request headers

    @Test("fetchModels sends x-goog-api-key header")
    func requestSendsAPIKeyHeader() async throws {
        let mock = MockURLSessionDataProvider()
        mock.jsonPayload = try makePayload([])
        var capturedRequest: URLRequest?

        // Use a closure-based approach: intercept via MockDataURLProtocol's
        // request-capture path by observing which key was injected via a thin
        // wrapper mock that records the request before delegating.
        final class CapturingProvider: URLSessionDataProviding, @unchecked Sendable {
            var captured: URLRequest?
            let inner: MockURLSessionDataProvider
            init(inner: MockURLSessionDataProvider) { self.inner = inner }
            func data(for request: URLRequest) async throws -> (Data, URLResponse) {
                captured = request
                return try await inner.data(for: request)
            }
        }

        let capturing = CapturingProvider(inner: mock)
        let service = GeminiModelService(session: capturing)
        _ = try await service.fetchModels(apiKey: "AIzaSy-test-key")
        capturedRequest = capturing.captured

        #expect(capturedRequest?.value(forHTTPHeaderField: "x-goog-api-key") == "AIzaSy-test-key")
        #expect(capturedRequest?.value(forHTTPHeaderField: "accept") == "application/json")
    }

    // MARK: - Response parsing

    @Test("fetchModels returns models that support generateContent")
    func returnsFilteredModels() async throws {
        let mock = MockURLSessionDataProvider()
        mock.jsonPayload = try makePayload([
            modelJSON(
                name: "models/gemini-2.5-flash",
                displayName: "Gemini 2.5 Flash",
                supportedMethods: ["generateContent", "countTokens"]
            ),
            modelJSON(
                name: "models/embedding-001",
                displayName: "Embedding 001",
                supportedMethods: ["embedContent"]
            ),
        ])

        let service = makeService(mock: mock)
        let models = try await service.fetchModels(apiKey: "key")

        #expect(models.count == 1)
        #expect(models[0].id == "gemini-2.5-flash")
        #expect(models[0].displayName == "Gemini 2.5 Flash")
    }

    @Test("fetchModels strips the 'models/' prefix from the name field")
    func stripsModelsPrefix() async throws {
        let mock = MockURLSessionDataProvider()
        mock.jsonPayload = try makePayload([
            modelJSON(
                name: "models/gemini-2.5-pro",
                displayName: "Gemini 2.5 Pro",
                supportedMethods: ["generateContent"]
            ),
        ])

        let service = makeService(mock: mock)
        let models = try await service.fetchModels(apiKey: "key")

        #expect(models.count == 1)
        #expect(models[0].id == "gemini-2.5-pro")
    }

    @Test("fetchModels uses raw name when 'models/' prefix is absent")
    func handlesNameWithoutPrefix() async throws {
        let mock = MockURLSessionDataProvider()
        mock.jsonPayload = try makePayload([
            modelJSON(
                name: "gemini-experimental",
                displayName: "Gemini Experimental",
                supportedMethods: ["generateContent"]
            ),
        ])

        let service = makeService(mock: mock)
        let models = try await service.fetchModels(apiKey: "key")

        #expect(models.count == 1)
        #expect(models[0].id == "gemini-experimental")
    }

    @Test("fetchModels falls back to id when displayName is absent")
    func fallsBackToIDForDisplayName() async throws {
        let mock = MockURLSessionDataProvider()
        mock.jsonPayload = try makePayload([
            modelJSON(
                name: "models/gemini-no-name",
                supportedMethods: ["generateContent"]
            ),
        ])

        let service = makeService(mock: mock)
        let models = try await service.fetchModels(apiKey: "key")

        #expect(models.count == 1)
        #expect(models[0].displayName == "gemini-no-name")
    }

    @Test("fetchModels excludes models with no supportedGenerationMethods")
    func excludesModelsWithoutMethods() async throws {
        let mock = MockURLSessionDataProvider()
        mock.jsonPayload = try makePayload([
            modelJSON(
                name: "models/gemini-mystery",
                displayName: "Mystery"
                // no supportedGenerationMethods key
            ),
        ])

        let service = makeService(mock: mock)
        let models = try await service.fetchModels(apiKey: "key")

        #expect(models.isEmpty)
    }

    @Test("fetchModels returns empty array when models array is empty")
    func emptyModelsArray() async throws {
        let mock = MockURLSessionDataProvider()
        mock.jsonPayload = try makePayload([])

        let service = makeService(mock: mock)
        let models = try await service.fetchModels(apiKey: "key")

        #expect(models.isEmpty)
    }

    @Test("fetchModels returns empty array when models key is absent")
    func missingModelsKey() async throws {
        let mock = MockURLSessionDataProvider()
        mock.jsonPayload = try JSONSerialization.data(withJSONObject: [String: Any]())

        let service = makeService(mock: mock)
        let models = try await service.fetchModels(apiKey: "key")

        #expect(models.isEmpty)
    }

    // MARK: - HTTP error handling

    @Test("fetchModels throws httpError for non-2xx status code")
    func httpErrorStatusCode() async throws {
        let mock = MockURLSessionDataProvider()
        mock.statusCode = 403
        mock.jsonPayload = Data()

        let service = makeService(mock: mock)
        await #expect(throws: AIServiceError.self) {
            _ = try await service.fetchModels(apiKey: "key")
        }
    }

    @Test("fetchModels throws httpError with the returned status code")
    func httpErrorStatusCodeValue() async throws {
        let mock = MockURLSessionDataProvider()
        mock.statusCode = 401
        mock.jsonPayload = Data()

        let service = makeService(mock: mock)
        do {
            _ = try await service.fetchModels(apiKey: "key")
            Issue.record("Expected fetchModels to throw")
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

    // MARK: - Network error propagation

    @Test("fetchModels propagates network errors from the session")
    func propagatesNetworkError() async throws {
        let mock = MockURLSessionDataProvider()
        mock.throwError = URLError(.notConnectedToInternet)

        let service = makeService(mock: mock)
        await #expect(throws: URLError.self) {
            _ = try await service.fetchModels(apiKey: "key")
        }
    }
}
