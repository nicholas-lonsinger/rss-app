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

    /// Reorders feeds by moving the items at `source` to `destination`.
    /// Called by SwiftUI's `onMove` modifier on the feed list.
    func moveFeed(from source: IndexSet, to destination: Int) {
        feeds.move(fromOffsets: source, toOffset: destination)
        do {
            try persistence.updateFeedOrder(feeds)
            Self.logger.notice("Reordered feeds (moved to index \(destination, privacy: .public))")
        } catch {
            // Reload to restore the persisted order on failure.
            loadFeeds()
            // Only set the reorder error if loadFeeds() didn't already surface
            // a more severe error (e.g. "Unable to load your feeds.").
            if errorMessage == nil {
                errorMessage = "Unable to reorder feeds."
            }
            Self.logger.error("Failed to persist feed reorder: \(error, privacy: .public)")
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

        let parseResult: OPMLParseResult
        do {
            parseResult = try opmlService.parseOPML(data)
        } catch {
            importExportErrorMessage = "Unable to import feeds. The file may be invalid."
            Self.logger.error("OPML parse failed: \(error, privacy: .public)")
            return
        }

        let entries = parseResult.entries
        var addedCount = 0
        var skippedCount = 0
        var failedCount = 0
        let parseSkippedCount = parseResult.parseSkippedCount
        var groupsCreatedCount = 0
        var groupsReusedCount = 0
        var groupsFailedCount = 0

        // Build a cache of existing groups by name so we can reuse them.
        var groupsByName: [String: PersistentFeedGroup]
        do {
            let existingGroups = try persistence.allGroups()
            groupsByName = Dictionary(
                existingGroups.map { ($0.name, $0) },
                uniquingKeysWith: { first, _ in first }
            )
        } catch {
            importExportErrorMessage = "Unable to load existing groups. Import aborted."
            Self.logger.error("Failed to load existing groups: \(error, privacy: .public)")
            loadFeeds()
            return
        }

        // Build a cache of existing feeds by URL so duplicate lookups are O(1).
        var feedsByURL: [URL: PersistentFeed]
        do {
            let existingFeeds = try persistence.allFeeds()
            feedsByURL = Dictionary(
                existingFeeds.map { ($0.feedURL, $0) },
                uniquingKeysWith: { first, _ in first }
            )
        } catch {
            importExportErrorMessage = "Unable to load existing feeds. Import aborted."
            Self.logger.error("Failed to load existing feeds: \(error, privacy: .public)")
            loadFeeds()
            return
        }

        // Track the next sortOrder for newly-added feeds so they appear after
        // any user-customized order rather than defaulting to 0 and displacing
        // existing feeds.
        var nextFeedSortOrder = (feedsByURL.values.map(\.sortOrder).max() ?? -1) + 1

        // Snapshot of feed URLs that existed before this import began. Used below
        // to distinguish true pre-existing duplicates (count once as skipped) from
        // multi-group OPML appearances of a feed added earlier in this same import
        // (standard OPML structure — not reported as duplicates).
        let preImportURLs = Set(feedsByURL.keys)
        // Tracks which pre-existing URLs have already been counted as skipped so
        // each pre-existing duplicate is reported at most once, regardless of how
        // many groups it appears under in the OPML file.
        var skippedURLs: Set<URL> = []

        // Track which group names were created vs. reused during this import
        // to avoid double-counting when multiple entries reference the same group.
        var createdGroupNames: Set<String> = []
        var reusedGroupNames: Set<String> = []

        for entry in entries {
            // --- Add or look up the feed ---
            let feed: PersistentFeed

            if let existingFeed = feedsByURL[entry.feedURL] {
                feed = existingFeed
                // Only count as skipped if this URL was already in the user's
                // subscription list before the import started. A feed added
                // earlier in this same import appearing under another group is
                // normal multi-group OPML structure and must not be reported as
                // a duplicate.
                if preImportURLs.contains(entry.feedURL), !skippedURLs.contains(entry.feedURL) {
                    skippedCount += 1
                    skippedURLs.insert(entry.feedURL)
                    Self.logger.debug("Skipped duplicate: \(entry.feedURL.absoluteString, privacy: .public)")
                } else if !preImportURLs.contains(entry.feedURL) {
                    Self.logger.debug("Multi-group entry (not a duplicate): \(entry.feedURL.absoluteString, privacy: .public)")
                } else {
                    Self.logger.debug("Pre-existing duplicate already counted, skipping: \(entry.feedURL.absoluteString, privacy: .public)")
                }
            } else {
                let newFeed = PersistentFeed(
                    title: entry.title,
                    feedURL: entry.feedURL,
                    feedDescription: entry.description,
                    siteURL: entry.siteURL,
                    sortOrder: nextFeedSortOrder
                )
                do {
                    try persistence.addFeed(newFeed)
                    feedsByURL[entry.feedURL] = newFeed
                    feed = newFeed
                    addedCount += 1
                    nextFeedSortOrder += 1
                } catch {
                    failedCount += 1
                    Self.logger.error("Failed to add feed '\(entry.title, privacy: .public)': \(error, privacy: .public)")
                    continue
                }
            }

            // --- Assign the feed to its OPML category group if present ---
            if let groupName = entry.groupName {
                let group: PersistentFeedGroup
                if let existingGroup = groupsByName[groupName] {
                    group = existingGroup
                    if !createdGroupNames.contains(groupName) {
                        reusedGroupNames.insert(groupName)
                    }
                } else {
                    let maxSortOrder = groupsByName.values.map(\.sortOrder).max() ?? -1
                    let newGroup = PersistentFeedGroup(
                        name: groupName,
                        sortOrder: maxSortOrder + 1
                    )
                    do {
                        try persistence.addGroup(newGroup)
                        groupsByName[groupName] = newGroup
                        group = newGroup
                        createdGroupNames.insert(groupName)
                        reusedGroupNames.remove(groupName)
                    } catch {
                        groupsFailedCount += 1
                        Self.logger.error("Failed to create group '\(groupName, privacy: .public)': \(error, privacy: .public)")
                        continue
                    }
                }
                do {
                    try persistence.addFeed(feed, to: group)
                } catch {
                    groupsFailedCount += 1
                    Self.logger.error("Failed to assign feed '\(entry.title, privacy: .public)' to group '\(groupName, privacy: .public)': \(error, privacy: .public)")
                }
            }
        }

        groupsCreatedCount = createdGroupNames.count
        groupsReusedCount = reusedGroupNames.count

        loadFeeds()
        opmlImportResult = OPMLImportResult(
            addedCount: addedCount,
            skippedCount: skippedCount,
            failedCount: failedCount,
            parseSkippedCount: parseSkippedCount,
            groupsCreatedCount: groupsCreatedCount,
            groupsReusedCount: groupsReusedCount,
            groupsFailedCount: groupsFailedCount
        )
        importExportErrorMessage = nil
        Self.logger.notice("OPML import: added \(addedCount, privacy: .public), skipped \(skippedCount, privacy: .public), failed \(failedCount, privacy: .public), parse-skipped \(parseSkippedCount, privacy: .public), groups created \(groupsCreatedCount, privacy: .public), groups reused \(groupsReusedCount, privacy: .public), groups failed \(groupsFailedCount, privacy: .public)")
    }

    func exportOPML() {
        importExportErrorMessage = nil
        Self.logger.debug("exportOPML() called")

        // Fetch all memberships in one query and build a lookup table so the
        // per-feed group-name resolution below is O(1) instead of N queries.
        let allMemberships: [PersistentFeedGroupMembership]
        do {
            allMemberships = try persistence.allGroupMemberships()
        } catch {
            importExportErrorMessage = "Unable to export feeds."
            Self.logger.error("OPML export failed — could not fetch group memberships: \(error, privacy: .public)")
            return
        }

        var groupNamesByFeedID: [UUID: [String]] = [:]
        for membership in allMemberships {
            guard let feedID = membership.feed?.id,
                  let groupName = membership.group?.name else {
                Self.logger.warning("Skipping membership with nil feed or group during OPML export — orphaned record in SwiftData")
                continue
            }
            groupNamesByFeedID[feedID, default: []].append(groupName)
        }

        do {
            let groupedFeeds: [GroupedFeed] = feeds.map { feed in
                let groupNames = groupNamesByFeedID[feed.id] ?? []
                return GroupedFeed(feed: feed.toSubscribedFeed(), groupNames: groupNames)
            }
            let data = try opmlService.generateOPML(from: groupedFeeds)
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("RSS Subscriptions.opml")
            try data.write(to: tempURL)
            opmlExportURL = tempURL
        } catch {
            importExportErrorMessage = "Unable to export feeds."
            Self.logger.error("OPML export failed — could not generate or write OPML data: \(error, privacy: .public)")
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
                let attempted = summary.totalFeeds - summary.skippedCount
                errorMessage = "\(summary.failureCount) of \(attempted) feed(s) could not be updated."
            } else if summary.retentionCleanupFailed {
                errorMessage = "Article cleanup could not complete."
            }
        }
    }
}
