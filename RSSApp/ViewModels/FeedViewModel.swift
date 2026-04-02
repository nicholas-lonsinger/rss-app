import Foundation
import os

@MainActor
@Observable
final class FeedViewModel {

    private static let logger = Logger(
        subsystem: "com.nicholas-lonsinger.rss-app",
        category: "FeedViewModel"
    )

    var articles: [PersistentArticle] = []
    var feedTitle: String = "Feed"
    var isLoading = false
    var errorMessage: String?

    private let feedFetching: FeedFetching
    private let persistence: FeedPersisting
    private let feed: PersistentFeed

    init(
        feed: PersistentFeed,
        feedFetching: FeedFetching = FeedFetchingService(),
        persistence: FeedPersisting
    ) {
        self.feed = feed
        self.feedFetching = feedFetching
        self.persistence = persistence
        self.feedTitle = feed.title
    }

    func loadFeed() async {
        Self.logger.debug("loadFeed() called for '\(self.feed.title, privacy: .public)'")

        // Show cached articles immediately (cache-first loading for offline support)
        do {
            let cached = try persistence.articles(for: feed)
            if !cached.isEmpty {
                articles = cached
            }
        } catch {
            Self.logger.warning("Failed to load cached articles for '\(self.feed.title, privacy: .public)': \(error, privacy: .public)")
        }

        isLoading = articles.isEmpty
        errorMessage = nil
        defer { isLoading = false }

        do {
            let rssFeed = try await feedFetching.fetchFeed(from: feed.feedURL)
            feedTitle = rssFeed.title
            try persistence.upsertArticles(rssFeed.articles, for: feed)
            try persistence.save()
            articles = try persistence.articles(for: feed)
            Self.logger.notice("Feed loaded: \(self.articles.count, privacy: .public) articles")
        } catch {
            if articles.isEmpty {
                errorMessage = error.localizedDescription
            }
            Self.logger.error("Feed load failed: \(error, privacy: .public)")
        }
    }

    func markAsRead(_ article: PersistentArticle) {
        guard !article.isRead else { return }
        do {
            try persistence.markArticleRead(article, isRead: true)
        } catch {
            errorMessage = "Unable to save read status."
            Self.logger.error("Failed to mark article as read: \(error, privacy: .public)")
        }
    }

    func toggleReadStatus(_ article: PersistentArticle) {
        do {
            try persistence.markArticleRead(article, isRead: !article.isRead)
        } catch {
            errorMessage = "Unable to save read status."
            Self.logger.error("Failed to toggle read status: \(error, privacy: .public)")
        }
    }
}
