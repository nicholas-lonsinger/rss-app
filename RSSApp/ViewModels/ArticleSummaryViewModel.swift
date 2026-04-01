import Foundation
import Observation
import os

@MainActor
@Observable
final class ArticleSummaryViewModel {

    private static let logger = Logger(
        subsystem: "com.nicholas-lonsinger.rss-app",
        category: "ArticleSummaryViewModel"
    )

    enum State {
        case idle
        case extracting
        case ready(ArticleContent)
        case failed(String)
    }

    var state: State = .idle

    var isReady: Bool {
        if case .ready = state { return true }
        return false
    }

    /// Set once extraction completes; used by the discussion sheet.
    private(set) var extractedContent: ArticleContent?

    private let article: Article
    private let extractor: any ArticleExtracting

    init(article: Article, preExtractedContent: ArticleContent? = nil, extractor: (any ArticleExtracting)? = nil) {
        self.article = article
        self.extractedContent = preExtractedContent
        self.extractor = extractor ?? ArticleExtractionService()
    }

    func loadContent() async {
        do {
            let content: ArticleContent
            if let existing = extractedContent {
                Self.logger.debug("Using pre-extracted content (\(existing.textContent.count, privacy: .public) chars)")
                content = existing
            } else {
                content = try await extractArticle()
            }
            state = .ready(content)
        } catch is CancellationError {
            Self.logger.debug("Content loading cancelled")
        } catch {
            Self.logger.error("Content loading failed: \(error, privacy: .public)")
            state = .failed(error.localizedDescription)
        }
    }

    // MARK: - Private

    private func extractArticle() async throws -> ArticleContent {
        guard let url = article.link else {
            throw ArticleExtractionError.serializerNotFound
        }
        state = .extracting
        Self.logger.debug("Extracting article: '\(self.article.title, privacy: .public)'")
        let content = try await extractor.extract(from: url, fallbackHTML: article.articleDescription)
        extractedContent = content
        Self.logger.notice("Article extracted (\(content.textContent.count, privacy: .public) chars)")
        return content
    }
}
