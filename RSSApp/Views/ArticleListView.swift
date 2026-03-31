import SwiftUI

struct ArticleListView: View {
    let viewModel: FeedViewModel

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.articles.isEmpty {
                ProgressView("Loading feed…")
            } else if let errorMessage = viewModel.errorMessage, viewModel.articles.isEmpty {
                ContentUnavailableView {
                    Label("Feed Unavailable", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("Retry") {
                        Task { await viewModel.loadFeed() }
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                List(viewModel.articles) { article in
                    NavigationLink(value: article) {
                        ArticleRowView(article: article)
                    }
                }
                .listStyle(.plain)
                .refreshable { await viewModel.loadFeed() }
            }
        }
        .navigationTitle("Feed")
        .navigationDestination(for: Article.self) { article in
            ArticleDetailView(article: article)
        }
        .task { await viewModel.loadFeed() }
    }
}
