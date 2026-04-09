import Foundation
import os

// MARK: - Protocol

/// Prefetches article thumbnails in bulk after feed refresh.
@MainActor
protocol ThumbnailPrefetching: Sendable {

    /// Downloads thumbnails for articles that are missing cached thumbnails,
    /// respecting the retry cap.
    ///
    /// The implementation re-checks `networkMonitor.isBackgroundDownloadAllowed()`
    /// between items so that a WiFi-only toggle flipped mid-batch stops further
    /// downloads within the current concurrency window.
    func prefetchThumbnails() async
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
    let outcome: Outcome

    enum Outcome: Sendable {
        /// Thumbnail was successfully downloaded and cached.
        case cached
        /// Download was attempted but failed after retries.
        case failed
        /// Article had no image source; no download was attempted.
        case skipped
        /// Download was cancelled mid-flight via structured concurrency. Not counted
        /// against the retry budget — the article should be retried fresh next cycle.
        case cancelled
    }
}

// MARK: - Implementation

@MainActor
struct ThumbnailPrefetchService: ThumbnailPrefetching {

    private static let logger = Logger(category: "ThumbnailPrefetchService")

    private let persistence: FeedPersisting
    private let thumbnailService: ArticleThumbnailCaching
    private let networkMonitor: NetworkMonitoring

    init(
        persistence: FeedPersisting,
        thumbnailService: ArticleThumbnailCaching = ArticleThumbnailService(),
        networkMonitor: NetworkMonitoring = NetworkMonitorService()
    ) {
        self.persistence = persistence
        self.thumbnailService = thumbnailService
        self.networkMonitor = networkMonitor
    }

    func prefetchThumbnails() async {
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

        // Download thumbnails concurrently, re-checking network allowance between items
        let results = await downloadThumbnails(articleData: articleData, networkMonitor: networkMonitor)

        // Apply results back to persistence on MainActor
        var successCount = 0
        var failureCount = 0
        var skippedCount = 0
        var cancelledCount = 0
        var persistenceFailureCount = 0

        let articlesByID = Dictionary(uniqueKeysWithValues: articles.map { ($0.articleID, $0) })
        for result in results {
            guard let article = articlesByID[result.articleID] else { continue }
            do {
                switch result.outcome {
                case .cached:
                    try persistence.markThumbnailCached(article)
                    successCount += 1
                case .failed:
                    try persistence.incrementThumbnailRetryCount(article)
                    failureCount += 1
                case .skipped:
                    skippedCount += 1
                case .cancelled:
                    // Cancelled work is not counted against retry budget — try again on next refresh cycle.
                    cancelledCount += 1
                }
            } catch {
                persistenceFailureCount += 1
                Self.logger.error("Failed to update thumbnail status for '\(article.title, privacy: .public)': \(error, privacy: .public)")
            }
        }

        do {
            try persistence.save()
        } catch {
            Self.logger.error("Failed to save thumbnail status updates — \(successCount, privacy: .public) cached and \(failureCount, privacy: .public) failed status updates may be lost: \(error, privacy: .public)")
        }

        Self.logger.notice("Thumbnail prefetch complete: \(successCount, privacy: .public) cached, \(failureCount, privacy: .public) failed, \(skippedCount, privacy: .public) skipped, \(cancelledCount, privacy: .public) cancelled, \(persistenceFailureCount, privacy: .public) persistence errors")
    }

    // MARK: - Private

    private func downloadThumbnails(
        articleData: [(articleID: String, thumbnailURL: URL?, articleLink: URL?)],
        networkMonitor: NetworkMonitoring
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

            // Drain results, enqueuing more work as each finishes.
            // Re-check network allowance between items so that toggling WiFi Only
            // on mid-batch stops dispatching new downloads promptly.
            for await result in group {
                collected.append(result)
                guard networkMonitor.isBackgroundDownloadAllowed() else {
                    Self.logger.info("Background downloads no longer allowed mid-prefetch — cancelling remaining items")
                    group.cancelAll()
                    break
                }
                _ = enqueueNext(&group, &iterator)
            }

            // Drain any cancelled tasks so the group closes cleanly
            for await result in group {
                collected.append(result)
            }

            return collected
        }
    }
}

// MARK: - Retry Logic

private let downloadRetryLogger = Logger(category: "ThumbnailPrefetchService")

/// Downloads a single thumbnail with within-cycle retry on transient failure.
/// Permanent failures (4xx, invalid data) skip retries immediately.
/// This is a free function to avoid capturing `@MainActor self` in the `Sendable` task group closure.
private func downloadWithRetry(
    articleID: String,
    thumbnailURL: URL?,
    articleLink: URL?,
    thumbnailService: ArticleThumbnailCaching
) async -> ThumbnailDownloadResult {

    // Skip articles with no possible image source
    guard thumbnailURL != nil || articleLink != nil else {
        return ThumbnailDownloadResult(articleID: articleID, outcome: .skipped)
    }

    for attempt in 0...ThumbnailPrefetchConstants.maxTransientRetries {
        guard !Task.isCancelled else {
            // Cancelled before the attempt started — do not count against retry budget.
            return ThumbnailDownloadResult(articleID: articleID, outcome: .cancelled)
        }

        if attempt > 0 {
            let delay = ThumbnailPrefetchConstants.baseBackoffDelay * pow(2.0, Double(attempt - 1))
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                // CancellationError — stop retrying immediately and do not penalize the retry budget.
                return ThumbnailDownloadResult(articleID: articleID, outcome: .cancelled)
            }
        }

        // RATIONALE: `resolveAndCacheThumbnail` is `throws(CancellationError)`, so the
        // unqualified `catch` below only ever receives a CancellationError and no
        // `catch { assertionFailure(...) }` safety net is needed. A `catch is
        // CancellationError` pattern would be flagged as always-true given the
        // typed-throws signature already guarantees the error type.
        let result: ThumbnailCacheResult
        do {
            result = try await thumbnailService.resolveAndCacheThumbnail(
                thumbnailURL: thumbnailURL,
                articleLink: articleLink,
                articleID: articleID
            )
        } catch {
            // Task was cancelled — stop retrying immediately without incrementing retry counters.
            return ThumbnailDownloadResult(articleID: articleID, outcome: .cancelled)
        }

        switch result {
        case .cached:
            return ThumbnailDownloadResult(articleID: articleID, outcome: .cached)
        case .permanentFailure:
            downloadRetryLogger.info("Permanent failure for article \(articleID, privacy: .public) — skipping retries")
            return ThumbnailDownloadResult(articleID: articleID, outcome: .failed)
        case .transientFailure:
            if attempt < ThumbnailPrefetchConstants.maxTransientRetries {
                downloadRetryLogger.debug("Transient failure on attempt \(attempt + 1, privacy: .public) for article \(articleID, privacy: .public), retrying")
            }
        }
    }

    downloadRetryLogger.info("Thumbnail download failed after \(ThumbnailPrefetchConstants.maxTransientRetries + 1, privacy: .public) attempts for article \(articleID, privacy: .public)")
    return ThumbnailDownloadResult(articleID: articleID, outcome: .failed)
}
