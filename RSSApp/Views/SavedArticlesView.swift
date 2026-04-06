import SwiftUI

struct SavedArticlesView: View {
    let persistence: FeedPersisting
    let homeViewModel: HomeViewModel

    @State private var selectedArticle: PersistentArticle?
    @State private var showMarkAllReadConfirmation = false
    @State private var hasAppeared = false

    private let thumbnailService: ArticleThumbnailCaching = ArticleThumbnailService()

    var body: some View {
        Group {
            if homeViewModel.savedArticlesList.isEmpty {
                ContentUnavailableView {
                    Label("No Saved Articles", systemImage: "bookmark")
                } description: {
                    Text("Saved articles will appear here.")
                }
            } else {
                List(homeViewModel.savedArticlesList, id: \.articleID) { article in
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
                    .swipeActions(edge: .trailing) {
                        Button {
                            homeViewModel.toggleSaved(article)
                            homeViewModel.loadSavedArticles()
                        } label: {
                            Label("Unsave", systemImage: "bookmark.slash")
                        }
                        .tint(.orange)
                    }
                    .onAppear {
                        if article.articleID == homeViewModel.savedArticlesList.last?.articleID {
                            homeViewModel.loadMoreSavedArticles()
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Saved Articles")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(role: .destructive) {
                        showMarkAllReadConfirmation = true
                    } label: {
                        Label("Mark All as Read", systemImage: "checkmark.circle")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .confirmationDialog(
            "Mark all articles as read?",
            isPresented: $showMarkAllReadConfirmation,
            titleVisibility: .visible
        ) {
            Button("Mark All as Read", role: .destructive) {
                homeViewModel.markAllAsRead()
            }
        }
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
            homeViewModel.loadSavedArticles()
            homeViewModel.loadSavedCount()
        }
        .task {
            homeViewModel.loadSavedArticles()
            hasAppeared = true
        }
        .onAppear {
            guard hasAppeared else { return }
            homeViewModel.loadSavedArticles()
        }
        .onDisappear {
            homeViewModel.loadSavedCount()
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
