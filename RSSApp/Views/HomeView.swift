import SwiftUI

struct HomeView: View {

    @State private var viewModel: HomeViewModel
    @State private var feedListViewModel: FeedListViewModel
    private let persistence: FeedPersisting

    init(persistence: FeedPersisting) {
        self.persistence = persistence
        let feedListVM = FeedListViewModel(persistence: persistence)
        _feedListViewModel = State(initialValue: feedListVM)
        _viewModel = State(initialValue: HomeViewModel(
            persistence: persistence,
            refreshFeeds: { [feedListVM] in
                await feedListVM.refreshAllFeeds()
            }
        ))
    }

    var body: some View {
        NavigationStack {
            List(HomeGroup.allCases) { group in
                NavigationLink(value: group) {
                    HomeRowView(group: group, unreadCount: unreadCount(for: group))
                }
            }
            .listStyle(.plain)
            .refreshable {
                await viewModel.refreshAllFeeds()
            }
            .navigationTitle("Home")
            .navigationDestination(for: HomeGroup.self) { group in
                switch group {
                case .allArticles:
                    AllArticlesView(persistence: persistence, homeViewModel: viewModel)
                case .unreadArticles:
                    UnreadArticlesView(persistence: persistence, homeViewModel: viewModel)
                case .allFeeds:
                    FeedListView(persistence: persistence, isEmbedded: true)
                }
            }
            .navigationDestination(for: SettingsDestination.self) { destination in
                switch destination {
                case .settings:
                    SettingsView(
                        persistence: persistence,
                        viewModel: feedListViewModel
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
                feedListViewModel.loadFeeds()
            }
            .alert("Error", isPresented: errorAlertBinding) {
                Button("OK") { viewModel.clearError() }
            } message: {
                Text(viewModel.errorMessage ?? "")
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

    private func unreadCount(for group: HomeGroup) -> Int? {
        switch group {
        case .unreadArticles:
            return viewModel.unreadCount
        case .allArticles, .allFeeds:
            return nil
        }
    }
}

// MARK: - Home Row

private struct HomeRowView: View {

    let group: HomeGroup
    let unreadCount: Int?

    var body: some View {
        HStack {
            Label(group.title, systemImage: group.systemImage)
                .font(.headline)

            Spacer()

            if let count = unreadCount, count > 0 {
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
