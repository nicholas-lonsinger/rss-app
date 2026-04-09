import Foundation
import os

@MainActor
@Observable
final class FeedListViewModel {

    private static let logger = Logger(category: "FeedListViewModel")

    private(set) var feeds: [PersistentFeed] = []
    private var unreadCounts: [UUID: Int] = [:]
    var errorMessage: String?
    var importExportErrorMessage: String?
    var opmlImportResult: OPMLImportResult?
    var opmlExportURL: URL?

    private let persistence: FeedPersisting
    private let opmlService: OPMLServing
    private let refreshService: FeedRefreshService
    let feedIconService: FeedIconResolving

    init(
        persistence: FeedPersisting,
        refreshService: FeedRefreshService,
        feedIconService: FeedIconResolving,
        opmlService: OPMLServing = OPMLService()
    ) {
        self.persistence = persistence
        self.refreshService = refreshService
        self.feedIconService = feedIconService
        self.opmlService = opmlService
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

    /// Delegates the refresh work to the shared `FeedRefreshService`, then
    /// reloads feeds and translates the service outcome into UI error state.
    func refreshAllFeeds() async {
        Self.logger.debug("refreshAllFeeds() called")
        errorMessage = nil
        let outcome = await refreshService.refreshAllFeeds()

        // Always reload so any persistence changes (new articles, updated
        // metadata, retention-cleaned rows) are reflected in the UI, even when
        // the service coalesced with another caller's in-flight refresh.
        // loadFeeds() clears errorMessage on success, so the outcome-based
        // error assignments below must run AFTER loadFeeds() to survive.
        loadFeeds()

        switch outcome {
        case .skipped:
            // Either another caller is still refreshing, or there were no
            // feeds to refresh in the first place. Leave errorMessage nil —
            // loadFeeds() already cleared it.
            break
        case .setupFailed:
            errorMessage = "Unable to load your feeds."
        case .cancelled:
            // Cancellation is typically caused by a BG task expiration or a
            // view-teardown cancel — neither warrants a user-visible error.
            // The in-flight work has been abandoned; the next refresh picks
            // up from where this one left off.
            break
        case .completed(let summary):
            if summary.saveDidFail {
                errorMessage = "Unable to save updated feeds."
            } else if summary.failureCount > 0 {
                errorMessage = "\(summary.failureCount) of \(summary.totalFeeds) feed(s) could not be updated."
            } else if summary.retentionCleanupFailed {
                errorMessage = "Article cleanup could not complete."
            }
        }
    }
}
