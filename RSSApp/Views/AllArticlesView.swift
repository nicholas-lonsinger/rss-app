import SwiftUI

struct AllArticlesView: View {
    let persistence: FeedPersisting
    let homeViewModel: HomeViewModel

    @State private var selectedArticle: PersistentArticle?

    private let thumbnailService: ArticleThumbnailCaching = ArticleThumbnailService()

    var body: some View {
        Group {
            if homeViewModel.allArticlesList.isEmpty {
                ContentUnavailableView {
                    Label("No Articles", systemImage: "doc.text")
                } description: {
                    Text("Articles from your feeds will appear here.")
                }
            } else {
                List(homeViewModel.allArticlesList, id: \.articleID) { article in
                    Button {
                        if homeViewModel.markAsRead(article) {
                            selectedArticle = article
                        }
                    } label: {
                        CrossFeedArticleRowView(
                            article: article,
                            thumbnailService: thumbnailService
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(article.link == nil)
                    .swipeActions(edge: .leading) {
                        Button {
                            homeViewModel.toggleReadStatus(article)
                        } label: {
                            Label(
                                article.isRead ? "Unread" : "Read",
                                systemImage: article.isRead ? "envelope.badge" : "envelope.open"
                            )
                        }
                        .tint(article.isRead ? .blue : .gray)
                    }
                    .onAppear {
                        if article.articleID == homeViewModel.allArticlesList.last?.articleID {
                            homeViewModel.loadMoreAllArticles()
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("All Articles")
        .fullScreenCover(item: $selectedArticle) { article in
            ArticleReaderView(article: article, persistence: persistence)
        }
        .alert("Error", isPresented: errorAlertBinding) {
            Button("OK") { homeViewModel.clearError() }
        } message: {
            Text(homeViewModel.errorMessage ?? "")
        }
        .refreshable {
            await homeViewModel.refreshAllFeeds()
            homeViewModel.loadAllArticles()
            homeViewModel.loadUnreadCount()
        }
        .task {
            homeViewModel.loadAllArticles()
        }
        .onDisappear {
            homeViewModel.loadUnreadCount()
        }
    }

    // MARK: - Helpers

    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { homeViewModel.errorMessage != nil },
            set: { if !$0 { homeViewModel.clearError() } }
        )
    }
}
