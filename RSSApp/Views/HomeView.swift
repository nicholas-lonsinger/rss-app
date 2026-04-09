import SwiftUI

struct HomeView: View {

    @Environment(\.scenePhase) private var scenePhase
    @State private var viewModel: HomeViewModel
    @State private var feedListViewModel: FeedListViewModel
    private let persistence: FeedPersisting
    private let refreshService: FeedRefreshService
    private let feedIconService: FeedIconResolving

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
            List(HomeGroup.allCases) { group in
                NavigationLink(value: group) {
                    HomeRowView(group: group, badgeCount: badgeCount(for: group))
                }
            }
            .listStyle(.plain)
            .refreshable {
                await viewModel.refreshAllFeeds()
                viewModel.loadUnreadCount()
                viewModel.loadSavedCount()
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
                    NavigationLink(value: SettingsDestination.settings) {
                        Image(systemName: "gear")
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .task {
                viewModel.loadUnreadCount()
                viewModel.loadSavedCount()
                feedListViewModel.loadFeeds()
            }
            .alert("Error", isPresented: errorAlertBinding) {
                Button("OK") { viewModel.clearError() }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    viewModel.loadUnreadCount()
                    viewModel.loadSavedCount()
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
