import Foundation
import os

@MainActor
@Observable
final class FeedViewModel {

    private static let logger = Logger(category: "FeedViewModel")

    /// Number of articles to fetch per page.
    static let pageSize = 50

    var articles: [PersistentArticle] = []
    var feedTitle: String = "Feed"
    var isLoading = false
    var errorMessage: String?
    private(set) var hasMoreArticles = true

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

        // Show first page of cached articles immediately (cache-first loading for offline support)
        do {
            let cached = try persistence.articles(for: feed, offset: 0, limit: Self.pageSize)
            if !cached.isEmpty {
                articles = cached
                hasMoreArticles = cached.count == Self.pageSize
            }
        } catch {
            Self.logger.warning("Failed to load cached articles for '\(self.feed.title, privacy: .public)': \(error, privacy: .public)")
        }

        isLoading = articles.isEmpty
        errorMessage = nil
        defer { isLoading = false }

        do {
            let result = try await feedFetching.fetchFeed(
                from: feed.feedURL,
                etag: feed.etag,
                lastModified: feed.lastModifiedHeader
            )
            if let result {
                feedTitle = result.feed.title
                try persistence.upsertArticles(result.feed.articles, for: feed)
                try persistence.updateFeedCacheHeaders(feed, etag: result.etag, lastModified: result.lastModified)
                try persistence.save()
                // Reload up to current scroll depth so the user doesn't lose their position
                let reloadLimit = max(articles.count, Self.pageSize)
                articles = try persistence.articles(for: feed, offset: 0, limit: reloadLimit)
                hasMoreArticles = articles.count == reloadLimit
                Self.logger.notice("Feed loaded: \(self.articles.count, privacy: .public) articles (reload limit: \(reloadLimit, privacy: .public))")
            } else {
                Self.logger.debug("Feed unchanged (304) for '\(self.feed.title, privacy: .public)'")
            }
        } catch {
            if articles.isEmpty {
                errorMessage = error.localizedDescription
            }
            Self.logger.error("Feed load failed: \(error, privacy: .public)")
        }
    }

    /// Loads the next page of articles and appends to the existing list.
    func loadMoreArticles() {
        guard hasMoreArticles else { return }
        do {
            let page = try persistence.articles(
                for: feed,
                offset: articles.count,
                limit: Self.pageSize
            )
            let existingIDs = Set(articles.map(\.articleID))
            let newItems = page.filter { !existingIDs.contains($0.articleID) }
            articles.append(contentsOf: newItems)
            hasMoreArticles = page.count == Self.pageSize
            Self.logger.debug("Loaded page of \(page.count, privacy: .public) articles for feed (\(newItems.count, privacy: .public) new, total: \(self.articles.count, privacy: .public))")
        } catch {
            hasMoreArticles = false
            errorMessage = "Unable to load more articles."
            Self.logger.error("Failed to load articles page: \(error, privacy: .public)")
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
