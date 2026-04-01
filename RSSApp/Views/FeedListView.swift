import SwiftUI

struct FeedListView: View {
    @State private var viewModel = FeedListViewModel()
    @State private var showAddFeed = false
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            Group {
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
                        ForEach(viewModel.feeds) { feed in
                            NavigationLink(value: feed) {
                                FeedRowView(feed: feed)
                            }
                        }
                        .onDelete { offsets in
                            viewModel.removeFeed(at: offsets)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Feeds")
            .navigationDestination(for: SubscribedFeed.self) { feed in
                ArticleListView(viewModel: FeedViewModel(feedURL: feed.url))
            }
            .toolbar {
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
                        showSettings = true
                    } label: {
                        Image(systemName: "gear")
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .sheet(isPresented: $showAddFeed, onDismiss: {
                viewModel.loadFeeds()
            }) {
                AddFeedView()
            }
            .sheet(isPresented: $showSettings) {
                APIKeySettingsView()
            }
            .task {
                viewModel.loadFeeds()
            }
        }
    }
}
