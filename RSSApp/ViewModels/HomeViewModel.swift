import Foundation
import os

@MainActor
@Observable
final class HomeViewModel {

    private static let logger = Logger(category: "HomeViewModel")

    private(set) var unreadCount: Int = 0
    private(set) var errorMessage: String?

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

    func allArticles() -> [PersistentArticle] {
        do {
            let articles = try persistence.allArticles()
            Self.logger.debug("Loaded \(articles.count, privacy: .public) total articles")
            return articles
        } catch {
            errorMessage = "Unable to load all articles."
            Self.logger.error("Failed to load all articles: \(error, privacy: .public)")
            return []
        }
    }

    func unreadArticles() -> [PersistentArticle] {
        do {
            let articles = try persistence.allUnreadArticles()
            Self.logger.debug("Loaded \(articles.count, privacy: .public) unread articles")
            return articles
        } catch {
            errorMessage = "Unable to load unread articles."
            Self.logger.error("Failed to load unread articles: \(error, privacy: .public)")
            return []
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
}
