import Foundation
@testable import RSSApp

@MainActor
final class MockArticleExtractionService: ArticleExtracting {
    private let result: ArticleContent?
    private let error: Error?

    init(result: ArticleContent? = nil, error: Error? = nil) {
        self.result = result
        self.error = error
    }

    func extract(from url: URL, fallbackHTML: String) async throws -> ArticleContent {
        if let error { throw error }
        return result ?? ArticleContent(
            title: "Mock Title",
            byline: nil,
            htmlContent: "<p>Mock content</p>",
            textContent: "Mock content"
        )
    }
}
