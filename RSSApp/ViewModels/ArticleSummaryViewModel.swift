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
    private let persistentArticle: PersistentArticle?
    private let persistence: FeedPersisting?

    init(
        article: Article,
        preExtractedContent: ArticleContent? = nil,
        extractor: (any ArticleExtracting)? = nil,
        persistentArticle: PersistentArticle? = nil,
        persistence: FeedPersisting? = nil
    ) {
        self.article = article
        self.extractedContent = preExtractedContent
        self.extractor = extractor ?? ArticleExtractionService()
        self.persistentArticle = persistentArticle
        self.persistence = persistence
    }

    func loadContent() async {
        do {
            let content: ArticleContent

            // Check pre-extracted content first
            if let existing = extractedContent {
                Self.logger.debug("Using pre-extracted content (\(existing.textContent.count, privacy: .public) chars)")
                content = existing
            }
            // Check database cache
            else if let persistentArticle, let persistence,
                    let cached = try? persistence.cachedContent(for: persistentArticle) {
                Self.logger.debug("Using cached content for '\(self.article.title, privacy: .public)'")
                content = cached.toArticleContent()
                extractedContent = content
            }
            // Extract fresh
            else {
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
            throw ArticleExtractionError.missingArticleURL
        }
        state = .extracting
        Self.logger.debug("Extracting article: '\(self.article.title, privacy: .public)'")
        let content = try await extractor.extract(from: url, fallbackHTML: article.articleDescription)
        extractedContent = content

        // Cache to database
        if let persistentArticle, let persistence {
            do {
                try persistence.cacheContent(content, for: persistentArticle)
                Self.logger.debug("Cached extracted content for '\(self.article.title, privacy: .public)'")
            } catch {
                Self.logger.warning("Failed to cache content: \(error, privacy: .public)")
            }
        }

        Self.logger.notice("Article extracted (\(content.textContent.count, privacy: .public) chars)")
        return content
    }
}
