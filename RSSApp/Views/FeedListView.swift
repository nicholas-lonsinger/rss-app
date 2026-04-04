import SwiftUI

struct FeedListView: View {
    @State private var viewModel: FeedListViewModel
    @State private var navigationPath = NavigationPath()
    @State private var showAddFeed = false
    @State private var feedToEdit: PersistentFeed?
    @State private var lastViewedFeedID: PersistentFeed.ID?

    private let persistence: FeedPersisting
    private let thumbnailService: ArticleThumbnailCaching = ArticleThumbnailService()
    private let isEmbedded: Bool

    /// Creates a feed list view.
    /// - Parameters:
    ///   - persistence: The persistence service for feed data.
    ///   - isEmbedded: When `true`, omits the wrapping `NavigationStack` so this view
    ///     can be pushed inside a parent stack (e.g., from `HomeView`). Defaults to `false`.
    init(persistence: FeedPersisting, isEmbedded: Bool = false) {
        self.persistence = persistence
        self.isEmbedded = isEmbedded
        _viewModel = State(initialValue: FeedListViewModel(persistence: persistence))
    }

    var body: some View {
        if isEmbedded {
            feedListContent
        } else {
            NavigationStack(path: $navigationPath) {
                feedListContent
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
                    .onAppear { lastViewedFeedID = feedID }
                } else {
                    ContentUnavailableView {
                        Label("Feed Not Found", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text("This feed is no longer available.")
                    }
                }
            }
            .navigationDestination(for: SettingsDestination.self) { destination in
                switch destination {
                case .settings:
                    SettingsView(persistence: persistence, viewModel: viewModel)
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
            .onChange(of: navigationPath.count) { oldCount, newCount in
                if newCount < oldCount,
                   let feedID = lastViewedFeedID,
                   let feed = viewModel.feeds.first(where: { $0.id == feedID }) {
                    viewModel.refreshUnreadCount(for: feed)
                }
            }
    }

    // MARK: - Navigation Destinations

    /// Typed navigation destinations for push navigation within the feed list NavigationStack.
    private enum SettingsDestination: Hashable {
        case settings
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
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                navigationPath.append(SettingsDestination.settings)
            } label: {
                Image(systemName: "gear")
            }
            .accessibilityLabel("Settings")
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
