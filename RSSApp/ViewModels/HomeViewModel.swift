import Foundation
import os

@MainActor
@Observable
final class HomeViewModel {

    private static let logger = Logger(category: "HomeViewModel")

    /// Number of articles to fetch per page.
    static let pageSize = 50

    private(set) var unreadCount: Int = 0
    private(set) var errorMessage: String?

    // MARK: - Pagination state for all articles

    private(set) var allArticlesList: [PersistentArticle] = []
    private(set) var hasMoreAllArticles = true

    // MARK: - Pagination state for unread articles

    private(set) var unreadArticlesList: [PersistentArticle] = []
    private(set) var hasMoreUnreadArticles = true

    private let persistence: FeedPersisting

    init(persistence: FeedPersisting) {
        self.persistence = persistence
    }

    func clearError() {
        errorMessage = nil
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
        guard hasMoreAllArticles else { return }
        do {
            let page = try persistence.allArticles(
                offset: allArticlesList.count,
                limit: Self.pageSize
            )
            let existingIDs = Set(allArticlesList.map(\.articleID))
            let newItems = page.filter { !existingIDs.contains($0.articleID) }
            allArticlesList.append(contentsOf: newItems)
            hasMoreAllArticles = page.count == Self.pageSize
            Self.logger.debug("Loaded page of \(page.count, privacy: .public) all articles (\(newItems.count, privacy: .public) new, total: \(self.allArticlesList.count, privacy: .public))")
        } catch {
            hasMoreAllArticles = false
            errorMessage = "Unable to load all articles."
            Self.logger.error("Failed to load all articles page: \(error, privacy: .public)")
        }
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
        guard hasMoreUnreadArticles else { return }
        do {
            let page = try persistence.allUnreadArticles(
                offset: unreadArticlesList.count,
                limit: Self.pageSize
            )
            let existingIDs = Set(unreadArticlesList.map(\.articleID))
            let newItems = page.filter { !existingIDs.contains($0.articleID) }
            unreadArticlesList.append(contentsOf: newItems)
            hasMoreUnreadArticles = page.count == Self.pageSize
            Self.logger.debug("Loaded page of \(page.count, privacy: .public) unread articles (\(newItems.count, privacy: .public) new, total: \(self.unreadArticlesList.count, privacy: .public))")
        } catch {
            hasMoreUnreadArticles = false
            errorMessage = "Unable to load unread articles."
            Self.logger.error("Failed to load unread articles page: \(error, privacy: .public)")
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
