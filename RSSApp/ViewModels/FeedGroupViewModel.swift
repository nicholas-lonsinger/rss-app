import Foundation
import os

/// Per-group state management for the group article list. Analogous to
/// `FeedViewModel` for individual feeds: owns pagination state and mutation
/// methods. `FeedGroupArticleSource` wraps this as the `ArticleListSource`
/// adapter consumed by `ArticleListScreen`.
///
/// Refresh is NOT managed here — the group source delegates to
/// `HomeViewModel.refreshAllFeeds()` for network work, then calls
/// `loadArticles()` to re-query the local store.
@MainActor
@Observable
final class FeedGroupViewModel {

    private static let logger = Logger(category: "FeedGroupViewModel")

    /// Number of articles to fetch per page.
    static let pageSize = 50

    let group: PersistentFeedGroup
    private let persistence: FeedPersisting

    private(set) var articles: [PersistentArticle] = []
    private(set) var hasMore = true
    var errorMessage: String?

    /// Current sort order — reads from the global UserDefaults preference.
    /// The setter triggers a reload so the list reflects the new order
    /// immediately, matching `FeedViewModel.sortAscending`'s behavior.
    var sortAscending: Bool {
        get { UserDefaults.standard.bool(forKey: FeedViewModel.sortAscendingKey) }
        set {
            guard UserDefaults.standard.bool(forKey: FeedViewModel.sortAscendingKey) != newValue else { return }
            UserDefaults.standard.set(newValue, forKey: FeedViewModel.sortAscendingKey)
            Self.logger.debug("sortAscending changed to \(newValue, privacy: .public)")
            loadArticles()
        }
    }

    var groupTitle: String { group.name }

    init(group: PersistentFeedGroup, persistence: FeedPersisting) {
        self.group = group
        self.persistence = persistence
    }

    // MARK: - Loading

    /// Resets pagination and loads the first page of articles for this group.
    /// On failure, preserves the previously loaded list to avoid flashing an empty state.
    func loadArticles() {
        let previous = articles
        articles = []
        hasMore = true
        loadMoreArticles()
        if articles.isEmpty && errorMessage != nil {
            articles = previous
        }
    }

    /// Loads the next page of articles and appends to the existing list.
    @discardableResult
    func loadMoreArticles() -> LoadMoreResult {
        guard hasMore else { return .exhausted }
        let ascending = sortAscending
        do {
            let page = try persistence.articlesInGroup(
                group,
                offset: articles.count,
                limit: Self.pageSize,
                ascending: ascending
            )
            let existingIDs = Set(articles.map(\.articleID))
            let newItems = page.filter { !existingIDs.contains($0.articleID) }
            articles.append(contentsOf: newItems)
            hasMore = page.count == Self.pageSize
            Self.logger.debug("Loaded page of \(page.count, privacy: .public) articles in group '\(self.group.name, privacy: .public)' (\(newItems.count, privacy: .public) new, total: \(self.articles.count, privacy: .public))")
            return newItems.isEmpty ? .exhausted : .loaded
        } catch {
            let message = "Unable to load articles."
            errorMessage = message
            Self.logger.error("Failed to load articles in group '\(self.group.name, privacy: .public)': \(error, privacy: .public)")
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

    // MARK: - Mutations (snapshot-stable)

    @discardableResult
    func markAsRead(_ article: PersistentArticle) -> Bool {
        guard !article.isRead else { return true }
        do {
            try persistence.markArticleRead(article, isRead: true)
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
        } catch {
            errorMessage = "Unable to update read status."
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

    /// Marks all articles in this group as read. Snapshot-stable — row visuals
    /// update via `@Observable` propagation but list composition is preserved.
    func markAllAsRead() {
        do {
            try persistence.markAllArticlesRead(inGroup: group)
            Self.logger.notice("Marked all articles as read in group '\(self.group.name, privacy: .public)'")
        } catch {
            errorMessage = "Unable to mark all articles as read."
            Self.logger.error("Failed to mark all articles as read in group '\(self.group.name, privacy: .public)': \(error, privacy: .public)")
        }
    }

    func clearError() {
        errorMessage = nil
    }
}
