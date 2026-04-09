import os
import SwiftUI

/// Typed navigation destination for push navigation to settings.
/// Both `HomeView` and `FeedListView` register `.navigationDestination(for:)`
/// handlers for this type — `HomeView` handles it when `FeedListView` is
/// embedded, and `FeedListView` handles it when it owns its own `NavigationStack`.
enum SettingsDestination: Hashable {
    case settings
}

struct FeedListView: View {
    private static let logger = Logger(category: "FeedListView")

    @State private var viewModel: FeedListViewModel
    @State private var homeViewModel: HomeViewModel
    @State private var navigationPath = NavigationPath()
    @State private var showAddFeed = false
    @State private var feedToEdit: PersistentFeed?

    private let persistence: FeedPersisting
    private let refreshService: FeedRefreshService
    private let feedIconService: FeedIconResolving
    private let thumbnailService: ArticleThumbnailCaching = ArticleThumbnailService()
    private let isEmbedded: Bool

    /// Creates a feed list view.
    /// - Parameters:
    ///   - persistence: The persistence service for feed data.
    ///   - refreshService: The shared feed refresh service. Callers should pass
    ///     the app-wide instance so foreground and background refreshes share
    ///     in-flight state.
    ///   - feedIconService: The shared feed icon service. Callers should pass
    ///     the app-wide instance so refresh writes and UI reads share the cache.
    ///   - isEmbedded: When `true`, omits the wrapping `NavigationStack` so this view
    ///     can be pushed inside a parent stack (e.g., from `HomeView`). Defaults to `false`.
    ///   - homeViewModel: The home view model for badge updates in settings. When nil
    ///     (standalone mode), a minimal instance is created internally.
    init(
        persistence: FeedPersisting,
        refreshService: FeedRefreshService,
        feedIconService: FeedIconResolving,
        isEmbedded: Bool = false,
        homeViewModel: HomeViewModel? = nil
    ) {
        self.persistence = persistence
        self.refreshService = refreshService
        self.feedIconService = feedIconService
        self.isEmbedded = isEmbedded
        _viewModel = State(initialValue: FeedListViewModel(
            persistence: persistence,
            refreshService: refreshService,
            feedIconService: feedIconService
        ))
        _homeViewModel = State(initialValue: homeViewModel ?? HomeViewModel(persistence: persistence))
    }

    var body: some View {
        if isEmbedded {
            feedListContent
        } else {
            NavigationStack(path: $navigationPath) {
                feedListContent
                    .navigationDestination(for: SettingsDestination.self) { destination in
                        switch destination {
                        case .settings:
                            SettingsView(
                                persistence: persistence,
                                viewModel: viewModel,
                                homeViewModel: homeViewModel
                            )
                        }
                    }
            }
        }
    }

    @ViewBuilder
    private var feedListContent: some View {
        feedContent
            .navigationTitle("Feeds")
            .navigationDestination(for: PersistentFeed.ID.self) { feedID in
                if let feed = viewModel.feeds.first(where: { $0.id == feedID }) {
                    ArticleListView(
                        viewModel: FeedViewModel(feed: feed, persistence: persistence),
                        persistence: persistence,
                        thumbnailService: thumbnailService
                    )
                    .onDisappear { viewModel.refreshUnreadCount(for: feed) }
                } else {
                    let _ = Self.logger.warning("Feed not found for navigated ID: \(feedID)")
                    ContentUnavailableView {
                        Label("Feed Not Found", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text("This feed is no longer available.")
                    }
                }
            }
            .toolbar { toolbarItems }
            .sheet(isPresented: $showAddFeed, onDismiss: {
                viewModel.loadFeeds()
            }) {
                AddFeedView(persistence: persistence)
            }
            .sheet(item: $feedToEdit, onDismiss: {
                viewModel.loadFeeds()
            }) { feed in
                EditFeedView(feed: feed, persistence: persistence)
            }
            .alert("Error", isPresented: errorAlertBinding) {
                Button("OK") { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
            .task {
                viewModel.loadFeeds()
            }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var feedContent: some View {
        if viewModel.feeds.isEmpty {
            ContentUnavailableView {
                Label("No Feeds", systemImage: "plus.circle")
            } description: {
                Text("Add an RSS feed to get started.")
            } actions: {
                Button("Add Feed") {
                    showAddFeed = true
                }
                .buttonStyle(.bordered)
            }
        } else {
            List {
                ForEach(viewModel.feeds, id: \.id) { feed in
                    NavigationLink(value: feed.id) {
                        FeedRowView(
                            feed: feed,
                            unreadCount: viewModel.unreadCount(for: feed),
                            iconService: viewModel.feedIconService
                        )
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            feedToEdit = feed
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .tint(.blue)
                    }
                }
                .onDelete { offsets in
                    viewModel.removeFeed(at: offsets)
                }
            }
            .listStyle(.plain)
            .refreshable {
                await viewModel.refreshAllFeeds()
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                showAddFeed = true
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel("Add Feed")
        }
        if !isEmbedded {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(value: SettingsDestination.settings) {
                    Image(systemName: "gear")
                }
                .accessibilityLabel("Settings")
            }
        }
    }

    // MARK: - Helpers

    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )
    }
}
