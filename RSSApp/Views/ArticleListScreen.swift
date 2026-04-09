import SwiftUI

/// Single shared implementation of every article list in the app. Generic
/// over `ArticleListSource` so the per-feed, All Articles, Unread Articles,
/// and Saved Articles screens (and future feed-group and label variants) all
/// flow through one view. Source-specific behavior is injected via the
/// `source` — the screen itself contains zero list-specific logic.
///
/// **Snapshot-stable rule** — row mutations (mark read, toggle saved) only
/// update the row's visuals via `@Observable` propagation; the list's
/// composition and order are preserved until the user triggers an explicit
/// refresh (pull-to-refresh, sort/filter toggle, or a fresh re-entry from a
/// parent screen). Reader push/pop is explicitly NOT an explicit refresh — it
/// is gated by the two-gate `hasAppeared` + `returningFromReader` mechanism
/// documented below and in ARCHITECTURE.md.
struct ArticleListScreen<Source: ArticleListSource>: View {

    let source: Source
    let persistence: FeedPersisting
    let thumbnailService: ArticleThumbnailCaching

    init(
        source: Source,
        persistence: FeedPersisting,
        thumbnailService: ArticleThumbnailCaching = ArticleThumbnailService()
    ) {
        self.source = source
        self.persistence = persistence
        self.thumbnailService = thumbnailService
    }

    @Environment(\.dismiss) private var dismiss

    @State private var selectedArticleIndex: Int?
    @State private var showMarkAllReadConfirmation = false
    @State private var showEditGroupSheet = false
    @State private var showDeleteGroupConfirmation = false
    @State private var hasAppeared = false
    // RATIONALE: Snapshot preservation across reader push/pop. See
    // ARCHITECTURE.md → "Snapshot preservation across reader push/pop (two gates)".
    // Both gates (this flag and the `hasAppeared` flag above) are required —
    // removing either reopens #209. Centralized here so every list destination
    // in the app — per-feed, All, Unread, Saved, and future feed-group/label
    // variants — gets the preservation for free.
    @State private var returningFromReader = false

    var body: some View {
        // A single `List` container for every state — loading, happy-empty,
        // error-empty, and content — so `.refreshable` has a consistent
        // scrollable target to attach to. The old per-destination views put
        // `.refreshable` inside a conditional `else` branch around the List,
        // which made pull-to-refresh unreachable whenever the list was empty
        // or errored out. Unifying the container fixes that gap for every
        // source.
        List {
            if source.articles.isEmpty && source.isLoading {
                loadingRow
            } else if source.articles.isEmpty, let errorMessage = source.errorMessage {
                errorEmptyRow(message: errorMessage)
            } else if source.articles.isEmpty {
                happyEmptyRow
            } else {
                contentRows
            }
        }
        .listStyle(.plain)
        .refreshable {
            await source.refresh()
        }
        .navigationTitle(source.title)
        .toolbar { toolbarContent }
        .confirmationDialog(
            "Mark all articles as read?",
            isPresented: $showMarkAllReadConfirmation,
            titleVisibility: .visible
        ) {
            Button("Mark All as Read", role: .destructive) {
                source.markAllAsRead()
            }
        }
        .navigationDestination(item: $selectedArticleIndex) { index in
            ArticleReaderView(
                persistence: persistence,
                articles: source.articles,
                initialIndex: index,
                loadMore: source.hasMore ? { source.loadMoreAndReport() } : nil
            )
        }
        .alert("Error", isPresented: errorAlertBinding) {
            Button("OK") { source.clearError() }
        } message: {
            Text(source.errorMessage ?? "")
        }
        .alert(
            "Delete Group?",
            isPresented: $showDeleteGroupConfirmation,
            presenting: source.editableGroup
        ) { group in
            Button("Delete", role: .destructive) {
                source.deleteGroup()
            }
            Button("Cancel", role: .cancel) { }
        } message: { group in
            Text("\"\(group.name)\" will be deleted. Its feeds will not be removed.")
        }
        .sheet(isPresented: $showEditGroupSheet) {
            if let group = source.editableGroup {
                EditGroupView(group: group, persistence: persistence)
            }
        }
        .onChange(of: source.wasGroupDeleted) { _, deleted in
            if deleted {
                dismiss()
            }
        }
        .task {
            // RATIONALE: First half of the two-gate snapshot-preservation
            // mechanism. `hasAppeared = true` MUST be set BEFORE awaiting
            // `source.initialLoad()`: SwiftUI cancels `.task` on disappear,
            // so if the user taps an article during the initial network
            // fetch, setting the flag after the await would leave it false
            // and the post-pop re-run would fire a fresh `initialLoad()` —
            // reproducing #209. Setting it first means a cancelled `.task`
            // still leaves `hasAppeared = true`, so the post-pop re-run is
            // gated and the snapshot is preserved.
            guard !hasAppeared else { return }
            hasAppeared = true
            await source.initialLoad()
        }
        .onAppear {
            // Second gate: on the post-pop `.onAppear`, consume the
            // `returningFromReader` flag (armed in the row-tap handler just
            // before the push) and skip the reload. Non-reader re-appears
            // (e.g. returning to this view from a parent) still re-query
            // via `source.reload()`.
            guard hasAppeared else { return }
            if returningFromReader {
                returningFromReader = false
                return
            }
            source.reload()
        }
        .onDisappear {
            source.onDisappear()
        }
    }

    // MARK: - State Rows

    private var loadingRow: some View {
        HStack {
            Spacer()
            ProgressView("Loading\u{2026}")
                .padding(.vertical, 40)
            Spacer()
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private func errorEmptyRow(message: String) -> some View {
        VStack {
            Spacer(minLength: 40)
            ContentUnavailableView {
                Label("Unable to Load", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Retry") {
                    Task { await source.refresh() }
                }
                .buttonStyle(.bordered)
            }
            Spacer(minLength: 40)
        }
        .frame(maxWidth: .infinity)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private var happyEmptyRow: some View {
        VStack {
            Spacer(minLength: 40)
            ContentUnavailableView {
                Label(source.emptyState.label, systemImage: source.emptyState.systemImage)
            } description: {
                Text(source.emptyState.description)
            }
            Spacer(minLength: 40)
        }
        .frame(maxWidth: .infinity)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    // MARK: - Content Rows

    @ViewBuilder
    private var contentRows: some View {
        ForEach(Array(source.articles.enumerated()), id: \.element.articleID) { index, article in
            Button {
                // Gate the reader push on `markAsRead` success. A persistence
                // failure keeps the user on the list with an error alert
                // instead of opening a reader for an article whose read state
                // was not actually persisted.
                guard source.markAsRead(article) else { return }
                returningFromReader = true
                selectedArticleIndex = index
            } label: {
                ArticleRowView(
                    article: article,
                    thumbnailService: thumbnailService
                )
            }
            .buttonStyle(.plain)
            .disabled(article.link == nil)
            .listRowInsets(EdgeInsets(top: 10, leading: 20, bottom: 10, trailing: 20))
            .swipeActions(edge: .leading) {
                Button {
                    source.toggleReadStatus(article)
                } label: {
                    Label(
                        article.isRead ? "Unread" : "Read",
                        systemImage: article.isRead ? "envelope.badge" : "envelope.open"
                    )
                }
                .tint(article.isRead ? .blue : .gray)
            }
            .swipeActions(edge: .trailing) {
                // Snapshot-stable rule: toggling saved state updates the row's
                // visual flag but does NOT drop the row from the list. The
                // just-unsaved row remains visible in the Saved list until the
                // user triggers an explicit refresh.
                Button {
                    source.toggleSaved(article)
                } label: {
                    Label(
                        article.isSaved ? "Unsave" : "Save",
                        systemImage: article.isSaved ? "bookmark.slash" : "bookmark"
                    )
                }
                .tint(.orange)
            }
            .onAppear {
                if article.articleID == source.articles.last?.articleID {
                    _ = source.loadMoreAndReport()
                }
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                if source.supportsSort {
                    Button {
                        source.sortAscending.toggle()
                    } label: {
                        Label(
                            source.sortAscending ? "Newest First" : "Oldest First",
                            systemImage: source.sortAscending ? "arrow.down" : "arrow.up"
                        )
                    }
                }

                if source.supportsUnreadFilter {
                    Button {
                        source.showUnreadOnly.toggle()
                    } label: {
                        Label(
                            source.showUnreadOnly ? "Show All Articles" : "Show Unread Only",
                            systemImage: source.showUnreadOnly ? "envelope.open" : "envelope.badge"
                        )
                    }
                }

                if source.supportsSort || source.supportsUnreadFilter {
                    Divider()
                }

                Button(role: .destructive) {
                    showMarkAllReadConfirmation = true
                } label: {
                    Label("Mark All as Read", systemImage: "checkmark.circle")
                }

                if source.supportsGroupEdit {
                    Divider()

                    Button {
                        showEditGroupSheet = true
                    } label: {
                        Label("Edit Group", systemImage: "pencil")
                    }

                    Button(role: .destructive) {
                        showDeleteGroupConfirmation = true
                    } label: {
                        Label("Delete Group", systemImage: "trash")
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }

    // MARK: - Helpers

    /// The alert is only shown when there are articles to return to — when
    /// the list is empty, the error goes to the `errorEmptyRow` with its
    /// Retry button instead, so the two presentations don't race.
    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { source.errorMessage != nil && !source.articles.isEmpty },
            set: { if !$0 { source.clearError() } }
        )
    }
}
