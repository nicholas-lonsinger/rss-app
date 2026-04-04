import SwiftUI

struct UnreadArticlesView: View {
    let persistence: FeedPersisting
    let homeViewModel: HomeViewModel

    @State private var selectedArticle: PersistentArticle?

    private let thumbnailService: ArticleThumbnailCaching = ArticleThumbnailService()

    var body: some View {
        Group {
            if homeViewModel.unreadArticlesList.isEmpty {
                ContentUnavailableView {
                    Label("All Caught Up", systemImage: "checkmark.circle")
                } description: {
                    Text("You have no unread articles.")
                }
            } else {
                List(homeViewModel.unreadArticlesList, id: \.articleID) { article in
                    Button {
                        if homeViewModel.markAsRead(article) {
                            selectedArticle = article
                            homeViewModel.removeFromUnreadList(article)
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
                            if article.isRead {
                                homeViewModel.removeFromUnreadList(article)
                            }
                        } label: {
                            Label(
                                article.isRead ? "Unread" : "Read",
                                systemImage: article.isRead ? "envelope.badge" : "envelope.open"
                            )
                        }
                        .tint(article.isRead ? .blue : .gray)
                    }
                    .onAppear {
                        if article.articleID == homeViewModel.unreadArticlesList.last?.articleID {
                            homeViewModel.loadMoreUnreadArticles()
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Unread Articles")
        .fullScreenCover(item: $selectedArticle) { article in
            ArticleReaderView(article: article, persistence: persistence)
        }
        .alert("Error", isPresented: errorAlertBinding) {
            Button("OK") { homeViewModel.clearError() }
        } message: {
            Text(homeViewModel.errorMessage ?? "")
        }
        .task {
            homeViewModel.loadUnreadArticles()
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
