import Foundation
import Observation
import os

@MainActor
@Observable
final class ArticleSummaryViewModel {

    private static let logger = Logger(category: "ArticleSummaryViewModel")

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

    /// `true` when the currently displayed content was extracted before the
    /// publisher's most recent revision (issue #398). The view shows a banner
    /// and lets the user trigger `refreshContent()` to re-extract.
    private(set) var isContentStale: Bool = false

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
            else if let persistentArticle, let persistence {
                let cachedContent: PersistentArticleContent?
                do {
                    cachedContent = try persistence.cachedContent(for: persistentArticle)
                } catch {
                    Self.logger.warning("Failed to load cached content for '\(self.article.title, privacy: .public)': \(error, privacy: .public)")
                    cachedContent = nil
                }

                if let cached = cachedContent {
                    let stale = persistentArticle.isContentStale
                    if stale {
                        Self.logger.notice("Using stale cached content for '\(self.article.title, privacy: .public)' — publisher has a newer revision")
                    } else {
                        Self.logger.debug("Using cached content for '\(self.article.title, privacy: .public)'")
                    }
                    content = cached.toArticleContent()
                    extractedContent = content
                    isContentStale = stale
                } else {
                    content = try await extractArticle()
                }
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

    // MARK: - Stale Content Refresh

    /// User-triggered re-extraction when `isContentStale` is `true` (issue #398).
    ///
    /// Shows the stale body immediately (no spinner) and lets the user opt in to
    /// seeing the fresh version. On success the cached `PersistentArticleContent`
    /// row is updated in-place by `cacheContent()`, which also sets
    /// `extractedDate = Date()`, making `PersistentArticle.isContentStale` return
    /// `false` on subsequent reads. On failure the stale content remains visible
    /// and the banner stays so the user can retry.
    func refreshContent() async {
        // Snapshot the current state so we can restore it if extraction fails.
        // `extractArticle()` sets `state = .extracting` as a side effect; we must
        // not leave the view in `.extracting` if the re-extraction ultimately fails.
        let stateBeforeRefresh = state
        do {
            let fresh = try await extractArticle()
            state = .ready(fresh)
            isContentStale = false
        } catch is CancellationError {
            Self.logger.debug("Content refresh cancelled")
            state = stateBeforeRefresh
        } catch {
            Self.logger.warning("Content refresh failed for '\(self.article.title, privacy: .public)': \(error, privacy: .public)")
            // Restore the previous .ready(staleContent) state so the user continues
            // to see the stale body rather than a loading spinner or error screen.
            state = stateBeforeRefresh
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
