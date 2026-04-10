import Foundation
import os

@MainActor
@Observable
final class HomeViewModel {

    private static let logger = Logger(category: "HomeViewModel")

    /// Number of articles to fetch per page.
    static let pageSize = 50

    /// Minimum interval between automatic on-entry network refreshes for
    /// cross-feed lists. A user navigating between `All Articles` / `Unread
    /// Articles` in rapid succession should see cached data on the second
    /// entry rather than stacking redundant refreshes. Pull-to-refresh is
    /// never throttled — it's an explicit user action that bypasses the gate.
    /// Background refresh updates the same timestamp via
    /// `FeedRefreshService.lastRefreshCompletedAt`, so the throttle honors BG
    /// work as well as foreground work.
    static let entryRefreshInterval: TimeInterval = 5 * 60

    /// Whether a fresh on-entry network refresh should be triggered. Reads the
    /// process-wide `FeedRefreshService.lastRefreshCompletedAt` timestamp
    /// (shared with the BG refresh path) and compares it against
    /// `entryRefreshInterval`. Returns `true` when no refresh has ever
    /// completed on this install, or when the most recent completion is
    /// older than the interval. Used by `AllArticlesSource`,
    /// `UnreadArticlesSource`, and `GroupArticleSource` to gate the
    /// `refreshAllFeeds()` call in their `initialLoad()`;
    /// `SavedArticlesSource` does not consult it at all because saved
    /// articles never benefit from a feed refresh.
    var shouldRefreshOnEntry: Bool {
        guard let last = FeedRefreshService.lastRefreshCompletedAt else {
            return true
        }
        return Date().timeIntervalSince(last) > Self.entryRefreshInterval
    }

    private(set) var unreadCount: Int = 0
    private(set) var isRefreshing = false
    private(set) var errorMessage: String?

    // MARK: - Group state

    private(set) var groups: [PersistentFeedGroup] = []
    private(set) var groupUnreadCounts: [UUID: Int] = [:]

    // MARK: - Pagination state for all articles

    private(set) var allArticlesList: [PersistentArticle] = []
    private(set) var hasMoreAllArticles = true

    // MARK: - Pagination state for unread articles

    private(set) var unreadArticlesList: [PersistentArticle] = []
    private(set) var hasMoreUnreadArticles = true

    // MARK: - Pagination state for saved articles

    private(set) var savedArticlesList: [PersistentArticle] = []
    private(set) var hasMoreSavedArticles = true

    // RATIONALE: Unlike FeedViewModel.sortAscending which auto-reloads on set,
    // HomeViewModel does not auto-reload because it serves three independent adapters
    // (AllArticlesSource, UnreadArticlesSource, and SavedArticlesSource) that each need
    // to reload their own specific list. Callers toggle the property then call the
    // appropriate reload method (loadAllArticles, loadUnreadArticles, or
    // loadSavedArticles) for their view.
    /// Current sort order — reads from the global UserDefaults preference.
    var sortAscending: Bool {
        get { UserDefaults.standard.bool(forKey: FeedViewModel.sortAscendingKey) }
        set {
            guard UserDefaults.standard.bool(forKey: FeedViewModel.sortAscendingKey) != newValue else { return }
            UserDefaults.standard.set(newValue, forKey: FeedViewModel.sortAscendingKey)
            Self.logger.debug("sortAscending changed to \(newValue, privacy: .public)")
        }
    }

    private let persistence: FeedPersisting
    private let badgeService: AppBadgeUpdating

    /// Async closure that performs the actual network feed refresh.
    /// Returns an error message string on failure, or nil on success.
    /// Injected by the caller to perform the actual network feed refresh.
    private let refreshFeeds: (@Sendable () async -> String?)?

    init(
        persistence: FeedPersisting,
        badgeService: AppBadgeUpdating = AppBadgeService(),
        refreshFeeds: (@Sendable () async -> String?)? = nil
    ) {
        self.persistence = persistence
        self.badgeService = badgeService
        self.refreshFeeds = refreshFeeds
    }

    func clearError() {
        errorMessage = nil
    }

    // MARK: - Refresh

    /// Triggers a full network refresh of all feeds.
    /// When no refresh closure is configured, this is a no-op.
    ///
    /// This method only performs the network refresh and sets `errorMessage` on failure.
    /// Callers are responsible for reloading local data afterward (e.g., `loadUnreadCount()`,
    /// `loadAllArticles()`) so each view reloads exactly what it needs.
    func refreshAllFeeds() async {
        guard let refreshFeeds else {
            Self.logger.debug("refreshAllFeeds() called but no refresh closure configured")
            return
        }
        guard !isRefreshing else {
            Self.logger.debug("refreshAllFeeds() skipped — already refreshing")
            return
        }
        Self.logger.debug("refreshAllFeeds() starting network refresh")
        errorMessage = nil
        isRefreshing = true
        defer { isRefreshing = false }

        let refreshError = await refreshFeeds()
        if let refreshError {
            errorMessage = refreshError
            Self.logger.error("refreshAllFeeds() finished with error: \(refreshError, privacy: .public)")
        } else {
            Self.logger.notice("refreshAllFeeds() completed successfully")
        }
    }

    func loadUnreadCount() {
        do {
            unreadCount = try persistence.totalUnreadCount()
            Self.logger.debug("Total unread count: \(self.unreadCount, privacy: .public)")
            // RATIONALE: Fire-and-forget Task is intentional. Badge update is best-effort
            // and should not block article loading or propagate errors to the UI.
            Task { await badgeService.updateBadge(unreadCount: unreadCount) }
        } catch {
            errorMessage = "Unable to load unread count."
            Self.logger.error("Failed to load total unread count: \(error, privacy: .public)")
        }
    }

    /// Updates the app icon badge to reflect the current unread count.
    /// Call directly when the badge setting changes to apply immediately.
    func updateBadge() async {
        await badgeService.updateBadge(unreadCount: unreadCount)
    }

    /// Handles the badge toggle being switched ON.
    ///
    /// Checks notification permission and either updates the badge (if authorized
    /// or newly granted) or signals the caller to revert the toggle (if denied,
    /// including the case where the user denies the system prompt).
    ///
    /// - Returns: `true` if the toggle should remain ON, `false` if it must revert to OFF.
    func handleBadgeToggleEnabled() async -> Bool {
        let status = await badgeService.checkPermission()
        if status == .denied {
            Self.logger.notice("Badge toggle enabled but notification permission denied — caller should revert toggle")
            return false
        }

        // Permission is .authorized or .notDetermined. updateBadge() triggers the
        // system prompt when .notDetermined, so the user may still deny. Re-check
        // permission afterward to catch that case.
        await updateBadge()

        let postPromptStatus = await badgeService.checkPermission()
        if postPromptStatus == .denied {
            Self.logger.notice("Badge toggle enabled but user denied system permission prompt — caller should revert toggle")
            return false
        }

        return true
    }

    // MARK: - All Articles (paginated)

    /// Resets pagination and loads the first page of all articles.
    /// On failure, preserves the previously loaded list to avoid flashing an empty state.
    func loadAllArticles() {
        let previous = allArticlesList
        allArticlesList = []
        hasMoreAllArticles = true
        loadMoreAllArticles()
        if allArticlesList.isEmpty && errorMessage != nil {
            allArticlesList = previous
        }
    }

    /// Loads the next page of all articles and appends to the existing list.
    @discardableResult
    func loadMoreAllArticles() -> LoadMoreResult {
        let ascending = sortAscending
        return loadMorePage(
            into: &allArticlesList,
            hasMore: &hasMoreAllArticles,
            fetch: { offset, limit in try self.persistence.allArticles(offset: offset, limit: limit, ascending: ascending) },
            label: "all articles"
        )
    }

    /// Loads the next page of all articles and returns the outcome, clearing `errorMessage` on failure
    /// so only the caller (article reader) displays the error — not the list view's alert.
    func loadMoreAllArticlesAndReport() -> LoadMoreResult {
        let result = loadMoreAllArticles()
        if case .failed = result {
            errorMessage = nil
        }
        return result
    }

    // MARK: - Unread Articles (paginated)

    /// Resets pagination and loads the first page of unread articles.
    /// On failure, preserves the previously loaded list to avoid flashing an empty state.
    func loadUnreadArticles() {
        let previous = unreadArticlesList
        unreadArticlesList = []
        hasMoreUnreadArticles = true
        loadMoreUnreadArticles()
        if unreadArticlesList.isEmpty && errorMessage != nil {
            unreadArticlesList = previous
        }
    }

    /// Loads the next page of unread articles and appends to the existing list.
    @discardableResult
    func loadMoreUnreadArticles() -> LoadMoreResult {
        let ascending = sortAscending
        return loadMorePage(
            into: &unreadArticlesList,
            hasMore: &hasMoreUnreadArticles,
            fetch: { offset, limit in try self.persistence.allUnreadArticles(offset: offset, limit: limit, ascending: ascending) },
            label: "unread articles"
        )
    }

    /// Loads the next page of unread articles and returns the outcome, clearing `errorMessage` on failure
    /// so only the caller (article reader) displays the error — not the list view's alert.
    func loadMoreUnreadArticlesAndReport() -> LoadMoreResult {
        let result = loadMoreUnreadArticles()
        if case .failed = result {
            errorMessage = nil
        }
        return result
    }

    // MARK: - Saved Articles (paginated)

    /// Resets pagination and loads the first page of saved articles.
    /// On failure, preserves the previously loaded list to avoid flashing an empty state.
    func loadSavedArticles() {
        let previous = savedArticlesList
        savedArticlesList = []
        hasMoreSavedArticles = true
        loadMoreSavedArticles()
        if savedArticlesList.isEmpty && errorMessage != nil {
            savedArticlesList = previous
        }
    }

    /// Loads the next page of saved articles and appends to the existing list.
    /// Sorted by `sortDate` with direction controlled by the global
    /// `sortAscending` preference — same as `allArticles` / `allUnreadArticles`
    /// so the saved list honors the user's newest-first / oldest-first choice.
    @discardableResult
    func loadMoreSavedArticles() -> LoadMoreResult {
        let ascending = sortAscending
        return loadMorePage(
            into: &savedArticlesList,
            hasMore: &hasMoreSavedArticles,
            fetch: { offset, limit in try self.persistence.allSavedArticles(offset: offset, limit: limit, ascending: ascending) },
            label: "saved articles"
        )
    }

    /// Loads the next page of saved articles and returns the outcome, clearing `errorMessage` on failure
    /// so only the caller (article reader) displays the error — not the list view's alert.
    func loadMoreSavedArticlesAndReport() -> LoadMoreResult {
        let result = loadMoreSavedArticles()
        if case .failed = result {
            errorMessage = nil
        }
        return result
    }

    // MARK: - Pagination Helpers

    /// Fetches the next page of articles, deduplicates, and appends to the list.
    /// On error, preserves `hasMore` so the user can retry by tapping next again.
    private func loadMorePage(
        into list: inout [PersistentArticle],
        hasMore: inout Bool,
        fetch: (_ offset: Int, _ limit: Int) throws -> [PersistentArticle],
        label: String
    ) -> LoadMoreResult {
        guard hasMore else { return .exhausted }
        do {
            let page = try fetch(list.count, Self.pageSize)
            let existingIDs = Set(list.map(\.articleID))
            let newItems = page.filter { !existingIDs.contains($0.articleID) }
            list.append(contentsOf: newItems)
            hasMore = page.count == Self.pageSize
            let totalCount = list.count
            Self.logger.debug("Loaded page of \(page.count, privacy: .public) \(label, privacy: .public) (\(newItems.count, privacy: .public) new, total: \(totalCount, privacy: .public))")
            return newItems.isEmpty ? .exhausted : .loaded
        } catch {
            // RATIONALE: hasMore is intentionally NOT set to false on error.
            // Pagination errors are transient (database hiccups, etc.) and the user
            // should be able to retry by tapping next again. The error is surfaced via
            // LoadMoreResult.failed so the caller can display an alert.
            let message = "Unable to load \(label)."
            errorMessage = message
            Self.logger.error("Failed to load \(label) page: \(error, privacy: .public)")
            return .failed(message)
        }
    }

    /// Marks the article as read and returns `true` on success, `false` on failure.
    @discardableResult
    func markAsRead(_ article: PersistentArticle) -> Bool {
        guard !article.isRead else { return true }
        do {
            try persistence.markArticleRead(article, isRead: true)
            loadUnreadCount()
            return true
        } catch {
            errorMessage = "Unable to mark article as read."
            Self.logger.error("Failed to mark article as read: \(error, privacy: .public)")
            return false
        }
    }

    func toggleReadStatus(_ article: PersistentArticle) {
        do {
            try persistence.markArticleRead(article, isRead: !article.isRead)
            loadUnreadCount()
        } catch {
            errorMessage = "Unable to update read status."
            Self.logger.error("Failed to toggle read status: \(error, privacy: .public)")
        }
    }

    func toggleSaved(_ article: PersistentArticle) {
        do {
            try persistence.toggleArticleSaved(article)
        } catch {
            errorMessage = "Unable to update saved status."
            Self.logger.error("Failed to toggle saved status: \(error, privacy: .public)")
        }
    }

    /// Marks all articles across all feeds as read. Does NOT re-query any of
    /// the three lists — per the snapshot-stable rule, bulk mutations update
    /// row visuals through `@Observable` propagation but leave list composition
    /// and order intact. In the Unread Articles list specifically, the
    /// just-read rows remain visible (now read-styled) until the user triggers
    /// an explicit refresh. `loadUnreadCount()` is still called so the Home
    /// badge and the sidebar count reflect the mutation immediately.
    func markAllAsRead() {
        do {
            try persistence.markAllArticlesRead()
            loadUnreadCount()
            Self.logger.notice("Marked all articles as read across all feeds")
        } catch {
            errorMessage = "Unable to mark all articles as read."
            Self.logger.error("Failed to mark all articles as read: \(error, privacy: .public)")
        }
    }

    /// Marks only saved articles as read. Scoped wrapper for the Saved
    /// Articles list's "Mark All as Read" action so the sweep covers exactly
    /// the list the user is looking at, not every article in the app. Same
    /// snapshot-stable semantics as `markAllAsRead()`: row visuals update
    /// via `@Observable` propagation but `savedArticlesList` composition is
    /// preserved until the user triggers an explicit refresh.
    func markAllSavedArticlesRead() {
        do {
            try persistence.markAllSavedArticlesRead()
            loadUnreadCount()
            Self.logger.notice("Marked all saved articles as read")
        } catch {
            errorMessage = "Unable to mark all saved articles as read."
            Self.logger.error("Failed to mark all saved articles as read: \(error, privacy: .public)")
        }
    }

    // MARK: - Groups

    func loadGroups() {
        do {
            groups = try persistence.allGroups()
            loadGroupUnreadCounts()
            Self.logger.debug("Loaded \(self.groups.count, privacy: .public) groups")
        } catch {
            errorMessage = "Unable to load groups."
            Self.logger.error("Failed to load groups: \(error, privacy: .public)")
        }
    }

    func loadGroupUnreadCounts() {
        var counts: [UUID: Int] = [:]
        var feedUnreadCache: [UUID: Int] = [:]
        for group in groups {
            do {
                let feeds = try persistence.feeds(in: group)
                var total = 0
                for feed in feeds {
                    if let cached = feedUnreadCache[feed.id] {
                        total += cached
                    } else {
                        let count = try persistence.unreadCount(for: feed)
                        feedUnreadCache[feed.id] = count
                        total += count
                    }
                }
                counts[group.id] = total
            } catch {
                Self.logger.error("Failed to load unread count for group '\(group.name, privacy: .public)': \(error, privacy: .public)")
                counts[group.id] = 0
            }
        }
        groupUnreadCounts = counts
    }

    func addGroup(name: String) {
        let nextSortOrder = (groups.map(\.sortOrder).max() ?? -1) + 1
        let group = PersistentFeedGroup(name: name, sortOrder: nextSortOrder)
        do {
            try persistence.addGroup(group)
            loadGroups()
            Self.logger.notice("Created group '\(name, privacy: .public)' at sortOrder \(nextSortOrder, privacy: .public)")
        } catch {
            errorMessage = "Unable to create group."
            Self.logger.error("Failed to create group '\(name, privacy: .public)': \(error, privacy: .public)")
        }
    }

    /// Reorders groups by moving the items at `source` to `destination`.
    /// Called by SwiftUI's `onMove` modifier on the groups section.
    func moveGroup(from source: IndexSet, to destination: Int) {
        groups.move(fromOffsets: source, toOffset: destination)
        do {
            try persistence.updateGroupOrder(groups)
            Self.logger.notice("Reordered groups (moved to index \(destination, privacy: .public))")
        } catch {
            // Reload to restore the persisted order on failure.
            loadGroups()
            errorMessage = "Unable to reorder groups."
            Self.logger.error("Failed to persist group reorder: \(error, privacy: .public)")
        }
    }

    func deleteGroup(_ group: PersistentFeedGroup) {
        let name = group.name
        do {
            try persistence.deleteGroup(group)
            loadGroups()
            Self.logger.notice("Deleted group '\(name, privacy: .public)'")
        } catch {
            errorMessage = "Unable to delete group."
            Self.logger.error("Failed to delete group '\(name, privacy: .public)': \(error, privacy: .public)")
        }
    }

    func renameGroup(_ group: PersistentFeedGroup, to name: String) {
        do {
            try persistence.renameGroup(group, to: name)
            loadGroups()
            Self.logger.notice("Renamed group to '\(name, privacy: .public)'")
        } catch {
            errorMessage = "Unable to rename group."
            Self.logger.error("Failed to rename group: \(error, privacy: .public)")
        }
    }

    /// Marks all articles in a group as read. Scoped to the group's feeds
    /// only — same pattern as `markAllSavedArticlesRead()` scoping to saved.
    func markAllArticlesReadInGroup(_ group: PersistentFeedGroup) {
        do {
            try persistence.markAllArticlesRead(in: group)
            loadUnreadCount()
            loadGroupUnreadCounts()
            Self.logger.notice("Marked all articles as read in group '\(group.name, privacy: .public)'")
        } catch {
            errorMessage = "Unable to mark all articles as read."
            Self.logger.error("Failed to mark all articles as read in group '\(group.name, privacy: .public)': \(error, privacy: .public)")
        }
    }
}
