import Foundation
import os

/// `ArticleListSource` for a user-created feed group. Queries articles
/// from all feeds in the group via `FeedPersisting` and delegates
/// cross-cutting concerns (network refresh, badge updates, mutations)
/// to `HomeViewModel`.
///
/// Owns its own pagination state — unlike the built-in cross-feed sources
/// (All/Unread/Saved) which share state on `HomeViewModel`, each group
/// gets an independent list because there can be N groups with independent
/// navigation lifecycles.
@MainActor
@Observable
final class GroupArticleSource: ArticleListSource {

    private static let logger = Logger(category: "GroupArticleSource")

    private let group: PersistentFeedGroup
    private let persistence: FeedPersisting
    private let homeViewModel: HomeViewModel
    private let userDefaults: UserDefaults

    private(set) var articles: [PersistentArticle] = []
    private(set) var hasMore = true
    var isLoading: Bool { homeViewModel.isRefreshing }
    private(set) var errorMessage: String?

    var title: String { group.name }
    var emptyState: EmptyStateContent {
        EmptyStateContent(
            label: "No Articles",
            systemImage: "folder",
            description: "Add feeds to this group to see their articles here."
        )
    }
    var supportsSort: Bool { true }
    var supportsUnreadFilter: Bool { true }

    // RATIONALE: sortAscending delegates to homeViewModel.sortAscending, which is itself
    // backed by Settings.UserDefaultsKeys.sortAscending. @Observable does not track
    // UserDefaults reads automatically; UI correctness is preserved because the setter
    // calls reloadArticles(), which mutates the tracked `articles` array and drives SwiftUI
    // updates.
    var sortAscending: Bool {
        get { homeViewModel.sortAscending }
        set {
            homeViewModel.sortAscending = newValue
            reloadArticles()
        }
    }

    // RATIONALE: showUnreadOnly is backed by Settings.UserDefaultsKeys.showUnreadOnly, the
    // same global key used by FeedViewModel.showUnreadOnly, so the toggle state is shared
    // across all feed and group article lists. @Observable does not track UserDefaults reads
    // automatically; UI correctness is preserved because the setter calls reloadArticles(),
    // which mutates the tracked `articles` array and drives SwiftUI updates.
    var showUnreadOnly: Bool {
        get { userDefaults.bool(forKey: Settings.UserDefaultsKeys.showUnreadOnly) }
        set {
            guard userDefaults.bool(forKey: Settings.UserDefaultsKeys.showUnreadOnly) != newValue else { return }
            userDefaults.set(newValue, forKey: Settings.UserDefaultsKeys.showUnreadOnly)
            Self.logger.debug("showUnreadOnly changed to \(newValue, privacy: .public)")
            reloadArticles()
        }
    }

    init(
        group: PersistentFeedGroup,
        persistence: FeedPersisting,
        homeViewModel: HomeViewModel,
        userDefaults: UserDefaults = .standard
    ) {
        self.group = group
        self.persistence = persistence
        self.homeViewModel = homeViewModel
        self.userDefaults = userDefaults
    }

    // MARK: - Lifecycle

    func initialLoad() async {
        loadArticles()
        if homeViewModel.shouldRefreshOnEntry {
            await homeViewModel.refreshAllFeeds()
            loadArticles()
        }
        homeViewModel.loadUnreadCount()
    }

    func refresh() async {
        await homeViewModel.refreshAllFeeds()
        loadArticles()
        homeViewModel.loadUnreadCount()
    }

    func reload() {
        loadArticles()
    }

    // MARK: - Pagination

    func loadMoreAndReport() -> LoadMoreResult {
        let result = loadMore()
        if case .failed = result {
            errorMessage = nil
        }
        return result
    }

    // MARK: - Mutations (snapshot-stable)

    @discardableResult
    func markAsRead(_ article: PersistentArticle) -> Bool {
        homeViewModel.markAsRead(article)
    }

    func toggleReadStatus(_ article: PersistentArticle) {
        homeViewModel.toggleReadStatus(article)
    }

    func toggleSaved(_ article: PersistentArticle) {
        homeViewModel.toggleSaved(article)
    }

    func markAllAsRead() {
        homeViewModel.markAllArticlesReadInGroup(group)
    }

    func onDisappear() {
        homeViewModel.loadUnreadCount()
        homeViewModel.loadGroupUnreadCounts()
    }

    func clearError() {
        errorMessage = nil
    }

    // MARK: - Private

    /// Cursor tracking the last article in the current snapshot for efficient
    /// cursor-based pagination. Reset to `nil` on full reload (sort change,
    /// refresh) so the first page re-fetches from the start.
    private var paginationCursor: ArticlePaginationCursor?

    /// Reloads the article list from the beginning, preserving the current display depth.
    /// Fetches `max(articles.count, pageSize)` articles from the start in a single call so
    /// the user stays near their current scroll position after toggling sort or filter —
    /// mirroring the behavior of `FeedViewModel.reloadArticles()`.
    private func reloadArticles() {
        let reloadLimit = max(articles.count, HomeViewModel.pageSize)
        let ascending = sortAscending
        let unreadOnly = showUnreadOnly
        do {
            let page = try unreadOnly
                ? persistence.unreadArticles(
                    in: group,
                    cursor: nil,
                    limit: reloadLimit,
                    ascending: ascending
                )
                : persistence.articles(
                    in: group,
                    cursor: nil,
                    limit: reloadLimit,
                    ascending: ascending
                )
            articles = page
            paginationCursor = page.last.map(ArticlePaginationCursor.init)
            hasMore = page.count == reloadLimit
            Self.logger.debug("Reloaded \(page.count, privacy: .public) articles for group '\(self.group.name, privacy: .public)' (limit: \(reloadLimit, privacy: .public))")
        } catch {
            errorMessage = "Unable to reload articles."
            Self.logger.error("Failed to reload articles for group '\(self.group.name, privacy: .public)': \(error, privacy: .public)")
        }
    }

    private func loadArticles() {
        let previous = articles
        let previousCursor = paginationCursor
        let previousHasMore = hasMore
        articles = []
        paginationCursor = nil
        hasMore = true
        loadMore()
        if articles.isEmpty && errorMessage != nil {
            articles = previous
            paginationCursor = previousCursor
            hasMore = previousHasMore
        }
    }

    @discardableResult
    private func loadMore() -> LoadMoreResult {
        guard hasMore else { return .exhausted }
        let ascending = sortAscending
        let unreadOnly = showUnreadOnly
        do {
            let page = try unreadOnly
                ? persistence.unreadArticles(
                    in: group,
                    cursor: paginationCursor,
                    limit: HomeViewModel.pageSize,
                    ascending: ascending
                )
                : persistence.articles(
                    in: group,
                    cursor: paginationCursor,
                    limit: HomeViewModel.pageSize,
                    ascending: ascending
                )
            let existingIDs = Set(articles.map(\.articleID))
            let newItems = page.filter { !existingIDs.contains($0.articleID) }
            articles.append(contentsOf: newItems)
            hasMore = page.count == HomeViewModel.pageSize

            // Advance the cursor to the last article in the page for the next fetch.
            if let last = page.last {
                paginationCursor = ArticlePaginationCursor(after: last)
            }

            Self.logger.debug("Loaded \(page.count, privacy: .public) articles for group '\(self.group.name, privacy: .public)' (\(newItems.count, privacy: .public) new, total: \(self.articles.count, privacy: .public))")
            return newItems.isEmpty ? .exhausted : .loaded
        } catch {
            let message = "Unable to load articles."
            errorMessage = message
            Self.logger.error("Failed to load articles for group '\(self.group.name, privacy: .public)': \(error, privacy: .public)")
            return .failed(message)
        }
    }
}
