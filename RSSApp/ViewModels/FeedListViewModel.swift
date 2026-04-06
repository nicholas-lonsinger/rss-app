import Foundation
import os

@MainActor
@Observable
final class FeedListViewModel {

    private static let logger = Logger(category: "FeedListViewModel")

    private(set) var feeds: [PersistentFeed] = []
    private var unreadCounts: [UUID: Int] = [:]
    private(set) var isRefreshing = false
    var errorMessage: String?
    var importExportErrorMessage: String?
    var opmlImportResult: OPMLImportResult?
    var opmlExportURL: URL?

    private let persistence: FeedPersisting
    private let opmlService: OPMLServing
    private let feedFetching: FeedFetching
    let feedIconService: FeedIconResolving
    private let thumbnailPrefetcher: ThumbnailPrefetching
    private let articleRetention: ArticleRetaining
    private let thumbnailService: ArticleThumbnailCaching
    private var thumbnailPrefetchTask: Task<Void, Never>?

    init(
        persistence: FeedPersisting,
        opmlService: OPMLServing = OPMLService(),
        feedFetching: FeedFetching = FeedFetchingService(),
        feedIconService: FeedIconResolving = FeedIconService(),
        // RATIONALE: Default cannot reference the `persistence` parameter in a default-value
        // expression, so nil-coalescing is used to construct the default inside the body.
        thumbnailPrefetcher: ThumbnailPrefetching? = nil,
        articleRetention: ArticleRetaining = ArticleRetentionService(),
        thumbnailService: ArticleThumbnailCaching = ArticleThumbnailService()
    ) {
        self.persistence = persistence
        self.opmlService = opmlService
        self.feedFetching = feedFetching
        self.feedIconService = feedIconService
        self.thumbnailPrefetcher = thumbnailPrefetcher ?? ThumbnailPrefetchService(persistence: persistence)
        self.articleRetention = articleRetention
        self.thumbnailService = thumbnailService
    }

    func loadFeeds() {
        do {
            feeds = try persistence.allFeeds()
            errorMessage = nil
            refreshUnreadCounts()
            Self.logger.debug("Loaded \(self.feeds.count, privacy: .public) feeds")
        } catch {
            errorMessage = "Unable to load your feeds."
            Self.logger.error("Failed to load feeds: \(error, privacy: .public)")
        }
    }

    func refreshUnreadCounts() {
        Self.logger.debug("refreshUnreadCounts() called for \(self.feeds.count, privacy: .public) feeds")
        var counts: [UUID: Int] = [:]
        var hadError = false
        for feed in feeds {
            do {
                counts[feed.id] = try persistence.unreadCount(for: feed)
            } catch {
                hadError = true
                Self.logger.error("Failed to fetch unread count for '\(feed.title, privacy: .public)': \(error, privacy: .public)")
                // Preserve previous count — showing a stale value is less misleading than
                // resetting to 0 and making the user think they have no unread articles.
                counts[feed.id] = unreadCounts[feed.id] ?? 0
            }
        }
        unreadCounts = counts
        if hadError {
            errorMessage = "Unable to update unread counts."
        } else {
            errorMessage = nil
        }
    }

    func removeFeed(_ feed: PersistentFeed) {
        let previousFeeds = feeds
        let feedID = feed.id
        feeds.removeAll { $0.id == feedID }
        do {
            try persistence.deleteFeed(feed)
            unreadCounts.removeValue(forKey: feedID)
            feedIconService.deleteCachedIcon(for: feedID)
            Self.logger.notice("Removed feed '\(feed.title, privacy: .public)'")
        } catch {
            feeds = previousFeeds
            errorMessage = "Unable to save changes."
            Self.logger.error("Failed to persist feed removal: \(error, privacy: .public)")
        }
    }

    func removeFeed(at offsets: IndexSet) {
        let previousFeeds = feeds
        let removed = offsets.map { feeds[$0] }
        feeds.remove(atOffsets: offsets)
        do {
            for feed in removed {
                let feedID = feed.id
                try persistence.deleteFeed(feed)
                unreadCounts.removeValue(forKey: feedID)
                feedIconService.deleteCachedIcon(for: feedID)
                Self.logger.notice("Removed feed '\(feed.title, privacy: .public)'")
            }
        } catch {
            feeds = previousFeeds
            errorMessage = "Unable to save changes."
            Self.logger.error("Failed to persist feed removal: \(error, privacy: .public)")
        }
    }

    func refreshUnreadCount(for feed: PersistentFeed) {
        do {
            unreadCounts[feed.id] = try persistence.unreadCount(for: feed)
            errorMessage = nil
        } catch {
            errorMessage = "Unable to update unread count."
            Self.logger.error("Failed to fetch unread count for '\(feed.title, privacy: .public)': \(error, privacy: .public)")
            // Preserve previous count — showing a stale value is less misleading than
            // resetting to 0 and making the user think they have no unread articles.
        }
    }

    func unreadCount(for feed: PersistentFeed) -> Int {
        unreadCounts[feed.id] ?? 0
    }

    // MARK: - OPML Import/Export

    func importOPML(from url: URL) {
        guard let data = readSecurityScopedData(from: url) else { return }
        importOPML(from: data)
    }

    func importOPML(from data: Data) {
        importExportErrorMessage = nil
        Self.logger.debug("importOPML() called with \(data.count, privacy: .public) bytes")

        let entries: [OPMLFeedEntry]
        do {
            entries = try opmlService.parseOPML(data)
        } catch {
            importExportErrorMessage = "Unable to import feeds. The file may be invalid."
            Self.logger.error("OPML parse failed: \(error, privacy: .public)")
            return
        }

        var addedCount = 0
        var skippedCount = 0

        for entry in entries {
            do {
                if try persistence.feedExists(url: entry.feedURL) {
                    skippedCount += 1
                    Self.logger.debug("Skipped duplicate: \(entry.feedURL.absoluteString, privacy: .public)")
                } else {
                    let newFeed = PersistentFeed(
                        title: entry.title,
                        feedURL: entry.feedURL,
                        feedDescription: entry.description
                    )
                    try persistence.addFeed(newFeed)
                    addedCount += 1
                }
            } catch {
                importExportErrorMessage = "Unable to save imported feeds."
                Self.logger.error("Failed to persist OPML import: \(error, privacy: .public)")
                loadFeeds()
                return
            }
        }

        loadFeeds()
        opmlImportResult = OPMLImportResult(
            addedCount: addedCount,
            skippedCount: skippedCount
        )
        importExportErrorMessage = nil
        Self.logger.notice("OPML import: added \(addedCount, privacy: .public), skipped \(skippedCount, privacy: .public)")
    }

    func exportOPML() {
        importExportErrorMessage = nil
        Self.logger.debug("exportOPML() called")
        do {
            let subscribedFeeds = feeds.map { $0.toSubscribedFeed() }
            let data = try opmlService.generateOPML(from: subscribedFeeds)
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("RSS Subscriptions.opml")
            try data.write(to: tempURL)
            opmlExportURL = tempURL
        } catch {
            importExportErrorMessage = "Unable to export feeds."
            Self.logger.error("OPML export failed: \(error, privacy: .public)")
        }
    }

    // MARK: - OPML Import with Refresh

    func importOPMLAndRefresh(from url: URL) async {
        guard let data = readSecurityScopedData(from: url) else { return }
        await importOPMLAndRefresh(from: data)
    }

    func importOPMLAndRefresh(from data: Data) async {
        importOPML(from: data)
        guard let result = opmlImportResult, result.addedCount > 0 else { return }
        await refreshAllFeeds()
    }

    // MARK: - Helpers

    private func readSecurityScopedData(from url: URL) -> Data? {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        do {
            return try Data(contentsOf: url)
        } catch {
            importExportErrorMessage = "Unable to read the selected file."
            Self.logger.error("Failed to read OPML file: \(error, privacy: .public)")
            return nil
        }
    }

    // MARK: - Feed Metadata Refresh

    func refreshAllFeeds() async {
        Self.logger.debug("refreshAllFeeds() called for \(self.feeds.count, privacy: .public) feeds")
        guard !feeds.isEmpty, !isRefreshing else { return }
        errorMessage = nil
        isRefreshing = true
        defer { isRefreshing = false }

        let feedsToRefresh = feeds
        let feedFetching = self.feedFetching
        let logger = Self.logger
        let maxConcurrency = 6

        let results: [(UUID, Result<FeedFetchResult?, any Error>)]
        do {
            results = try await withThrowingTaskGroup(
            of: (UUID, Result<FeedFetchResult?, any Error>).self,
            returning: [(UUID, Result<FeedFetchResult?, any Error>)].self
        ) { group in
            var collected: [(UUID, Result<FeedFetchResult?, any Error>)] = []
            var iterator = feedsToRefresh.makeIterator()

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
            Self.logger.debug("refreshAllFeeds() cancelled")
            return
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
                    Task {
                        await self.resolveAndCacheIconIfNeeded(
                            for: feed,
                            siteURL: Self.siteURL(from: feed.feedURL),
                            feedImageURL: feed.iconURL
                        )
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

                Task {
                    await self.resolveAndCacheIconIfNeeded(
                        for: feed,
                        siteURL: fetchResult.feed.link,
                        feedImageURL: fetchResult.feed.imageURL
                    )
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

        // loadFeeds() clears errorMessage on success, so error feedback must be set after this call.
        loadFeeds()
        Self.logger.notice("Refresh complete: \(self.feeds.count - failureCount, privacy: .public) updated, \(failureCount, privacy: .public) failed")

        if saveDidFail {
            errorMessage = "Unable to save updated feeds."
        } else if failureCount > 0 {
            errorMessage = "\(failureCount) of \(feedsToRefresh.count) feed(s) could not be updated."
        }

        // Enforce article retention limit after refresh — delete oldest articles
        // that exceed the configured limit, including their disk-cached thumbnails.
        do {
            try articleRetention.enforceArticleLimit(
                persistence: persistence,
                thumbnailService: thumbnailService
            )
        } catch {
            Self.logger.error("Article retention cleanup failed: \(error, privacy: .public)")
            // Only set if no higher-priority error (save failure, fetch failure) is already displayed.
            if errorMessage == nil {
                errorMessage = "Article cleanup could not complete."
            }
        }

        // Cancel any in-flight prefetch from a previous refresh cycle before starting a new one
        thumbnailPrefetchTask?.cancel()
        thumbnailPrefetchTask = Task(priority: .utility) {
            await self.thumbnailPrefetcher.prefetchThumbnails()
        }
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
            // RATIONALE: No errorMessage set here. This runs inside a fire-and-forget Task
            // spawned by refreshAllFeeds(), so setting errorMessage would race with the
            // post-refresh errorMessage assignments. Icon persistence failure is also cosmetic
            // and self-healing — the icon is re-resolved and re-cached on the next refresh.
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
