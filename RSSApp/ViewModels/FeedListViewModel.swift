import Foundation
import os

@MainActor
@Observable
final class FeedListViewModel {

    private static let logger = Logger(
        subsystem: "com.nicholas-lonsinger.rss-app",
        category: "FeedListViewModel"
    )

    private(set) var feeds: [PersistentFeed] = []
    private var unreadCounts: [UUID: Int] = [:]
    private(set) var isRefreshing = false
    var errorMessage: String?
    var opmlImportResult: OPMLImportResult?
    var opmlExportURL: URL?

    private let persistence: FeedPersisting
    private let opmlService: OPMLServing
    private let feedFetching: FeedFetching
    private let feedIconService: FeedIconResolving

    init(
        persistence: FeedPersisting,
        opmlService: OPMLServing = OPMLService(),
        feedFetching: FeedFetching = FeedFetchingService(),
        feedIconService: FeedIconResolving = FeedIconService()
    ) {
        self.persistence = persistence
        self.opmlService = opmlService
        self.feedFetching = feedFetching
        self.feedIconService = feedIconService
    }

    func loadFeeds() {
        do {
            feeds = try persistence.allFeeds()
            refreshUnreadCounts()
            errorMessage = nil
            Self.logger.debug("Loaded \(self.feeds.count, privacy: .public) feeds")
        } catch {
            errorMessage = "Unable to load your feeds."
            Self.logger.error("Failed to load feeds: \(error, privacy: .public)")
        }
    }

    func refreshUnreadCounts() {
        Self.logger.debug("refreshUnreadCounts() called for \(self.feeds.count, privacy: .public) feeds")
        var counts: [UUID: Int] = [:]
        for feed in feeds {
            do {
                counts[feed.id] = try persistence.unreadCount(for: feed)
            } catch {
                Self.logger.error("Failed to fetch unread count for '\(feed.title, privacy: .public)': \(error, privacy: .public)")
                counts[feed.id] = 0
            }
        }
        unreadCounts = counts
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
        } catch {
            Self.logger.error("Failed to fetch unread count for '\(feed.title, privacy: .public)': \(error, privacy: .public)")
            unreadCounts[feed.id] = 0
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
        Self.logger.debug("importOPML() called with \(data.count, privacy: .public) bytes")

        let entries: [OPMLFeedEntry]
        do {
            entries = try opmlService.parseOPML(data)
        } catch {
            errorMessage = "Unable to import feeds. The file may be invalid."
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
                errorMessage = "Unable to save imported feeds."
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
        errorMessage = nil
        Self.logger.notice("OPML import: added \(addedCount, privacy: .public), skipped \(skippedCount, privacy: .public)")
    }

    func exportOPML() {
        Self.logger.debug("exportOPML() called")
        do {
            let subscribedFeeds = feeds.map { $0.toSubscribedFeed() }
            let data = try opmlService.generateOPML(from: subscribedFeeds)
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("RSS Subscriptions.opml")
            try data.write(to: tempURL)
            opmlExportURL = tempURL
        } catch {
            errorMessage = "Unable to export feeds."
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
            errorMessage = "Unable to read the selected file."
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
            guard let feed = idToFeed[id] else { continue }
            switch result {
            case .success(let fetchResult):
                guard let fetchResult else {
                    // 304 Not Modified — feed is unchanged, just clear error state
                    Self.logger.notice("[ICON] '\(feed.title, privacy: .public)' got 304")
                    do {
                        try persistence.updateFeedError(feed, error: nil)
                    } catch {
                        Self.logger.error("Failed to clear error state for '\(feed.title, privacy: .public)': \(error, privacy: .public)")
                    }
                    // Still resolve icon if not cached (e.g., add-time resolution failed)
                    if feedIconService.cachedIconFileURL(for: feed.id) == nil {
                        Self.logger.notice("[ICON] '\(feed.title, privacy: .public)' 304 branch: no cached icon, resolving...")
                        let siteURL = Self.siteURL(from: feed.feedURL)
                        let iconURL = await feedIconService.resolveIconURL(
                            feedSiteURL: siteURL,
                            feedImageURL: feed.iconURL
                        )
                        if let iconURL {
                            Self.logger.notice("[ICON] '\(feed.title, privacy: .public)' resolved to \(iconURL.absoluteString, privacy: .public), caching...")
                            let cached = await feedIconService.cacheIcon(from: iconURL, feedID: feed.id)
                            Self.logger.notice("[ICON] '\(feed.title, privacy: .public)' cache result: \(cached, privacy: .public)")
                            if cached {
                                try? persistence.updateFeedIcon(feed, iconURL: iconURL)
                            }
                        } else {
                            Self.logger.notice("[ICON] '\(feed.title, privacy: .public)' 304 branch: resolveIconURL returned nil")
                        }
                    } else {
                        Self.logger.notice("[ICON] '\(feed.title, privacy: .public)' 304 branch: already cached")
                    }
                    continue
                }
                do {
                    try persistence.updateFeedMetadata(feed, title: fetchResult.feed.title, description: fetchResult.feed.feedDescription)
                    try persistence.upsertArticles(fetchResult.feed.articles, for: feed)
                    try persistence.updateFeedCacheHeaders(feed, etag: fetchResult.etag, lastModified: fetchResult.lastModified)

                    // Resolve and cache icon if not already cached
                    if feedIconService.cachedIconFileURL(for: feed.id) == nil {
                        Self.logger.notice("[ICON] '\(feed.title, privacy: .public)' 200 branch: no cached icon, resolving (siteURL=\(fetchResult.feed.link?.absoluteString ?? "nil", privacy: .public), imageURL=\(fetchResult.feed.imageURL?.absoluteString ?? "nil", privacy: .public))...")
                        let iconURL = await feedIconService.resolveIconURL(
                            feedSiteURL: fetchResult.feed.link,
                            feedImageURL: fetchResult.feed.imageURL
                        )
                        if let iconURL {
                            Self.logger.notice("[ICON] '\(feed.title, privacy: .public)' resolved to \(iconURL.absoluteString, privacy: .public), caching...")
                            let cached = await feedIconService.cacheIcon(from: iconURL, feedID: feed.id)
                            Self.logger.notice("[ICON] '\(feed.title, privacy: .public)' cache result: \(cached, privacy: .public)")
                            if cached {
                                try? persistence.updateFeedIcon(feed, iconURL: iconURL)
                            }
                        } else {
                            Self.logger.notice("[ICON] '\(feed.title, privacy: .public)' resolveIconURL returned nil")
                        }
                    } else {
                        Self.logger.notice("[ICON] '\(feed.title, privacy: .public)' 200 branch: already cached")
                    }
                } catch {
                    failureCount += 1
                    Self.logger.error("Failed to persist refresh for '\(feed.title, privacy: .public)': \(error, privacy: .public)")
                }
            case .failure(let error):
                failureCount += 1
                do {
                    try persistence.updateFeedError(feed, error: Self.errorDescription(for: error))
                } catch {
                    Self.logger.error("Failed to persist error state for '\(feed.title, privacy: .public)': \(error, privacy: .public)")
                }
            }
        }

        do {
            try persistence.save()
        } catch {
            Self.logger.error("Failed to save after refresh: \(error, privacy: .public)")
        }

        loadFeeds()
        Self.logger.notice("Refresh complete: \(self.feeds.count - failureCount, privacy: .public) updated, \(failureCount, privacy: .public) failed")

        if failureCount > 0 {
            errorMessage = "\(failureCount) of \(feedsToRefresh.count) feed(s) could not be updated."
        }
    }

    /// Derives a site root URL from a feed URL (e.g., https://example.com/feed → https://example.com).
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
