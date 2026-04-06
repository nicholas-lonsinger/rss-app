import Foundation
import os

@MainActor
@Observable
final class HomeViewModel {

    private static let logger = Logger(category: "HomeViewModel")

    /// Number of articles to fetch per page.
    static let pageSize = 50

    private(set) var unreadCount: Int = 0
    private(set) var savedCount: Int = 0
    private(set) var isRefreshing = false
    private(set) var errorMessage: String?

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
    // HomeViewModel does not auto-reload because it serves three independent views
    // (AllArticlesView, UnreadArticlesView, and SavedArticlesView) that each need
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

    func loadSavedCount() {
        do {
            savedCount = try persistence.savedCount()
            Self.logger.debug("Total saved count: \(self.savedCount, privacy: .public)")
        } catch {
            errorMessage = "Unable to load saved count."
            Self.logger.error("Failed to load total saved count: \(error, privacy: .public)")
        }
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
    /// Saved articles are always sorted by `savedDate` descending (most recently saved first).
    @discardableResult
    func loadMoreSavedArticles() -> LoadMoreResult {
        return loadMorePage(
            into: &savedArticlesList,
            hasMore: &hasMoreSavedArticles,
            fetch: { offset, limit in try self.persistence.allSavedArticles(offset: offset, limit: limit) },
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
            loadSavedCount()
        } catch {
            errorMessage = "Unable to update saved status."
            Self.logger.error("Failed to toggle saved status: \(error, privacy: .public)")
        }
    }

    /// Removes an article from the local saved articles list without reloading from persistence.
    /// Used after unsaving an article in SavedArticlesView to avoid resetting pagination and scroll position.
    func removeFromSavedList(_ article: PersistentArticle) {
        savedArticlesList.removeAll { $0.articleID == article.articleID }
        Self.logger.debug("Removed article '\(article.articleID, privacy: .public)' from saved list (remaining: \(self.savedArticlesList.count, privacy: .public))")
    }

    /// Marks all articles across all feeds as read.
    func markAllAsRead() {
        do {
            try persistence.markAllArticlesRead()
            loadUnreadCount()
            loadAllArticles()
            unreadArticlesList = []
            hasMoreUnreadArticles = false
            Self.logger.notice("Marked all articles as read across all feeds")
        } catch {
            errorMessage = "Unable to mark all articles as read."
            Self.logger.error("Failed to mark all articles as read: \(error, privacy: .public)")
        }
    }
}
