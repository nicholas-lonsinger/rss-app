import Foundation
import Observation
import FoundationModels
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
        case generating
        case ready(String)
        case unavailable
        case failed(String)
    }

    var state: State = .idle
    var options: SummaryOptions = SummaryOptions()

    /// Set once extraction completes; used by the discussion sheet.
    private(set) var extractedContent: ArticleContent?

    private let article: Article
    private let extractor: any ArticleExtracting
    private static let maxArticleChars = 12_000

    init(article: Article, preExtractedContent: ArticleContent? = nil, extractor: (any ArticleExtracting)? = nil) {
        self.article = article
        self.extractedContent = preExtractedContent
        self.extractor = extractor ?? ArticleExtractionService()
    }

    func generate() async {
        do {
            let content: ArticleContent
            if let existing = extractedContent {
                content = existing
            } else {
                content = try await extractArticle()
            }
            try await summarize(content: content)
        } catch is CancellationError {
            Self.logger.debug("Summary generation cancelled")
        } catch {
            Self.logger.error("Summary generation failed: \(error, privacy: .public)")
            state = .failed(error.localizedDescription)
        }
    }

    // MARK: - Private

    private func extractArticle() async throws -> ArticleContent {
        guard let url = article.link else {
            throw ArticleExtractionError.readabilityNotFound
        }
        state = .extracting
        Self.logger.debug("Extracting article for summary: '\(self.article.title, privacy: .public)'")
        let content = try await extractor.extract(from: url, fallbackHTML: article.articleDescription)
        extractedContent = content
        Self.logger.notice("Article extracted for summary (\(content.textContent.count, privacy: .public) chars)")
        return content
    }

    private func summarize(content: ArticleContent) async throws {
        guard SystemLanguageModel.default.availability == .available else {
            Self.logger.warning("Foundation Models unavailable on this device")
            state = .unavailable
            return
        }

        state = .generating
        Self.logger.debug("generate() — length=\(self.options.length.rawValue, privacy: .public) format=\(self.options.format.rawValue, privacy: .public)")

        let session = LanguageModelSession(instructions: systemInstructions())
        let genOptions = GenerationOptions(
            temperature: 0.3,
            maximumResponseTokens: options.length.maxTokens
        )
        for try await snapshot in session.streamResponse(to: summaryPrompt(for: content), options: genOptions) {
            state = .ready(snapshot.content)
        }
        if case .ready(let text) = state {
            Self.logger.notice("Summary complete (\(text.count, privacy: .public) chars)")
        }
    }

    private func truncated(_ text: String) -> String {
        guard text.count > Self.maxArticleChars else { return text }
        return String(text.prefix(Self.maxArticleChars))
    }

    private func summaryPrompt(for content: ArticleContent) -> String {
        """
        Summarize the following article \(options.format.promptInstruction) in \(options.length.promptInstruction). \
        Output only the summary — no preamble, no title, no explanation.

        Article title: \(content.title)

        \(truncated(content.textContent))
        """
    }

    private func systemInstructions() -> String {
        "You are a precise reading assistant. Summarize articles accurately and concisely. Output only the requested summary."
    }
}
