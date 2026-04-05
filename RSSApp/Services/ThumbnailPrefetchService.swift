import Foundation
import os

// MARK: - Protocol

/// Prefetches article thumbnails in bulk after feed refresh.
@MainActor
protocol ThumbnailPrefetching: Sendable {

    /// Downloads thumbnails for articles that are missing cached thumbnails,
    /// respecting the retry cap. Runs at background priority so feed refreshing
    /// is not blocked.
    func prefetchThumbnails(persistence: FeedPersisting) async
}

// MARK: - Constants

/// Shared constants for thumbnail prefetch configuration.
/// Extracted to a nonisolated enum so both the `@MainActor` service and
/// the nonisolated free function can access them without actor-isolation conflicts.
enum ThumbnailPrefetchConstants {

    /// Maximum number of cross-cycle retries before permanently giving up on an article's thumbnail.
    static let maxRetryCount = 3

    /// Maximum number of concurrent thumbnail downloads.
    static let maxConcurrency = 4

    /// Maximum number of within-cycle retries for transient failures.
    static let maxTransientRetries = 2

    /// Base delay for exponential backoff on transient retries (seconds).
    static let baseBackoffDelay: TimeInterval = 1.0
}

// MARK: - Result Type

/// Outcome of a single thumbnail download attempt.
private struct ThumbnailDownloadResult: Sendable {
    let articleID: String
    let success: Bool
}

// MARK: - Implementation

@MainActor
struct ThumbnailPrefetchService: ThumbnailPrefetching {

    private static let logger = Logger(category: "ThumbnailPrefetchService")

    private let thumbnailService: ArticleThumbnailCaching

    init(thumbnailService: ArticleThumbnailCaching = ArticleThumbnailService()) {
        self.thumbnailService = thumbnailService
    }

    func prefetchThumbnails(persistence: FeedPersisting) async {
        Self.logger.debug("prefetchThumbnails() called")

        let articles: [PersistentArticle]
        do {
            articles = try persistence.articlesNeedingThumbnails(
                maxRetryCount: ThumbnailPrefetchConstants.maxRetryCount
            )
        } catch {
            Self.logger.error("Failed to query articles needing thumbnails: \(error, privacy: .public)")
            return
        }

        guard !articles.isEmpty else {
            Self.logger.debug("No articles need thumbnail downloads")
            return
        }

        Self.logger.info("Starting thumbnail prefetch for \(articles.count, privacy: .public) articles")

        // Collect article data on MainActor before entering the task group
        let articleData: [(articleID: String, thumbnailURL: URL?, articleLink: URL?)] = articles.map {
            ($0.articleID, $0.thumbnailURL, $0.link)
        }

        // Download thumbnails concurrently
        let results = await downloadThumbnails(articleData: articleData)

        // Apply results back to persistence on MainActor
        var successCount = 0
        var failureCount = 0

        let articlesByID = Dictionary(uniqueKeysWithValues: articles.map { ($0.articleID, $0) })
        for result in results {
            guard let article = articlesByID[result.articleID] else { continue }
            do {
                if result.success {
                    try persistence.markThumbnailCached(article)
                    successCount += 1
                } else {
                    try persistence.incrementThumbnailRetryCount(article)
                    failureCount += 1
                }
            } catch {
                Self.logger.error("Failed to update thumbnail status for '\(article.title, privacy: .public)': \(error, privacy: .public)")
            }
        }

        do {
            try persistence.save()
        } catch {
            Self.logger.error("Failed to save thumbnail status updates: \(error, privacy: .public)")
        }

        Self.logger.notice("Thumbnail prefetch complete: \(successCount, privacy: .public) cached, \(failureCount, privacy: .public) failed")
    }

    // MARK: - Private

    private func downloadThumbnails(
        articleData: [(articleID: String, thumbnailURL: URL?, articleLink: URL?)]
    ) async -> [ThumbnailDownloadResult] {
        let thumbnailService = self.thumbnailService

        return await withTaskGroup(of: ThumbnailDownloadResult.self, returning: [ThumbnailDownloadResult].self) { group in
            var collected: [ThumbnailDownloadResult] = []
            var iterator = articleData.makeIterator()

            func enqueueNext(_ group: inout TaskGroup<ThumbnailDownloadResult>, _ iterator: inout IndexingIterator<[(articleID: String, thumbnailURL: URL?, articleLink: URL?)]>) -> Bool {
                guard let item = iterator.next() else { return false }
                group.addTask {
                    await downloadWithRetry(
                        articleID: item.articleID,
                        thumbnailURL: item.thumbnailURL,
                        articleLink: item.articleLink,
                        thumbnailService: thumbnailService
                    )
                }
                return true
            }

            // Seed with initial batch
            for _ in 0..<ThumbnailPrefetchConstants.maxConcurrency {
                guard enqueueNext(&group, &iterator) else { break }
            }

            // Drain results, enqueuing more work as each finishes
            for await result in group {
                collected.append(result)
                _ = enqueueNext(&group, &iterator)
            }

            return collected
        }
    }
}

// MARK: - Retry Logic

/// Downloads a single thumbnail with retry for transient failures.
/// This is a free function to avoid capturing `@MainActor self` in the `Sendable` task group closure.
private func downloadWithRetry(
    articleID: String,
    thumbnailURL: URL?,
    articleLink: URL?,
    thumbnailService: ArticleThumbnailCaching
) async -> ThumbnailDownloadResult {
    let logger = Logger(category: "ThumbnailPrefetchService")

    // Skip articles with no possible image source
    guard thumbnailURL != nil || articleLink != nil else {
        return ThumbnailDownloadResult(articleID: articleID, success: false)
    }

    for attempt in 0...ThumbnailPrefetchConstants.maxTransientRetries {
        if attempt > 0 {
            let delay = ThumbnailPrefetchConstants.baseBackoffDelay * pow(2.0, Double(attempt - 1))
            try? await Task.sleep(for: .seconds(delay))
        }

        let cached = await thumbnailService.resolveAndCacheThumbnail(
            thumbnailURL: thumbnailURL,
            articleLink: articleLink,
            articleID: articleID
        )

        if cached {
            return ThumbnailDownloadResult(articleID: articleID, success: true)
        }

        if attempt < ThumbnailPrefetchConstants.maxTransientRetries {
            logger.debug("Thumbnail download attempt \(attempt + 1, privacy: .public) failed for article \(articleID, privacy: .public), retrying")
        }
    }

    logger.info("Thumbnail download failed after \(ThumbnailPrefetchConstants.maxTransientRetries + 1, privacy: .public) attempts for article \(articleID, privacy: .public)")
    return ThumbnailDownloadResult(articleID: articleID, success: false)
}
