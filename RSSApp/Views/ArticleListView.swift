import SwiftUI

struct ArticleListView: View {
    let viewModel: FeedViewModel
    @State private var selectedArticle: Article?

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
                    Button {
                        selectedArticle = article
                    } label: {
                        ArticleRowView(article: article)
                    }
                    .buttonStyle(.plain)
                    .disabled(article.link == nil)
                }
                .listStyle(.plain)
                .refreshable { await viewModel.loadFeed() }
            }
        }
        .navigationTitle(viewModel.feedTitle)
        .fullScreenCover(item: $selectedArticle) { article in
            ArticleReaderView(article: article)
        }
        .task { await viewModel.loadFeed() }
    }
}
