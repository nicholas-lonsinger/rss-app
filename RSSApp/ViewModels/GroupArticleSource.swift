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
    var supportsUnreadFilter: Bool { false }

    // MARK: - Group editing capability

    var supportsGroupEdit: Bool { true }
    var editableGroup: PersistentFeedGroup? { group }
    private(set) var wasGroupDeleted: Bool = false
    private(set) var deleteErrorMessage: String?

    func deleteGroup() {
        let name = group.name
        do {
            try persistence.deleteGroup(group)
            homeViewModel.loadGroups()
            wasGroupDeleted = true
            Self.logger.notice("Deleted group '\(name, privacy: .public)' from GroupArticleSource")
        } catch {
            deleteErrorMessage = "Unable to delete group."
            Self.logger.error("Failed to delete group '\(name, privacy: .public)': \(error, privacy: .public)")
        }
    }

    var sortAscending: Bool {
        get { homeViewModel.sortAscending }
        set {
            homeViewModel.sortAscending = newValue
            loadArticles()
        }
    }
    var showUnreadOnly: Bool {
        get { false }
        set { /* no-op — not supported for group lists */ }
    }

    init(
        group: PersistentFeedGroup,
        persistence: FeedPersisting,
        homeViewModel: HomeViewModel
    ) {
        self.group = group
        self.persistence = persistence
        self.homeViewModel = homeViewModel
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

    private func loadArticles() {
        let previous = articles
        articles = []
        hasMore = true
        loadMore()
        if articles.isEmpty && errorMessage != nil {
            articles = previous
        }
    }

    @discardableResult
    private func loadMore() -> LoadMoreResult {
        guard hasMore else { return .exhausted }
        let ascending = sortAscending
        do {
            let page = try persistence.articles(
                in: group,
                offset: articles.count,
                limit: HomeViewModel.pageSize,
                ascending: ascending
            )
            let existingIDs = Set(articles.map(\.articleID))
            let newItems = page.filter { !existingIDs.contains($0.articleID) }
            articles.append(contentsOf: newItems)
            hasMore = page.count == HomeViewModel.pageSize
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
