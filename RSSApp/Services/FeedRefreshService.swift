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

    /// UserDefaults key under which the wall-clock timestamp of the most
    /// recent *completed* refresh cycle is written. Shared across foreground
    /// and background callers (both paths go through `refreshAllFeeds()`),
    /// which allows `HomeViewModel.shouldRefreshOnEntry` to throttle list-
    /// entry refreshes even when the previous refresh came from a `BGTask`.
    static let lastRefreshCompletedKey = "feedRefresh.lastCompletedAt"

    /// Wall-clock timestamp of the most recent `.completed` refresh outcome,
    /// across any caller in the process. `nil` when no refresh has ever
    /// completed on this install. Read by `HomeViewModel.shouldRefreshOnEntry`
    /// to decide whether a cross-feed list entry should trigger a fresh
    /// network refresh or rely on the most recent cached snapshot.
    static var lastRefreshCompletedAt: Date? {
        let ts = UserDefaults.standard.double(forKey: lastRefreshCompletedKey)
        return ts > 0 ? Date(timeIntervalSince1970: ts) : nil
    }

    // MARK: - Dependencies

    private let persistence: FeedPersisting
    private let feedFetching: FeedFetching
    private let feedIconService: FeedIconResolving
    private let thumbnailPrefetcher: ThumbnailPrefetching
    private let articleRetention: ArticleRetaining
    private let thumbnailService: ArticleThumbnailCaching
    private let networkMonitor: NetworkMonitoring

    /// Background thumbnail prefetch task kicked off at the end of a refresh.
    /// Retained so `awaitPendingWork()` can drain it on behalf of a background
    /// task handler before it calls `setTaskCompleted(success:)`.
    private var thumbnailPrefetchTask: Task<Void, Never>?

    /// Fire-and-forget icon resolution tasks spawned during a refresh cycle.
    /// Retained so `awaitPendingWork()` can drain them for the same reason
    /// as `thumbnailPrefetchTask` — the allotted BG runtime should be used
    /// rather than cancelled mid-flight when the OS reclaims the process.
    private var pendingIconTasks: [Task<Void, Never>] = []

    init(
        persistence: FeedPersisting,
        feedFetching: FeedFetching = FeedFetchingService(),
        // No default for `feedIconService`: callers must pass the shared
        // instance from `RSSAppApp.init()` explicitly. Today
        // `FeedIconService` is a stateless struct whose only field is an
        // optional cache-directory override, so two default-constructed
        // instances would not actually diverge — the invariant is
        // forward-looking. Requiring an explicit instance keeps call
        // sites disciplined for when the service later gains instance-
        // level state (URLCache, in-memory LRU, URLSession auth
        // delegate), at which point the refresh writes and the UI reads
        // would silently drift if each side constructed its own copy.
        feedIconService: FeedIconResolving,
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

        /// Refresh could not begin because the feed list could not be loaded
        /// from persistence. Distinct from `.completed(... saveDidFail: true)`,
        /// which reports a save failure *after* a refresh cycle ran.
        case setupFailed

        /// Refresh was cancelled mid-cycle (typically because a `BGTask`
        /// expiration handler fired, propagating cancellation into the task
        /// group). `totalFeeds` is the number of feeds the cycle was
        /// attempting when cancellation was observed.
        case cancelled(totalFeeds: Int)

        /// Refresh completed; possibly with per-feed failures. All invariants
        /// on the associated values are enforced by `Summary`'s init.
        case completed(Summary)

        /// The post-completion summary of a successful refresh cycle.
        /// `Summary`'s init enforces `totalFeeds > 0` and
        /// `0 ≤ failureCount ≤ totalFeeds`, so pattern-matching callers do
        /// not need to defend against degenerate combinations.
        struct Summary: Sendable, Equatable {
            let totalFeeds: Int
            let failureCount: Int
            let saveDidFail: Bool
            let retentionCleanupFailed: Bool

            // RATIONALE: `precondition` (not `assertionFailure`) is the right
            // defensive tool here. CLAUDE.md's `assertionFailure` + fallback
            // pattern targets I/O-boundary defensive unwrapping (system APIs
            // returning an unexpected nil), where degraded operation is
            // preferable to a crash. Structural invariants on a value-type
            // constructor are a different case: there is no meaningful
            // fallback (what would a clamped `failureCount` even mean to the
            // caller?), and the invariants are guaranteed by the single
            // construction site in `performRefresh`. A precondition failure
            // here would indicate a genuine counting bug that surfaces
            // immediately rather than silently propagating a malformed
            // outcome through the system.
            init(
                totalFeeds: Int,
                failureCount: Int,
                saveDidFail: Bool,
                retentionCleanupFailed: Bool
            ) {
                precondition(
                    totalFeeds > 0,
                    "FeedRefreshService.Outcome.Summary requires totalFeeds > 0; use .skipped or .setupFailed for zero-feed paths"
                )
                precondition(
                    (0...totalFeeds).contains(failureCount),
                    "FeedRefreshService.Outcome.Summary requires 0 ≤ failureCount (\(failureCount)) ≤ totalFeeds (\(totalFeeds))"
                )
                self.totalFeeds = totalFeeds
                self.failureCount = failureCount
                self.saveDidFail = saveDidFail
                self.retentionCleanupFailed = retentionCleanupFailed
            }
        }
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
            return .setupFailed
        }

        guard !feeds.isEmpty else {
            Self.logger.debug("refreshAllFeeds() skipped — no feeds")
            return .skipped
        }

        isRefreshing = true
        defer { isRefreshing = false }

        let outcome = await performRefresh(feeds: feeds)
        // Record the completion timestamp on any `.completed` outcome,
        // including cosmetic save / retention failures — the fetch loop still
        // ran, the store is at least partially updated, and an immediate retry
        // would burn cycles without new information. `.skipped`, `.setupFailed`,
        // and `.cancelled` intentionally leave the timestamp alone so the
        // throttle doesn't swallow those paths on the next entry.
        if case .completed = outcome {
            UserDefaults.standard.set(
                Date().timeIntervalSince1970,
                forKey: Self.lastRefreshCompletedKey
            )
        }
        return outcome
    }

    /// Blocks until the in-flight thumbnail prefetch task and all pending
    /// icon resolution tasks from the current refresh cycle have drained.
    /// Background task handlers call this before invoking
    /// `setTaskCompleted(success:)` so the allotted background runtime is
    /// used for thumbnail + icon work that would otherwise be cancelled when
    /// the OS reclaims the process.
    ///
    /// Precondition: call this immediately after `refreshAllFeeds()` returns,
    /// as two consecutive `await` statements on the same main-actor task:
    ///
    ///     let outcome = await service.refreshAllFeeds()
    ///     await service.awaitPendingWork()
    ///
    /// The snapshot of task handles below runs synchronously at entry (before
    /// any suspension point), so a concurrent `refreshAllFeeds()` cycle that
    /// starts during one of the drain's `await` yields cannot mutate the
    /// captured handles — the drain loop always walks this caller's own
    /// cycle's task handles. A concurrent cycle's end-of-`performRefresh`
    /// cleanup can still call `cancel()` on `thumbnailPrefetchTask` (the
    /// stored reference, which this caller also holds locally), in which
    /// case `await task.value` returns early on the cancelled task; the
    /// drain still releases and the OS-allotted runtime is still used,
    /// just for whatever work completed before the cancel.
    func awaitPendingWork() async {
        // Snapshot both task references synchronously, before any `await`,
        // so a concurrent `refreshAllFeeds()` cycle cannot replace the
        // stored handles mid-drain. Clearing `pendingIconTasks` here (not
        // merely snapshotting) is load-bearing: it prevents the next
        // cycle's `performRefresh` start-of-cycle cleanup (which calls
        // `cancel()` on every entry in `pendingIconTasks`) from cancelling
        // the icon tasks this caller is about to await.
        let prefetchTask = thumbnailPrefetchTask
        let iconTasks = pendingIconTasks
        pendingIconTasks.removeAll()

        await prefetchTask?.value
        for task in iconTasks {
            _ = await task.value
        }
    }

    // MARK: - Refresh Loop

    private func performRefresh(feeds: [PersistentFeed]) async -> Outcome {
        // Cancel any icon tasks still in flight from a previous cycle so they
        // cannot contend with this cycle's writes or outlive it unnecessarily.
        // Mirrors the `thumbnailPrefetchTask?.cancel()` pattern below.
        for task in pendingIconTasks { task.cancel() }
        pendingIconTasks.removeAll()

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
        } catch is CancellationError {
            Self.logger.warning("performRefresh() cancelled — reporting .cancelled outcome")
            return .cancelled(totalFeeds: feeds.count)
        } catch {
            // RATIONALE: The enqueue closures explicitly convert non-CancellationError
            // fetch errors to `.failure` results, so the task group should only ever
            // rethrow CancellationError. A non-cancellation throw here indicates a
            // programming bug in the enqueue closure — fault-log and fall through to
            // `.cancelled` to avoid a misleading .completed outcome.
            Self.logger.fault("performRefresh() task group threw unexpected non-cancellation error: \(error, privacy: .public)")
            assertionFailure("performRefresh() task group threw unexpected error: \(error)")
            return .cancelled(totalFeeds: feeds.count)
        }

        // The expirationHandler-triggered cancel path may flip Task.isCancelled
        // while this loop is running. Bail before starting persistence writes so
        // the ModelContext does not get left mid-save when the OS reclaims the
        // process. Checked at each loop boundary so partial progress is not
        // silently reported as completion.
        if Task.isCancelled {
            Self.logger.warning("performRefresh() cancelled before result processing")
            return .cancelled(totalFeeds: feeds.count)
        }

        let idToFeed = Dictionary(uniqueKeysWithValues: feeds.map { ($0.id, $0) })
        var failureCount = 0
        for (id, result) in results {
            if Task.isCancelled {
                Self.logger.warning("performRefresh() cancelled mid-results at feed \(id, privacy: .public)")
                return .cancelled(totalFeeds: feeds.count)
            }
            guard let feed = idToFeed[id] else {
                Self.logger.warning("Skipping refresh result for feed ID \(id, privacy: .public) — feed no longer in list")
                continue
            }
            switch result {
            case .success(let fetchResult):
                guard let fetchResult else {
                    // 304 Not Modified — clear error state (cosmetic on failure,
                    // matching the 200 path below) and resolve icon if needed.
                    do {
                        try persistence.updateFeedError(feed, error: nil)
                    } catch {
                        // Cosmetic — does not increment failureCount. Matches
                        // the 200-path treatment at "Always clear error state
                        // on successful fetch" below. Both paths describe the
                        // same failure mode (cannot clear a stale error flag)
                        // with the same self-healing consequence.
                        Self.logger.warning("Failed to clear error state for '\(feed.title, privacy: .public)' on 304: \(error, privacy: .public) — feed may show stale error indicator until next successful clear")
                    }
                    if isDownloadAllowed {
                        let iconTask = Task {
                            await self.resolveAndCacheIconIfNeeded(
                                for: feed,
                                siteURL: feed.feedURL.siteRoot,
                                feedImageURL: feed.iconURL
                            )
                        }
                        pendingIconTasks.append(iconTask)
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

                // failureCount is incremented in exactly two places in this
                // function: (1) upsertArticles failure below — the one
                // data-losing operation; (2) the explicit .failure arm for
                // fetch failures. Cosmetic persistence failures (metadata,
                // error-clear, cache headers) are logged at .warning and
                // NOT counted — they self-heal on the next refresh and do
                // not warrant iOS backing off the BG schedule.
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
                    let iconTask = Task {
                        await self.resolveAndCacheIconIfNeeded(
                            for: feed,
                            siteURL: fetchResult.feed.link,
                            feedImageURL: fetchResult.feed.imageURL
                        )
                    }
                    pendingIconTasks.append(iconTask)
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

        if Task.isCancelled {
            Self.logger.warning("performRefresh() cancelled before save")
            return .cancelled(totalFeeds: feeds.count)
        }

        var saveDidFail = false
        do {
            try persistence.save()
        } catch {
            saveDidFail = true
            Self.logger.error("Failed to save after refresh: \(error, privacy: .public)")
        }

        if Task.isCancelled {
            Self.logger.warning("performRefresh() cancelled before retention cleanup")
            return .cancelled(totalFeeds: feeds.count)
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

        // Cancel any in-flight prefetch from a previous refresh cycle before
        // starting a new one. Safe because the `isRefreshing` guard coalesces
        // concurrent `refreshAllFeeds()` calls, so this cancel only runs once
        // the previous cycle has fully completed its result processing.
        thumbnailPrefetchTask?.cancel()
        if isDownloadAllowed {
            thumbnailPrefetchTask = Task(priority: .utility) {
                await self.thumbnailPrefetcher.prefetchThumbnails()
            }
        } else {
            Self.logger.info("Skipping thumbnail prefetch — background downloads not allowed on current network")
        }

        return .completed(
            Outcome.Summary(
                totalFeeds: feeds.count,
                failureCount: failureCount,
                saveDidFail: saveDidFail,
                retentionCleanupFailed: retentionCleanupFailed
            )
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
