import Foundation
import os

/// Owns the "refresh all feeds" work that was previously the body of
/// `FeedListViewModel.refreshAllFeeds()`. Shared across the foreground view
/// models and the background task coordinator so `isRefreshing` is a single
/// process-wide source of truth — guarantees the foreground pull-to-refresh
/// and a concurrent `BGTask` launch never run the upsert loop twice against
/// the same `ModelContext`.
@MainActor
@Observable
final class FeedRefreshService {

    private static let logger = Logger(category: "FeedRefreshService")

    /// Whether a refresh cycle is currently executing. Shared across callers.
    private(set) var isRefreshing = false

    // MARK: - Dependencies

    private let persistence: FeedPersisting
    private let feedFetching: FeedFetching
    let feedIconService: FeedIconResolving
    private let thumbnailPrefetcher: ThumbnailPrefetching
    private let articleRetention: ArticleRetaining
    private let thumbnailService: ArticleThumbnailCaching
    private let networkMonitor: NetworkMonitoring

    /// Background thumbnail prefetch task kicked off at the end of a refresh.
    /// Retained so `awaitPendingWork()` can drain it on behalf of a background
    /// task handler before it calls `setTaskCompleted(success:)`.
    private var thumbnailPrefetchTask: Task<Void, Never>?

    init(
        persistence: FeedPersisting,
        feedFetching: FeedFetching = FeedFetchingService(),
        feedIconService: FeedIconResolving = FeedIconService(),
        // RATIONALE: Default cannot reference the `persistence` parameter in a default-value
        // expression, so nil-coalescing is used to construct the default inside the body.
        thumbnailPrefetcher: ThumbnailPrefetching? = nil,
        articleRetention: ArticleRetaining = ArticleRetentionService(),
        thumbnailService: ArticleThumbnailCaching = ArticleThumbnailService(),
        networkMonitor: NetworkMonitoring? = nil
    ) {
        self.persistence = persistence
        self.feedFetching = feedFetching
        self.feedIconService = feedIconService
        self.thumbnailPrefetcher = thumbnailPrefetcher ?? ThumbnailPrefetchService(persistence: persistence)
        self.articleRetention = articleRetention
        self.thumbnailService = thumbnailService
        self.networkMonitor = networkMonitor ?? NetworkMonitorService()
    }

    // MARK: - Outcome

    /// Summary of a refresh attempt. Callers translate this into UI state.
    enum Outcome: Sendable, Equatable {
        /// No refresh was performed — either another caller already had a
        /// refresh in flight, or there are no feeds to refresh.
        case skipped

        /// Refresh completed; possibly with per-feed failures.
        case completed(
            totalFeeds: Int,
            failureCount: Int,
            saveDidFail: Bool,
            retentionCleanupFailed: Bool
        )
    }

    // MARK: - Public API

    /// Runs a refresh cycle. If another refresh is already in progress — from
    /// the foreground pull-to-refresh, a previous call on the same caller, or
    /// a `BGTask` launch — returns `.skipped` immediately so the two never run
    /// concurrently against the same `ModelContext`.
    @discardableResult
    func refreshAllFeeds() async -> Outcome {
        Self.logger.debug("refreshAllFeeds() called")
        guard !isRefreshing else {
            Self.logger.debug("refreshAllFeeds() skipped — another refresh already in progress")
            return .skipped
        }

        // Load the feed list fresh from persistence on every call. Foreground
        // and background callers must see the same canonical set, and the
        // previous design (reading a stale viewmodel snapshot) could drop a
        // just-added feed from the refresh loop.
        let feeds: [PersistentFeed]
        do {
            feeds = try persistence.allFeeds()
        } catch {
            Self.logger.error("Failed to load feeds for refresh: \(error, privacy: .public)")
            return .completed(totalFeeds: 0, failureCount: 0, saveDidFail: true, retentionCleanupFailed: false)
        }

        guard !feeds.isEmpty else {
            Self.logger.debug("refreshAllFeeds() skipped — no feeds")
            return .skipped
        }

        isRefreshing = true
        defer { isRefreshing = false }

        return await performRefresh(feeds: feeds)
    }

    /// Blocks until any in-flight thumbnail prefetch task has drained.
    /// Background task handlers call this before invoking
    /// `setTaskCompleted(success:)` so the allotted background runtime is
    /// used for thumbnail downloads that would otherwise be cancelled when
    /// the OS reclaims the process.
    func awaitPendingWork() async {
        await thumbnailPrefetchTask?.value
    }

    // MARK: - Refresh Loop

    private func performRefresh(feeds: [PersistentFeed]) async -> Outcome {
        let feedFetching = self.feedFetching
        let logger = Self.logger
        let maxConcurrency = 6
        let isDownloadAllowed = networkMonitor.isBackgroundDownloadAllowed()

        let results: [(UUID, Result<FeedFetchResult?, any Error>)]
        do {
            results = try await withThrowingTaskGroup(
                of: (UUID, Result<FeedFetchResult?, any Error>).self,
                returning: [(UUID, Result<FeedFetchResult?, any Error>)].self
            ) { group in
                var collected: [(UUID, Result<FeedFetchResult?, any Error>)] = []
                var iterator = feeds.makeIterator()

                func enqueueNext(_ group: inout ThrowingTaskGroup<(UUID, Result<FeedFetchResult?, any Error>), any Error>, _ iterator: inout IndexingIterator<[PersistentFeed]>) -> Bool {
                    guard let feed = iterator.next() else { return false }
                    let feedID = feed.id
                    let feedURL = feed.feedURL
                    let feedTitle = feed.title
                    let feedEtag = feed.etag
                    let feedLastModified = feed.lastModifiedHeader
                    group.addTask {
                        do {
                            let result = try await feedFetching.fetchFeed(from: feedURL, etag: feedEtag, lastModified: feedLastModified)
                            return (feedID, .success(result))
                        } catch is CancellationError {
                            throw CancellationError()
                        } catch {
                            logger.warning("Failed to refresh '\(feedTitle, privacy: .public)' (\(feedURL.absoluteString, privacy: .public)): \(error, privacy: .public)")
                            return (feedID, .failure(error))
                        }
                    }
                    return true
                }

                for _ in 0..<maxConcurrency {
                    guard enqueueNext(&group, &iterator) else { break }
                }

                for try await result in group {
                    collected.append(result)
                    _ = enqueueNext(&group, &iterator)
                }

                return collected
            }
        } catch {
            Self.logger.debug("performRefresh() cancelled")
            return .completed(
                totalFeeds: feeds.count,
                failureCount: 0,
                saveDidFail: false,
                retentionCleanupFailed: false
            )
        }

        let idToFeed = Dictionary(uniqueKeysWithValues: feeds.map { ($0.id, $0) })
        var failureCount = 0
        for (id, result) in results {
            guard let feed = idToFeed[id] else {
                Self.logger.warning("Skipping refresh result for feed ID \(id, privacy: .public) — feed no longer in list")
                continue
            }
            switch result {
            case .success(let fetchResult):
                guard let fetchResult else {
                    // 304 Not Modified — clear error state and resolve icon if needed
                    do {
                        try persistence.updateFeedError(feed, error: nil)
                    } catch {
                        failureCount += 1
                        Self.logger.error("Failed to clear error state for '\(feed.title, privacy: .public)': \(error, privacy: .public) — feed will appear to have an error on next launch despite successful 304 response")
                    }
                    if isDownloadAllowed {
                        Task {
                            await self.resolveAndCacheIconIfNeeded(
                                for: feed,
                                siteURL: Self.siteURL(from: feed.feedURL),
                                feedImageURL: feed.iconURL
                            )
                        }
                    } else {
                        Self.logger.debug("Skipping icon resolution for '\(feed.title, privacy: .public)' on 304 — background downloads not allowed")
                    }
                    continue
                }
                // Each persistence operation has its own catch block so a failure
                // in one does not prevent the others from running. In particular,
                // cache headers must only be written when upsertArticles succeeds —
                // leaving stale headers ensures the next refresh re-fetches the
                // articles rather than receiving a 304 Not Modified for data that
                // was never persisted.
                do {
                    try persistence.updateFeedMetadata(feed, title: fetchResult.feed.title, description: fetchResult.feed.feedDescription)
                } catch {
                    // Cosmetic — does not increment failureCount. Title/description
                    // remain stale but articles and cache headers still proceed.
                    Self.logger.warning("Failed to update metadata for '\(feed.title, privacy: .public)': \(error, privacy: .public) — title/description may be stale")
                }

                // Always clear error state on successful fetch, regardless of
                // whether the metadata update above succeeded. updateFeedMetadata
                // clears lastFetchError as a side effect, but if it threw, the
                // feed would retain a stale error indicator despite a good fetch.
                do {
                    try persistence.updateFeedError(feed, error: nil)
                } catch {
                    Self.logger.warning("Failed to clear error state for '\(feed.title, privacy: .public)': \(error, privacy: .public) — feed may show stale error indicator")
                }

                // Only upsert failure increments failureCount — it is the one
                // operation that loses user-visible data (new articles). Metadata
                // and cache header failures are cosmetic or self-healing.
                var upsertSucceeded = false
                do {
                    try persistence.upsertArticles(fetchResult.feed.articles, for: feed)
                    upsertSucceeded = true
                } catch {
                    failureCount += 1
                    Self.logger.error("Failed to upsert articles for '\(feed.title, privacy: .public)': \(error, privacy: .public)")
                }

                if upsertSucceeded {
                    do {
                        try persistence.updateFeedCacheHeaders(feed, etag: fetchResult.etag, lastModified: fetchResult.lastModified)
                    } catch {
                        // Cosmetic — does not increment failureCount. The feed
                        // will re-fetch unchanged content on the next refresh,
                        // which is wasteful but not data-losing.
                        Self.logger.warning("Failed to update cache headers for '\(feed.title, privacy: .public)': \(error, privacy: .public) — feed may re-fetch unchanged content on next refresh")
                    }
                }

                if isDownloadAllowed {
                    Task {
                        await self.resolveAndCacheIconIfNeeded(
                            for: feed,
                            siteURL: fetchResult.feed.link,
                            feedImageURL: fetchResult.feed.imageURL
                        )
                    }
                } else {
                    Self.logger.debug("Skipping icon resolution for '\(feed.title, privacy: .public)' — background downloads not allowed")
                }
            case .failure(let fetchError):
                failureCount += 1
                do {
                    try persistence.updateFeedError(feed, error: Self.errorDescription(for: fetchError))
                } catch {
                    Self.logger.error("Failed to persist error state for '\(feed.title, privacy: .public)': \(error, privacy: .public) — feed will appear healthy on next launch despite fetch failure")
                }
            }
        }

        var saveDidFail = false
        do {
            try persistence.save()
        } catch {
            saveDidFail = true
            Self.logger.error("Failed to save after refresh: \(error, privacy: .public)")
        }

        // Enforce article retention limit after save so the count reflects the
        // final database state, including newly upserted rows.
        var retentionCleanupFailed = false
        do {
            try articleRetention.enforceArticleLimit(
                persistence: persistence,
                thumbnailService: thumbnailService
            )
        } catch {
            retentionCleanupFailed = true
            Self.logger.error("Article retention cleanup failed: \(error, privacy: .public)")
        }

        Self.logger.notice("Refresh complete: \(feeds.count - failureCount, privacy: .public) updated, \(failureCount, privacy: .public) failed")

        // Cancel any in-flight prefetch from a previous refresh cycle before starting a new one
        thumbnailPrefetchTask?.cancel()
        if isDownloadAllowed {
            thumbnailPrefetchTask = Task(priority: .utility) {
                await self.thumbnailPrefetcher.prefetchThumbnails()
            }
        } else {
            Self.logger.info("Skipping thumbnail prefetch — background downloads not allowed on current network")
        }

        return .completed(
            totalFeeds: feeds.count,
            failureCount: failureCount,
            saveDidFail: saveDidFail,
            retentionCleanupFailed: retentionCleanupFailed
        )
    }

    /// Resolves and caches a feed icon if one is not already cached on disk.
    private func resolveAndCacheIconIfNeeded(
        for feed: PersistentFeed,
        siteURL: URL?,
        feedImageURL: URL?
    ) async {
        guard feedIconService.cachedIconFileURL(for: feed.id) == nil else {
            Self.logger.debug("Icon already cached for '\(feed.title, privacy: .public)'")
            return
        }
        guard let iconURL = await feedIconService.resolveAndCacheIcon(
            feedSiteURL: siteURL,
            feedImageURL: feedImageURL,
            feedID: feed.id
        ) else { return }
        do {
            try persistence.updateFeedIcon(feed, iconURL: iconURL)
        } catch {
            // RATIONALE: No error surfaced here. This runs inside a fire-and-forget Task
            // spawned by performRefresh(), so mutating the caller's errorMessage would race
            // with the post-refresh error state assignment. Icon persistence failure is also
            // cosmetic and self-healing — the icon is re-resolved on the next refresh.
            Self.logger.error("Failed to persist icon URL for '\(feed.title, privacy: .public)': \(error, privacy: .public)")
        }
    }

    /// Derives a site root URL from a feed URL (e.g., https://example.com/feed → https://example.com).
    /// Returns nil if the feed URL has no host.
    private static func siteURL(from feedURL: URL) -> URL? {
        guard let host = feedURL.host(percentEncoded: false), !host.isEmpty else { return nil }
        return URL(string: "\(feedURL.scheme ?? "https")://\(host)")
    }

    private static func errorDescription(for error: any Error) -> String {
        switch error {
        case let fetchError as FeedFetchingError:
            switch fetchError {
            case .invalidResponse(let statusCode):
                return "HTTP \(statusCode)"
            case .invalidFeedURL:
                return "Invalid feed URL"
            }
        case is URLError:
            return "Network error"
        default:
            return "Fetch failed"
        }
    }
}
