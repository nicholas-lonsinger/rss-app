import Foundation
import Observation

// MARK: - Per-Feed Source

/// `ArticleListSource` adapter for a single feed. Wraps an existing
/// `FeedViewModel` so `ArticleListScreen` can drive the per-feed article list
/// without caring that it's per-feed vs cross-feed. All state lives on the
/// underlying `FeedViewModel` — this adapter is a pure projection so its
/// properties trigger SwiftUI observation through the view model's registrar.
@MainActor
@Observable
final class FeedArticleSource: ArticleListSource {

    private let viewModel: FeedViewModel

    init(viewModel: FeedViewModel) {
        self.viewModel = viewModel
    }

    // MARK: Data

    var articles: [PersistentArticle] { viewModel.articles }
    var hasMore: Bool { viewModel.hasMoreArticles }
    var isLoading: Bool { viewModel.isLoading }
    var errorMessage: String? { viewModel.errorMessage }

    // MARK: Display

    var title: String { viewModel.feedTitle }
    var emptyState: EmptyStateContent {
        EmptyStateContent(
            label: "No Articles",
            systemImage: "doc.text",
            description: "This feed has no articles yet."
        )
    }
    var supportsSort: Bool { true }
    var supportsUnreadFilter: Bool { true }

    // MARK: Filter/sort

    var sortAscending: Bool {
        get { viewModel.sortAscending }
        set { viewModel.sortAscending = newValue }
    }
    var showUnreadOnly: Bool {
        get { viewModel.showUnreadOnly }
        set { viewModel.showUnreadOnly = newValue }
    }

    // MARK: Lifecycle

    func initialLoad() async {
        // `FeedViewModel.loadFeed()` already implements the cache-first +
        // network fetch + reload pattern, so a single call satisfies the
        // `initialLoad` contract. Spinner state is tracked by the view
        // model's `isLoading` flag, which the shared view reads via
        // `source.isLoading`.
        await viewModel.loadFeed()
    }

    func refresh() async {
        await viewModel.loadFeed()
    }

    func reload() {
        viewModel.reloadArticles()
    }

    // MARK: Pagination

    func loadMoreAndReport() -> LoadMoreResult {
        viewModel.loadMoreAndReport()
    }

    // MARK: Mutations (snapshot-stable)

    @discardableResult
    func markAsRead(_ article: PersistentArticle) -> Bool {
        viewModel.markAsRead(article)
    }

    func toggleReadStatus(_ article: PersistentArticle) {
        viewModel.toggleReadStatus(article)
    }

    func toggleSaved(_ article: PersistentArticle) {
        viewModel.toggleSaved(article)
    }

    func markAllAsRead() {
        viewModel.markAllAsRead()
    }

    // MARK: Errors

    func clearError() {
        viewModel.errorMessage = nil
    }
}

// MARK: - All Articles Source

/// Cross-feed source showing every article across every feed. Wraps the
/// `allArticlesList` slice of `HomeViewModel` and delegates refresh to the
/// shared `FeedRefreshService` via `HomeViewModel.refreshAllFeeds()`.
@MainActor
@Observable
final class AllArticlesSource: ArticleListSource {

    private let homeViewModel: HomeViewModel

    init(homeViewModel: HomeViewModel) {
        self.homeViewModel = homeViewModel
    }

    var articles: [PersistentArticle] { homeViewModel.allArticlesList }
    var hasMore: Bool { homeViewModel.hasMoreAllArticles }
    // Cross-feed lists have no dedicated "loading" flag — the only non-
    // instant work is the network refresh during `initialLoad`, so we
    // surface the shared refresh guard as the source's loading state.
    var isLoading: Bool { homeViewModel.isRefreshing }
    var errorMessage: String? { homeViewModel.errorMessage }

    var title: String { "All Articles" }
    var emptyState: EmptyStateContent {
        EmptyStateContent(
            label: "No Articles",
            systemImage: "doc.text",
            description: "Articles from your feeds will appear here."
        )
    }
    var supportsSort: Bool { true }
    var supportsUnreadFilter: Bool { false }

    var sortAscending: Bool {
        get { homeViewModel.sortAscending }
        set {
            homeViewModel.sortAscending = newValue
            homeViewModel.loadAllArticles()
        }
    }
    // Unread-only filter is not supported on the All Articles list — the
    // Unread list is a separate destination.
    var showUnreadOnly: Bool {
        get { false }
        set { /* no-op */ }
    }

    func initialLoad() async {
        // Cache-first: render whatever is already in SwiftData immediately
        // so the user sees content even if the network is slow or offline.
        homeViewModel.loadAllArticles()
        // Throttled network refresh. `HomeViewModel.shouldRefreshOnEntry`
        // reads the last-refresh timestamp from the injected UserDefaults
        // instance and returns `false` when the most recent refresh is
        // within `entryRefreshInterval` — so rapid navigation across sibling
        // cross-feed views (or a BG refresh that ran moments ago) doesn't
        // stack redundant refreshes on every entry. Pull-to-refresh goes
        // through `refresh()` below and bypasses the throttle entirely.
        if homeViewModel.shouldRefreshOnEntry {
            await homeViewModel.refreshAllFeeds()
            // Pick up any new rows the refresh persisted.
            homeViewModel.loadAllArticles()
        }
        homeViewModel.loadUnreadCount()
    }

    func refresh() async {
        // Pull-to-refresh is explicit user intent — always hit the network.
        await homeViewModel.refreshAllFeeds()
        homeViewModel.loadAllArticles()
        homeViewModel.loadUnreadCount()
    }

    func reload() {
        homeViewModel.loadAllArticles()
    }

    func loadMoreAndReport() -> LoadMoreResult {
        homeViewModel.loadMoreAllArticlesAndReport()
    }

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
        homeViewModel.markAllAsRead()
    }

    func onDisappear() {
        homeViewModel.loadUnreadCount()
    }

    func clearError() {
        homeViewModel.clearError()
    }
}

// MARK: - Unread Articles Source

/// Cross-feed source filtered to unread articles across all feeds. Shares the
/// snapshot-stable semantics with every other list: marking an article read
/// (via row tap, swipe, or reader) updates the row's `isRead` visual but
/// does NOT remove it from this list until the user triggers a refresh.
@MainActor
@Observable
final class UnreadArticlesSource: ArticleListSource {

    private let homeViewModel: HomeViewModel

    init(homeViewModel: HomeViewModel) {
        self.homeViewModel = homeViewModel
    }

    var articles: [PersistentArticle] { homeViewModel.unreadArticlesList }
    var hasMore: Bool { homeViewModel.hasMoreUnreadArticles }
    var isLoading: Bool { homeViewModel.isRefreshing }
    var errorMessage: String? { homeViewModel.errorMessage }

    var title: String { "Unread Articles" }
    var emptyState: EmptyStateContent {
        EmptyStateContent(
            label: "All Caught Up",
            systemImage: "checkmark.circle",
            description: "You have no unread articles."
        )
    }
    var supportsSort: Bool { true }
    var supportsUnreadFilter: Bool { false }

    var sortAscending: Bool {
        get { homeViewModel.sortAscending }
        set {
            homeViewModel.sortAscending = newValue
            homeViewModel.loadUnreadArticles()
        }
    }
    var showUnreadOnly: Bool {
        get { false }
        set { /* no-op — the list is already unread-only by definition */ }
    }

    func initialLoad() async {
        homeViewModel.loadUnreadArticles()
        if homeViewModel.shouldRefreshOnEntry {
            await homeViewModel.refreshAllFeeds()
            homeViewModel.loadUnreadArticles()
        }
        homeViewModel.loadUnreadCount()
    }

    func refresh() async {
        await homeViewModel.refreshAllFeeds()
        homeViewModel.loadUnreadArticles()
        homeViewModel.loadUnreadCount()
    }

    func reload() {
        homeViewModel.loadUnreadArticles()
    }

    func loadMoreAndReport() -> LoadMoreResult {
        homeViewModel.loadMoreUnreadArticlesAndReport()
    }

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
        homeViewModel.markAllAsRead()
    }

    func onDisappear() {
        homeViewModel.loadUnreadCount()
    }

    func clearError() {
        homeViewModel.clearError()
    }
}

// MARK: - Saved Articles Source

/// Cross-feed source filtered to saved / bookmarked articles. Honors the
/// same global `sortAscending` preference as the other cross-feed lists —
/// sort key is `sortDate`, not `savedDate`, for cross-feed consistency.
@MainActor
@Observable
final class SavedArticlesSource: ArticleListSource {

    private let homeViewModel: HomeViewModel

    init(homeViewModel: HomeViewModel) {
        self.homeViewModel = homeViewModel
    }

    var articles: [PersistentArticle] { homeViewModel.savedArticlesList }
    var hasMore: Bool { homeViewModel.hasMoreSavedArticles }
    var isLoading: Bool { homeViewModel.isRefreshing }
    var errorMessage: String? { homeViewModel.errorMessage }

    var title: String { "Saved Articles" }
    var emptyState: EmptyStateContent {
        EmptyStateContent(
            label: "No Saved Articles",
            systemImage: "bookmark",
            description: "Saved articles will appear here."
        )
    }
    var supportsSort: Bool { true }
    var supportsUnreadFilter: Bool { false }

    var sortAscending: Bool {
        get { homeViewModel.sortAscending }
        set {
            homeViewModel.sortAscending = newValue
            homeViewModel.loadSavedArticles()
        }
    }
    var showUnreadOnly: Bool {
        get { false }
        set { /* no-op */ }
    }

    // Saved articles never benefit from a feed refresh — the items are
    // already in SwiftData and only change via user action (saving/unsaving).
    // Neither `initialLoad()` nor `refresh()` triggers a network refresh.
    // Pull-to-refresh on this list just re-queries the local store, which is
    // useful for seeing unsaved rows drop off after the user has unsaved them
    // under the snapshot-stable rule.

    func initialLoad() async {
        homeViewModel.loadSavedArticles()
    }

    func refresh() async {
        homeViewModel.loadSavedArticles()
    }

    func reload() {
        homeViewModel.loadSavedArticles()
    }

    func loadMoreAndReport() -> LoadMoreResult {
        homeViewModel.loadMoreSavedArticlesAndReport()
    }

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

    /// Scoped to saved articles only — calls the dedicated
    /// `markAllSavedArticlesRead()` persistence path rather than the global
    /// `markAllArticlesRead()`. Previously this would mark every article in
    /// every feed as read when the user tapped "Mark All as Read" from the
    /// Saved list, which was not what the affordance implies.
    func markAllAsRead() {
        homeViewModel.markAllSavedArticlesRead()
    }

    func clearError() {
        homeViewModel.clearError()
    }
}
