import Foundation
import Observation

/// Display content for an article list's empty state. Each `ArticleListSource`
/// supplies its own so the shared view can render per-screen copy (e.g.
/// "All Caught Up" for Unread vs "No Saved Articles" for Saved) without
/// hardcoding variants into `ArticleListScreen`.
struct EmptyStateContent: Sendable, Equatable {
    let label: String
    let systemImage: String
    let description: String
}

/// Data-and-behavior seam between `ArticleListScreen` and the various
/// concrete article lists in the app (per-feed, All, Unread, Saved, and
/// user-created feed groups).
///
/// `ArticleListScreen` is generic over this protocol and renders the list,
/// toolbar, swipe actions, pagination trigger, empty/error/loading states,
/// and the two-gate snapshot preservation (#209). Sources own: data (the
/// current `articles` snapshot), configuration (title, empty state, which
/// toolbar capabilities to expose), and the mutation/lifecycle hooks the
/// shared view invokes.
///
/// The protocol is deliberately shaped around the **snapshot-stable rule**:
/// per-item and bulk mutations (`markAsRead`, `toggleReadStatus`,
/// `toggleSaved`, `markAllAsRead`) update row visuals through observation
/// propagation but never change list composition or order. Only
/// `initialLoad`, `refresh`, and `reload` re-query the underlying store;
/// toggling `sortAscending` or `showUnreadOnly` triggers a re-query — either
/// via the backing view model's `didSet` (`FeedViewModel`) or via the
/// adapter's setter calling the appropriate reload method (cross-feed sources).
///
/// Conforming types should be `@MainActor @Observable` classes so that
/// SwiftUI's body re-invocation picks up changes to any property the view
/// reads — even computed properties that forward to another `@Observable`
/// (e.g. `HomeViewModel`) work, because `withObservationTracking` registers
/// accesses on the backing class's registrar regardless of which adapter
/// the accessor goes through.
@MainActor
protocol ArticleListSource: AnyObject, Observable {

    // MARK: - Data

    /// Current snapshot of articles. Mutations (mark read, toggle saved) do
    /// NOT change this array — rows update visuals via `@Observable`
    /// propagation on the underlying `PersistentArticle` references.
    var articles: [PersistentArticle] { get }

    /// Whether more pages are available after `articles.count`.
    var hasMore: Bool { get }

    /// Whether a load is currently in progress. Drives the "loading" UI in
    /// `ArticleListScreen`: a spinner when `articles.isEmpty && isLoading`,
    /// hidden otherwise. For per-feed sources this reflects `loadFeed()`;
    /// for cross-feed sources it reflects the process-wide refresh guard.
    var isLoading: Bool { get }

    /// Current error message, if any. Cleared by `clearError()` or by a
    /// successful subsequent `initialLoad` / `refresh` / `reload`.
    var errorMessage: String? { get }

    // MARK: - Display configuration

    /// Navigation bar title.
    var title: String { get }

    /// Content shown when `articles` is empty and not loading.
    var emptyState: EmptyStateContent { get }

    /// Whether the toolbar should expose a sort-order toggle. Today every
    /// source returns `true` — the Saved list honors the same global
    /// `sortAscending` preference as the other lists. Future sources with
    /// semantically fixed ordering could return `false`.
    var supportsSort: Bool { get }

    /// Whether the toolbar should expose a "Show Unread Only" toggle. Only
    /// per-feed sources return `true` today — the cross-feed Unread list is
    /// a separate destination so this toggle is redundant there.
    var supportsUnreadFilter: Bool { get }

    // MARK: - Filter/sort (explicit list-level actions — DO re-query)

    /// Sort order for the article list. Conformers MUST trigger a reload of
    /// `articles` within the setter (either via the backing view model's
    /// `didSet` or by calling the appropriate load method explicitly) so the
    /// list reflects the new order immediately — `ArticleListScreen` does
    /// not call `reload()` after toggling this property.
    var sortAscending: Bool { get set }
    var showUnreadOnly: Bool { get set }

    // MARK: - Lifecycle (re-query allowed)

    /// Called once per view identity from `ArticleListScreen`'s `.task`,
    /// gated by the `hasAppeared` snapshot-preservation flag so it only fires
    /// on fresh entry into the view (not on reader pop). Implementations
    /// should follow the cache-first + network-refresh + reload pattern:
    ///
    ///  1. Render the first page from the local store immediately.
    ///  2. `await` a network refresh that populates the store.
    ///  3. Re-query the local snapshot so the UI picks up new rows.
    ///
    /// The shared view sets `hasAppeared = true` *before* awaiting this
    /// call — see `ArticleListScreen` for the ordering rationale.
    func initialLoad() async

    /// Called from pull-to-refresh. Typically delegates to the same work as
    /// `initialLoad` but without the first cache-render step.
    func refresh() async

    /// Called on non-reader re-entry (e.g. navigating back to this view
    /// from a parent screen). Synchronous local re-query only — network
    /// work belongs to `refresh()`.
    func reload()

    // MARK: - Pagination (extends snapshot, doesn't re-query)

    /// Loads the next page. Returns `.loaded` / `.exhausted` / `.failed` so
    /// the shared view and the article reader can react accordingly. Uses
    /// the "AndReport" variant semantics: on failure, the error is returned
    /// via the result *and* the source's `errorMessage` is cleared, so only
    /// the reader's alert surfaces the error (not the list's).
    func loadMoreAndReport() -> LoadMoreResult

    // MARK: - Mutations — snapshot-stable, NEVER re-query

    /// Marks the article as read and returns `true` on success (including
    /// the already-read no-op path), `false` on persistence failure. The
    /// shared view gates the reader push on this return value so an open-
    /// on-row-tap never pushes the reader if the mark did not persist.
    @discardableResult
    func markAsRead(_ article: PersistentArticle) -> Bool

    func toggleReadStatus(_ article: PersistentArticle)
    func toggleSaved(_ article: PersistentArticle)
    func markAllAsRead()

    // MARK: - Disappear

    /// Called when the list view disappears. Cross-feed sources use this to
    /// refresh Home badge counts (unread / saved) so the Home screen
    /// reflects any mutations made during the session. Default is a no-op.
    func onDisappear()

    // MARK: - Error dismissal

    func clearError()
}

extension ArticleListSource {
    func onDisappear() {}
}
