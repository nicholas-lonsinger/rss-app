import Foundation
import os

@MainActor
@Observable
final class FeedViewModel {

    private static let logger = Logger(category: "FeedViewModel")

    /// UserDefaults key for the global sort order preference.
    static let sortAscendingKey = "articleSortAscending"

    /// Number of articles to fetch per page.
    static let pageSize = 50

    var articles: [PersistentArticle] = []
    var feedTitle: String = "Feed"
    var isLoading = false
    var errorMessage: String?
    private(set) var hasMoreArticles = true

    /// When `true`, only unread articles are shown. Only used in `ArticleListView` (per-feed).
    var showUnreadOnly = false {
        didSet {
            guard oldValue != showUnreadOnly else { return }
            Self.logger.debug("showUnreadOnly changed to \(self.showUnreadOnly, privacy: .public)")
            reloadArticles()
        }
    }

    /// Current sort order — reads from the global UserDefaults preference.
    var sortAscending: Bool {
        get { UserDefaults.standard.bool(forKey: Self.sortAscendingKey) }
        set {
            guard UserDefaults.standard.bool(forKey: Self.sortAscendingKey) != newValue else { return }
            UserDefaults.standard.set(newValue, forKey: Self.sortAscendingKey)
            Self.logger.debug("sortAscending changed to \(newValue, privacy: .public)")
            reloadArticles()
        }
    }

    private let feedFetching: FeedFetching
    private let persistence: FeedPersisting
    let feed: PersistentFeed

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

        let ascending = sortAscending

        // Show first page of cached articles immediately (cache-first loading for offline support)
        do {
            let cached = try fetchCurrentPage(offset: 0, limit: Self.pageSize, ascending: ascending)
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
                articles = try fetchCurrentPage(offset: 0, limit: reloadLimit, ascending: ascending)
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
            let page = try fetchCurrentPage(
                offset: articles.count,
                limit: Self.pageSize,
                ascending: sortAscending
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

    /// Marks all articles in this feed as read.
    func markAllAsRead() {
        do {
            try persistence.markAllArticlesRead(for: feed)
            reloadArticles()
            Self.logger.notice("Marked all articles as read for '\(self.feed.title, privacy: .public)'")
        } catch {
            errorMessage = "Unable to mark all articles as read."
            Self.logger.error("Failed to mark all articles as read: \(error, privacy: .public)")
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

    // MARK: - Private Helpers

    /// Reloads the article list from the beginning, preserving the current display depth.
    private func reloadArticles() {
        let reloadLimit = max(articles.count, Self.pageSize)
        do {
            articles = try fetchCurrentPage(offset: 0, limit: reloadLimit, ascending: sortAscending)
            hasMoreArticles = articles.count == reloadLimit
        } catch {
            errorMessage = "Unable to reload articles."
            Self.logger.error("Failed to reload articles: \(error, privacy: .public)")
        }
    }

    /// Fetches a page of articles respecting the current filter mode (all or unread only).
    private func fetchCurrentPage(offset: Int, limit: Int, ascending: Bool) throws -> [PersistentArticle] {
        if showUnreadOnly {
            return try persistence.unreadArticles(for: feed, offset: offset, limit: limit, ascending: ascending)
        } else {
            return try persistence.articles(for: feed, offset: offset, limit: limit, ascending: ascending)
        }
    }
}
