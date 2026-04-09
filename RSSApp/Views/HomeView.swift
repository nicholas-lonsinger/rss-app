import SwiftUI

struct HomeView: View {

    @Environment(\.scenePhase) private var scenePhase
    @State private var viewModel: HomeViewModel
    @State private var feedListViewModel: FeedListViewModel
    private let persistence: FeedPersisting
    private let refreshService: FeedRefreshService
    private let feedIconService: FeedIconResolving

    // MARK: - Group CRUD state

    @State private var showNewGroupAlert = false
    @State private var newGroupName = ""
    @State private var groupToRename: PersistentFeedGroup?
    @State private var renameText = ""
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

    // MARK: - Computed items

    private static let fixedTopItems: [HomeGroup] = [
        .allArticles, .unreadArticles, .savedArticles
    ]

    private var homeItems: [HomeGroup] {
        Self.fixedTopItems
        + viewModel.groups.map { .feedGroup($0) }
        + [.allFeeds]
    }

    var body: some View {
        NavigationStack {
            List {
                // Fixed top items
                ForEach(Self.fixedTopItems) { group in
                    NavigationLink(value: group) {
                        HomeRowView(group: group, badgeCount: badgeCount(for: group))
                    }
                }

                // User-created groups
                if !viewModel.groups.isEmpty {
                    Section {
                        ForEach(viewModel.groups, id: \.id) { group in
                            let homeGroup = HomeGroup.feedGroup(group)
                            NavigationLink(value: homeGroup) {
                                HomeRowView(group: homeGroup, badgeCount: badgeCount(for: homeGroup))
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    if group.feeds.isEmpty {
                                        viewModel.deleteGroup(group)
                                    } else {
                                        groupToDelete = group
                                    }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .swipeActions(edge: .leading) {
                                Button {
                                    renameText = group.name
                                    groupToRename = group
                                } label: {
                                    Label("Rename", systemImage: "pencil")
                                }
                                .tint(.blue)
                            }
                            .contextMenu {
                                Button {
                                    renameText = group.name
                                    groupToRename = group
                                } label: {
                                    Label("Rename", systemImage: "pencil")
                                }
                                Button(role: .destructive) {
                                    if group.feeds.isEmpty {
                                        viewModel.deleteGroup(group)
                                    } else {
                                        groupToDelete = group
                                    }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                        .onMove { from, to in
                            viewModel.moveGroup(from: from, to: to)
                        }
                    } header: {
                        Text("Groups")
                    }
                }

                // All Feeds (always at bottom)
                NavigationLink(value: HomeGroup.allFeeds) {
                    HomeRowView(group: .allFeeds, badgeCount: nil)
                }
            }
            .listStyle(.plain)
            .refreshable {
                await viewModel.refreshAllFeeds()
                viewModel.loadUnreadCount()
                viewModel.loadSavedCount()
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
                case .feedGroup(let feedGroup):
                    ArticleListScreen(
                        source: FeedGroupArticleSource(
                            groupViewModel: FeedGroupViewModel(
                                group: feedGroup,
                                persistence: persistence
                            ),
                            homeViewModel: viewModel
                        ),
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
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            newGroupName = ""
                            showNewGroupAlert = true
                        } label: {
                            Label("New Group", systemImage: "folder.badge.plus")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    NavigationLink(value: SettingsDestination.settings) {
                        Image(systemName: "gear")
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .task {
                viewModel.loadUnreadCount()
                viewModel.loadSavedCount()
                viewModel.loadGroups()
                viewModel.loadGroupUnreadCounts()
                feedListViewModel.loadFeeds()
            }
            .alert("Error", isPresented: errorAlertBinding) {
                Button("OK") { viewModel.clearError() }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
            .alert("New Group", isPresented: $showNewGroupAlert) {
                TextField("Group name", text: $newGroupName)
                Button("Cancel", role: .cancel) { }
                Button("Create") {
                    let name = newGroupName.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !name.isEmpty {
                        viewModel.addGroup(name: name)
                        viewModel.loadGroupUnreadCounts()
                    }
                }
            } message: {
                Text("Enter a name for the new group.")
            }
            .alert("Rename Group", isPresented: Binding(
                get: { groupToRename != nil },
                set: { if !$0 { groupToRename = nil } }
            )) {
                TextField("Group name", text: $renameText)
                Button("Cancel", role: .cancel) { }
                Button("Save") {
                    if let group = groupToRename {
                        let name = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !name.isEmpty {
                            viewModel.renameGroup(group, to: name)
                        }
                    }
                }
            } message: {
                Text("Enter a new name for this group.")
            }
            .confirmationDialog(
                "Delete Group",
                isPresented: Binding(
                    get: { groupToDelete != nil },
                    set: { if !$0 { groupToDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let group = groupToDelete {
                        viewModel.deleteGroup(group)
                    }
                }
            } message: {
                if let group = groupToDelete {
                    let feedCount = group.feeds.count
                    Text("This group contains \(feedCount) \(feedCount == 1 ? "feed" : "feeds"). The \(feedCount == 1 ? "feed" : "feeds") will be ungrouped, not deleted.")
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    viewModel.loadUnreadCount()
                    viewModel.loadSavedCount()
                    viewModel.loadGroupUnreadCounts()
                }
            }
        }
    }

    // MARK: - Helpers

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
        case .savedArticles:
            return viewModel.savedCount
        case .feedGroup(let feedGroup):
            let count = viewModel.groupUnreadCounts[feedGroup.id] ?? 0
            return count > 0 ? count : nil
        case .allArticles, .allFeeds:
            return nil
        }
    }
}

// MARK: - Home Row

private struct HomeRowView: View {

    let group: HomeGroup
    let badgeCount: Int?

    var body: some View {
        HStack {
            Label(group.title, systemImage: group.systemImage)
                .font(.headline)

            Spacer()

            if let count = badgeCount, count > 0 {
                Text("\(count)")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.blue)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, 4)
    }
}
