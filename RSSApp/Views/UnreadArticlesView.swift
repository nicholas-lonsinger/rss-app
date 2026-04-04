import SwiftUI

struct UnreadArticlesView: View {
    let persistence: FeedPersisting
    let homeViewModel: HomeViewModel

    @State private var articles: [PersistentArticle] = []
    @State private var selectedArticle: PersistentArticle?

    private let thumbnailService: ArticleThumbnailCaching = ArticleThumbnailService()

    var body: some View {
        Group {
            if articles.isEmpty {
                ContentUnavailableView {
                    Label("All Caught Up", systemImage: "checkmark.circle")
                } description: {
                    Text("You have no unread articles.")
                }
            } else {
                List(articles, id: \.articleID) { article in
                    Button {
                        homeViewModel.markAsRead(article)
                        reloadArticles()
                        selectedArticle = article
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
                            reloadArticles()
                        } label: {
                            Label(
                                article.isRead ? "Unread" : "Read",
                                systemImage: article.isRead ? "envelope.badge" : "envelope.open"
                            )
                        }
                        .tint(article.isRead ? .blue : .gray)
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Unread Articles")
        .fullScreenCover(item: $selectedArticle) { article in
            ArticleReaderView(article: article, persistence: persistence)
        }
        .task {
            reloadArticles()
        }
        .onDisappear {
            homeViewModel.loadUnreadCount()
        }
    }

    // MARK: - Helpers

    private func reloadArticles() {
        articles = homeViewModel.unreadArticles()
    }
}
