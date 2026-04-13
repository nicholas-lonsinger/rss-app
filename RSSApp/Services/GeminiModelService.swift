import Foundation
import os

// MARK: - GeminiModel

struct GeminiModel: Sendable, Identifiable, Hashable {
    /// The short model ID used in API requests, e.g. `"gemini-2.5-flash"`.
    let id: String
    /// The human-readable display name, e.g. `"Gemini 2.5 Flash"`.
    let displayName: String
}

// MARK: - GeminiModelFetching

protocol GeminiModelFetching: Sendable {
    func fetchModels(apiKey: String) async throws -> [GeminiModel]
}

// MARK: - GeminiModelService

struct GeminiModelService: GeminiModelFetching {

    private static let logger = Logger(category: "GeminiModelService")
    private static let listURL = "https://generativelanguage.googleapis.com/v1beta/models"

    /// Fetches the list of Gemini models that support `generateContent`.
    ///
    /// Strips the `models/` prefix from each name so the returned `id` values are
    /// ready to use as the `{model}` path component in the streaming API URL.
    func fetchModels(apiKey: String) async throws -> [GeminiModel] {
        guard let url = URL(string: Self.listURL) else {
            Self.logger.fault("Failed to construct Gemini model list URL from '\(Self.listURL, privacy: .public)'")
            assertionFailure("Failed to construct Gemini model list URL")
            throw AIServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("application/json", forHTTPHeaderField: "accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIServiceError.httpError(statusCode: 0)
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            Self.logger.error("Gemini model list fetch returned HTTP \(httpResponse.statusCode, privacy: .public)")
            throw AIServiceError.httpError(statusCode: httpResponse.statusCode)
        }

        let decoded = try JSONDecoder().decode(GeminiModelsResponse.self, from: data)
        let models = (decoded.models ?? [])
            .filter { $0.supportedGenerationMethods?.contains("generateContent") == true }
            .compactMap { raw -> GeminiModel? in
                // Strip "models/" prefix: "models/gemini-2.5-flash" → "gemini-2.5-flash"
                let id = raw.name.hasPrefix("models/")
                    ? String(raw.name.dropFirst("models/".count))
                    : raw.name
                guard !id.isEmpty else { return nil }
                let displayName = raw.displayName ?? id
                return GeminiModel(id: id, displayName: displayName)
            }

        Self.logger.info("Fetched \(models.count, privacy: .public) Gemini models supporting generateContent")
        return models
    }
}

// MARK: - Codable response types

private struct GeminiModelsResponse: Decodable {
    let models: [GeminiModelRaw]?
}

private struct GeminiModelRaw: Decodable {
    let name: String
    let displayName: String?
    let supportedGenerationMethods: [String]?
}
