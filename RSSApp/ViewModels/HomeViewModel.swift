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

    private let persistence: FeedPersisting

    /// Async closure that performs the actual network feed refresh.
    /// Injected by the parent view to delegate to `FeedListViewModel.refreshAllFeeds()`.
    private let refreshFeeds: (@Sendable () async -> Void)?

    init(persistence: FeedPersisting, refreshFeeds: (@Sendable () async -> Void)? = nil) {
        self.persistence = persistence
        self.refreshFeeds = refreshFeeds
    }

    func clearError() {
        errorMessage = nil
    }

    // MARK: - Refresh

    /// Triggers a full network refresh of all feeds, then reloads local data.
    /// When no refresh closure is configured, this is a no-op.
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
        isRefreshing = true
        defer { isRefreshing = false }

        await refreshFeeds()

        loadUnreadCount()
        Self.logger.notice("refreshAllFeeds() completed, unread count updated")
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
        loadMorePage(
            into: &allArticlesList,
            hasMore: &hasMoreAllArticles,
            fetch: { offset, limit in try self.persistence.allArticles(offset: offset, limit: limit) },
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
        loadMorePage(
            into: &unreadArticlesList,
            hasMore: &hasMoreUnreadArticles,
            fetch: { offset, limit in try self.persistence.allUnreadArticles(offset: offset, limit: limit) },
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

    /// Removes a specific article from the unread articles list (e.g., after marking it read).
    func removeFromUnreadList(_ article: PersistentArticle) {
        unreadArticlesList.removeAll { $0.articleID == article.articleID }
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
}
