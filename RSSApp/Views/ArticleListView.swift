import SwiftUI

struct ArticleListView: View {
    let viewModel: FeedViewModel
    @State private var selectedArticle: Article?
    @State private var showSettings = false

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
        .navigationTitle("Feed")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gear")
                }
                .accessibilityLabel("Settings")
            }
        }
        .fullScreenCover(item: $selectedArticle) { article in
            ArticleReaderView(article: article)
        }
        .sheet(isPresented: $showSettings) {
            APIKeySettingsView()
        }
        .task { await viewModel.loadFeed() }
    }
}
