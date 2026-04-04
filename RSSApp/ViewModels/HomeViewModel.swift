import Foundation
import os

@MainActor
@Observable
final class HomeViewModel {

    private static let logger = Logger(category: "HomeViewModel")

    private(set) var unreadCount: Int = 0
    var errorMessage: String?

    private let persistence: FeedPersisting

    init(persistence: FeedPersisting) {
        self.persistence = persistence
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
            errorMessage = "Unable to load articles."
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
            errorMessage = "Unable to load articles."
            Self.logger.error("Failed to load unread articles: \(error, privacy: .public)")
            return []
        }
    }

    func markAsRead(_ article: PersistentArticle) {
        guard !article.isRead else { return }
        do {
            try persistence.markArticleRead(article, isRead: true)
            loadUnreadCount()
        } catch {
            errorMessage = "Unable to save read status."
            Self.logger.error("Failed to mark article as read: \(error, privacy: .public)")
        }
    }

    func toggleReadStatus(_ article: PersistentArticle) {
        do {
            try persistence.markArticleRead(article, isRead: !article.isRead)
            loadUnreadCount()
        } catch {
            errorMessage = "Unable to save read status."
            Self.logger.error("Failed to toggle read status: \(error, privacy: .public)")
        }
    }
}
