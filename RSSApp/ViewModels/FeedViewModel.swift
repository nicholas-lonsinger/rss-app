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

    // RATIONALE: showUnreadOnly is a computed property backed by UserDefaults, so @Observable
    // does not track it automatically. UI correctness is preserved because the setter calls
    // reloadArticles(), which mutates the tracked `articles` array and drives SwiftUI updates.
    // The global key ensures all feed and group lists share a single persistent toggle state.
    /// Whether to show only unread articles. Reads and writes the global unread-only
    /// filter preference via the injected `UserDefaults` instance. Shared across all
    /// feed and group article lists. Setting the value also calls `reloadArticles()`
    /// to refresh the current list immediately.
    var showUnreadOnly: Bool {
        get { userDefaults.bool(forKey: Settings.UserDefaultsKeys.showUnreadOnly) }
        set {
            guard userDefaults.bool(forKey: Settings.UserDefaultsKeys.showUnreadOnly) != newValue else { return }
            userDefaults.set(newValue, forKey: Settings.UserDefaultsKeys.showUnreadOnly)
            Self.logger.debug("showUnreadOnly changed to \(newValue, privacy: .public)")
            reloadArticles()
        }
    }

    // RATIONALE: sortAscending is a computed property backed by UserDefaults, so @Observable
    // does not track it automatically. UI correctness is preserved because the setter calls
    // reloadArticles(), which mutates the tracked `articles` array and drives SwiftUI updates.
    // A Toggle bound to this property works fine: the setter fires on user interaction, and
    // the resulting articles mutation triggers the necessary re-render.
    /// Current sort order — reads from the injected UserDefaults instance.
    var sortAscending: Bool {
        get { userDefaults.bool(forKey: Settings.UserDefaultsKeys.sortAscending) }
        set {
            guard userDefaults.bool(forKey: Settings.UserDefaultsKeys.sortAscending) != newValue else { return }
            userDefaults.set(newValue, forKey: Settings.UserDefaultsKeys.sortAscending)
            Self.logger.debug("sortAscending changed to \(newValue, privacy: .public)")
            reloadArticles()
        }
    }

    private let feedFetching: FeedFetching
    private let persistence: FeedPersisting
    private let userDefaults: UserDefaults
    let feed: PersistentFeed

    init(
        feed: PersistentFeed,
        feedFetching: FeedFetching = FeedFetchingService(),
        persistence: FeedPersisting,
        userDefaults: UserDefaults = .standard
    ) {
        self.feed = feed
        self.feedFetching = feedFetching
        self.persistence = persistence
        self.userDefaults = userDefaults
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
    @discardableResult
    func loadMoreArticles() -> LoadMoreResult {
        guard hasMoreArticles else { return .exhausted }
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
            return newItems.isEmpty ? .exhausted : .loaded
        } catch {
            // RATIONALE: hasMoreArticles is intentionally NOT set to false on error.
            // Pagination errors are transient (database hiccups, etc.) and the user
            // should be able to retry by tapping next again. The error is surfaced via
            // LoadMoreResult.failed so the caller can display an alert.
            let message = "Unable to load more articles."
            errorMessage = message
            Self.logger.error("Failed to load articles page: \(error, privacy: .public)")
            return .failed(message)
        }
    }

    /// Loads the next page and returns the outcome, clearing `errorMessage` on failure
    /// so only the caller (article reader) displays the error — not the list view's alert.
    func loadMoreAndReport() -> LoadMoreResult {
        let result = loadMoreArticles()
        if case .failed = result {
            errorMessage = nil
        }
        return result
    }

    /// Marks the article as read and returns `true` on success (or if the article
    /// was already read), `false` on persistence failure. Callers gate reader
    /// navigation on this return value so an open-on-row-tap never pushes the
    /// reader when the mark did not actually persist.
    @discardableResult
    func markAsRead(_ article: PersistentArticle) -> Bool {
        guard !article.isRead else { return true }
        do {
            try persistence.markArticleRead(article, isRead: true)
            return true
        } catch {
            errorMessage = "Unable to save read status."
            Self.logger.error("Failed to mark article as read: \(error, privacy: .public)")
            return false
        }
    }

    /// Marks all articles in this feed as read. Does NOT re-query the list —
    /// per the snapshot-stable rule, bulk mutations update row visuals through
    /// `@Observable` propagation but leave list composition and order intact.
    /// Under `showUnreadOnly`, the just-read rows remain visible until the user
    /// triggers an explicit refresh (pull-to-refresh, sort/filter toggle, or a
    /// fresh re-entry into the view).
    func markAllAsRead() {
        do {
            try persistence.markAllArticlesRead(for: feed)
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

    func toggleSaved(_ article: PersistentArticle) {
        do {
            try persistence.toggleArticleSaved(article)
        } catch {
            errorMessage = "Unable to update saved status."
            Self.logger.error("Failed to toggle saved status: \(error, privacy: .public)")
        }
    }

    // MARK: - Reload

    /// Reloads the article list from the beginning, preserving the current display depth.
    /// Called on explicit triggers: sort/filter change, mark all as read, navigation return.
    func reloadArticles() {
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
