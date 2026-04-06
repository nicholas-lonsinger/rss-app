import Foundation
import os

@MainActor
@Observable
final class HomeViewModel {

    private static let logger = Logger(category: "HomeViewModel")

    /// Number of articles to fetch per page.
    static let pageSize = 50

    private(set) var unreadCount: Int = 0
    private(set) var isRefreshing = false
    private(set) var errorMessage: String?

    // MARK: - Pagination state for all articles

    private(set) var allArticlesList: [PersistentArticle] = []
    private(set) var hasMoreAllArticles = true

    // MARK: - Pagination state for unread articles

    private(set) var unreadArticlesList: [PersistentArticle] = []
    private(set) var hasMoreUnreadArticles = true

    // RATIONALE: Unlike FeedViewModel.sortAscending which auto-reloads on set,
    // HomeViewModel does not auto-reload because it serves two independent views
    // (AllArticlesView and UnreadArticlesView) that each need to reload their own
    // specific list. Callers toggle the property then call the appropriate reload
    // method (loadAllArticles or loadUnreadArticles) for their view.
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

    /// Async closure that performs the actual network feed refresh.
    /// Returns an error message string on failure, or nil on success.
    /// Injected by the caller to perform the actual network feed refresh.
    private let refreshFeeds: (@Sendable () async -> String?)?

    init(persistence: FeedPersisting, refreshFeeds: (@Sendable () async -> String?)? = nil) {
        self.persistence = persistence
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
        } catch {
            errorMessage = "Unable to load unread count."
            Self.logger.error("Failed to load total unread count: \(error, privacy: .public)")
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
    func loadMoreAllArticles() {
        let ascending = sortAscending
        loadMorePage(
            into: &allArticlesList,
            hasMore: &hasMoreAllArticles,
            fetch: { offset, limit in try self.persistence.allArticles(offset: offset, limit: limit, ascending: ascending) },
            label: "all articles"
        )
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
    func loadMoreUnreadArticles() {
        let ascending = sortAscending
        loadMorePage(
            into: &unreadArticlesList,
            hasMore: &hasMoreUnreadArticles,
            fetch: { offset, limit in try self.persistence.allUnreadArticles(offset: offset, limit: limit, ascending: ascending) },
            label: "unread articles"
        )
    }

    // MARK: - Pagination Helpers

    /// Fetches the next page of articles, deduplicates, and appends to the list.
    /// Sets `hasMore` to `false` on error to prevent infinite retry loops.
    private func loadMorePage(
        into list: inout [PersistentArticle],
        hasMore: inout Bool,
        fetch: (_ offset: Int, _ limit: Int) throws -> [PersistentArticle],
        label: String
    ) {
        guard hasMore else { return }
        do {
            let page = try fetch(list.count, Self.pageSize)
            let existingIDs = Set(list.map(\.articleID))
            let newItems = page.filter { !existingIDs.contains($0.articleID) }
            list.append(contentsOf: newItems)
            hasMore = page.count == Self.pageSize
            let totalCount = list.count
            Self.logger.debug("Loaded page of \(page.count, privacy: .public) \(label, privacy: .public) (\(newItems.count, privacy: .public) new, total: \(totalCount, privacy: .public))")
        } catch {
            hasMore = false
            errorMessage = "Unable to load \(label)."
            Self.logger.error("Failed to load \(label) page: \(error, privacy: .public)")
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
