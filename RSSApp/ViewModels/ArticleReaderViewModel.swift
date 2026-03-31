import Foundation
import Observation
import os

@MainActor
@Observable
final class ArticleReaderViewModel {

    private static let logger = Logger(
        subsystem: "com.nicholas-lonsinger.rss-app",
        category: "ArticleReaderViewModel"
    )

    enum State {
        case loading
        case loaded(ArticleContent)
        case failed(String)
    }

    var state: State = .loading

    private let article: Article
    private let extractor: any ArticleExtracting

    init(article: Article, extractor: (any ArticleExtracting)? = nil) {
        self.article = article
        self.extractor = extractor ?? ArticleExtractionService()
    }

    func extractContent() async {
        guard let url = article.link else {
            Self.logger.warning("Article has no link, cannot extract content")
            state = .failed("This article has no URL.")
            return
        }

        let title = article.title
        let description = article.articleDescription
        Self.logger.debug("extractContent() starting for '\(title, privacy: .public)'")
        state = .loading

        do {
            let content = try await extractor.extract(from: url, fallbackHTML: description)
            state = .loaded(content)
            Self.logger.notice("Content extracted for '\(title, privacy: .public)'")
        } catch {
            Self.logger.error("Extraction failed for '\(title, privacy: .public)': \(error, privacy: .public)")
            state = .failed(error.localizedDescription)
        }
    }
}
