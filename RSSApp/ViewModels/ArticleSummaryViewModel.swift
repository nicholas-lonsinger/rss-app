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

    /// `true` while `refreshContent()` is running. The view disables the
    /// Refresh button for the duration to prevent concurrent refresh races.
    private(set) var isRefreshing: Bool = false

    /// Set to `true` when a `refreshContent()` call fails so the banner can
    /// show transient "Refresh failed" feedback. Cleared at the start of the
    /// next `refreshContent()` call so the user can retry without dismissing.
    private(set) var refreshFailed: Bool = false

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
    /// Keeps the stale body visible (no spinner) while extracting in the background,
    /// then replaces it on success. Sets `isRefreshing = true` for the duration so
    /// the view can disable the Refresh button and prevent concurrent calls. Sets
    /// `refreshFailed = true` on failure so the banner can show transient feedback;
    /// that flag is cleared at the start of the next call so the user can retry.
    /// On success the cached `PersistentArticleContent` row is updated in-place by
    /// `cacheContent()`, which also sets `extractedDate = Date()`, making
    /// `PersistentArticle.isContentStale` return `false` on subsequent reads. On
    /// failure the stale content remains visible and the banner stays so the user can
    /// retry.
    func refreshContent() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        refreshFailed = false
        defer { isRefreshing = false }

        do {
            // Pass suppressStateUpdate: true so `extractArticle()` skips the
            // `state = .extracting` transition — the stale body must stay visible
            // during the background re-extraction rather than flashing a spinner.
            let fresh = try await extractArticle(suppressStateUpdate: true)
            extractedContent = fresh
            state = .ready(fresh)
            isContentStale = false
        } catch is CancellationError {
            Self.logger.debug("Content refresh cancelled")
        } catch {
            Self.logger.warning("Content refresh failed for '\(self.article.title, privacy: .public)': \(error, privacy: .public)")
            // The previous .ready(staleContent) state is unchanged — no restore needed
            // because suppressStateUpdate: true prevented any state transition.
            refreshFailed = true
        }
    }

    // MARK: - Private

    /// - Parameter suppressStateUpdate: When `true`, skips the `state = .extracting`
    ///   transition so callers that want to keep the current content visible (e.g.
    ///   `refreshContent()`) do not flash a full-screen spinner mid-read.
    private func extractArticle(suppressStateUpdate: Bool = false) async throws -> ArticleContent {
        guard let url = article.link else {
            throw ArticleExtractionError.missingArticleURL
        }
        if !suppressStateUpdate { state = .extracting }
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
