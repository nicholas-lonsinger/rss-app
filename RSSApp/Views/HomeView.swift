import SwiftUI

/// Lightweight navigation value for user-created feed groups. Uses the
/// group's UUID rather than the `PersistentFeedGroup` model directly to
/// avoid SwiftData identity issues in `NavigationLink(value:)`.
struct GroupDestination: Hashable, Identifiable {
    let groupID: UUID
    var id: UUID { groupID }
}

struct HomeView: View {

    @Environment(\.scenePhase) private var scenePhase
    @State private var viewModel: HomeViewModel
    @State private var feedListViewModel: FeedListViewModel
    private let persistence: FeedPersisting
    private let refreshService: FeedRefreshService
    private let feedIconService: FeedIconResolving

    // MARK: - Group CRUD state

    @State private var showAddFeed = false
    @State private var showCreateGroup = false
    @State private var newGroupName = ""
    @State private var groupToEdit: PersistentFeedGroup?
    @State private var groupToDelete: PersistentFeedGroup?

    init(
        persistence: FeedPersisting,
        refreshService: FeedRefreshService,
        feedIconService: FeedIconResolving
    ) {
        self.persistence = persistence
        self.refreshService = refreshService
        self.feedIconService = feedIconService
        let feedListVM = FeedListViewModel(
            persistence: persistence,
            refreshService: refreshService,
            feedIconService: feedIconService
        )
        _feedListViewModel = State(initialValue: feedListVM)
        _viewModel = State(initialValue: HomeViewModel(
            persistence: persistence,
            refreshFeeds: { [feedListVM] in
                await feedListVM.refreshAllFeeds()
                return await feedListVM.errorMessage
            }
        ))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(HomeGroup.allCases) { group in
                        NavigationLink(value: group) {
                            HomeRowView(
                                title: group.title,
                                systemImage: group.systemImage,
                                badgeCount: badgeCount(for: group),
                                showErrorIndicator: showErrorIndicator(for: group)
                            )
                        }
                    }
                }

                if !viewModel.groups.isEmpty {
                    Section {
                        ForEach(viewModel.groups, id: \.id) { group in
                            NavigationLink(value: GroupDestination(groupID: group.id)) {
                                HomeRowView(
                                    title: group.name,
                                    systemImage: "folder",
                                    badgeCount: groupBadgeCount(for: group)
                                )
                            }
                            .swipeActions(edge: .leading) {
                                Button {
                                    groupToEdit = group
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .tint(.blue)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    groupToDelete = group
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                        .onMove { source, destination in
                            viewModel.moveGroup(from: source, to: destination)
                        }
                    } header: {
                        Text("Groups")
                    }
                }
            }
            .listStyle(.plain)
            .refreshable {
                await viewModel.refreshAllFeeds()
                viewModel.loadUnreadCount()
                viewModel.loadGroupUnreadCounts()
            }
            .navigationTitle("Home")
            .navigationDestination(for: HomeGroup.self) { group in
                switch group {
                case .allArticles:
                    ArticleListScreen(
                        source: AllArticlesSource(homeViewModel: viewModel),
                        persistence: persistence
                    )
                case .unreadArticles:
                    ArticleListScreen(
                        source: UnreadArticlesSource(homeViewModel: viewModel),
                        persistence: persistence
                    )
                case .savedArticles:
                    ArticleListScreen(
                        source: SavedArticlesSource(homeViewModel: viewModel),
                        persistence: persistence
                    )
                case .allFeeds:
                    FeedListView(
                        persistence: persistence,
                        refreshService: refreshService,
                        feedIconService: feedIconService,
                        isEmbedded: true,
                        homeViewModel: viewModel
                    )
                }
            }
            .navigationDestination(for: GroupDestination.self) { destination in
                if let group = viewModel.groups.first(where: { $0.id == destination.groupID }) {
                    ArticleListScreen(
                        source: GroupArticleSource(
                            group: group,
                            persistence: persistence,
                            homeViewModel: viewModel
                        ),
                        persistence: persistence
                    )
                } else {
                    ContentUnavailableView {
                        Label("Group Not Found", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text("This group is no longer available.")
                    }
                }
            }
            .navigationDestination(for: SettingsDestination.self) { destination in
                switch destination {
                case .settings:
                    SettingsView(
                        persistence: persistence,
                        viewModel: feedListViewModel,
                        homeViewModel: viewModel
                    )
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showAddFeed = true
                        } label: {
                            Label("Add Feed", systemImage: "plus")
                        }
                        Button {
                            showCreateGroup = true
                        } label: {
                            Label("New Group", systemImage: "folder.badge.plus")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(value: SettingsDestination.settings) {
                        Image(systemName: "gear")
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .task {
                viewModel.loadUnreadCount()
                viewModel.loadGroups()
                feedListViewModel.loadFeeds()
            }
            .alert("Error", isPresented: errorAlertBinding) {
                Button("OK") { viewModel.clearError() }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
            .alert("New Group", isPresented: $showCreateGroup) {
                TextField("Group name", text: $newGroupName)
                Button("Create") {
                    let name = newGroupName.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !name.isEmpty {
                        viewModel.addGroup(name: name)
                    }
                    newGroupName = ""
                }
                Button("Cancel", role: .cancel) {
                    newGroupName = ""
                }
            }
            .alert(
                "Delete Group?",
                isPresented: Binding(
                    get: { groupToDelete != nil },
                    set: { if !$0 { groupToDelete = nil } }
                ),
                presenting: groupToDelete
            ) { group in
                Button("Delete", role: .destructive) {
                    viewModel.deleteGroup(group)
                }
                Button("Cancel", role: .cancel) { }
            } message: { group in
                Text("\"\(group.name)\" will be deleted. Its feeds will not be removed.")
            }
            .sheet(isPresented: $showAddFeed, onDismiss: {
                feedListViewModel.loadFeeds()
            }) {
                AddFeedView(persistence: persistence)
            }
            .sheet(item: $groupToEdit, onDismiss: {
                viewModel.loadGroups()
            }) { group in
                EditGroupView(group: group, persistence: persistence)
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    viewModel.loadUnreadCount()
                    viewModel.loadGroupUnreadCounts()
                    // Re-check network allowance on foreground so that a network
                    // change (WiFi → cellular) or setting change that occurred
                    // while the app was backgrounded cancels any still-suspended
                    // download tasks before they resume.
                    refreshService.cancelBackgroundDownloadTasksIfDisallowed()
                }
            }
        }
    }

    // MARK: - Helpers

    // RATIONALE: `Binding(presentingIfNonNil:)` is not used here because
    // dismissal must call `viewModel.clearError()` rather than nil the optional
    // directly — `clearError()` performs additional side-effect cleanup beyond
    // setting `errorMessage = nil`.
    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.clearError() } }
        )
    }

    private func badgeCount(for group: HomeGroup) -> Int? {
        switch group {
        case .unreadArticles:
            return viewModel.unreadCount
        case .savedArticles, .allArticles, .allFeeds:
            return nil
        }
    }

    /// Returns `true` when the All Feeds row should show the
    /// `exclamationmark.triangle.fill` indicator — i.e., at least one feed has
    /// had a failure streak exceeding `FeedRefreshService.bubbleUpThreshold`
    /// (24 hours). Other rows never show this indicator.
    private func showErrorIndicator(for group: HomeGroup) -> Bool {
        switch group {
        case .allFeeds:
            return viewModel.hasFeedsWithLongRunningFailure
        case .allArticles, .unreadArticles, .savedArticles:
            return false
        }
    }

    private func groupBadgeCount(for group: PersistentFeedGroup) -> Int? {
        let count = viewModel.groupUnreadCounts[group.id] ?? 0
        return count > 0 ? count : nil
    }
}

// MARK: - Home Row

private struct HomeRowView: View {

    let title: String
    let systemImage: String
    /// `nil` means this row type never shows a badge (e.g. All Articles, All Feeds),
    /// which is distinct from a zero unread count where the badge is simply hidden.
    let badgeCount: Int?
    var showErrorIndicator: Bool = false

    var body: some View {
        HStack {
            Label(title, systemImage: systemImage)
                .font(.headline)

            Spacer()

            if showErrorIndicator {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            if let count = badgeCount {
                BadgeView(count: count)
            }
        }
        .padding(.vertical, 4)
    }
}
