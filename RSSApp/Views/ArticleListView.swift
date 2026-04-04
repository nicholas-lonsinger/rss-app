import SwiftUI

struct ArticleListView: View {
    let viewModel: FeedViewModel
    let persistence: FeedPersisting
    let thumbnailService: ArticleThumbnailCaching
    @State private var selectedArticle: PersistentArticle?

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.articles.isEmpty {
                ProgressView("Loading feed\u{2026}")
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
                List(viewModel.articles, id: \.articleID) { article in
                    Button {
                        viewModel.markAsRead(article)
                        selectedArticle = article
                    } label: {
                        ArticleRowView(article: article, thumbnailService: thumbnailService)
                    }
                    .buttonStyle(.plain)
                    .disabled(article.link == nil)
                    .swipeActions(edge: .leading) {
                        Button {
                            viewModel.toggleReadStatus(article)
                        } label: {
                            Label(
                                article.isRead ? "Unread" : "Read",
                                systemImage: article.isRead ? "envelope.badge" : "envelope.open"
                            )
                        }
                        .tint(article.isRead ? .blue : .gray)
                    }
                    .onAppear {
                        if article.articleID == viewModel.articles.last?.articleID {
                            viewModel.loadMoreArticles()
                        }
                    }
                }
                .listStyle(.plain)
                .refreshable { await viewModel.loadFeed() }
            }
        }
        .navigationTitle(viewModel.feedTitle)
        .fullScreenCover(item: $selectedArticle) { article in
            ArticleReaderView(article: article, persistence: persistence)
        }
        .task { await viewModel.loadFeed() }
        .alert("Error", isPresented: errorAlertBinding) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    // MARK: - Helpers

    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil && !viewModel.articles.isEmpty },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )
    }
}
