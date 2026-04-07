import SwiftUI

struct SavedArticlesView: View {
    let persistence: FeedPersisting
    let homeViewModel: HomeViewModel

    @State private var selectedArticleIndex: Int?
    @State private var showMarkAllReadConfirmation = false
    @State private var hasAppeared = false
    // RATIONALE: With push navigation via .navigationDestination, popping the reader
    // re-fires this view's onAppear. Skipping the reload on the post-reader onAppear
    // preserves pagination depth and scroll position so the user returns to the same
    // spot they left. The flag is armed when we push the reader and consumed by the
    // next onAppear (the one triggered by the pop).
    @State private var returningFromReader = false

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
                List(Array(homeViewModel.savedArticlesList.enumerated()), id: \.element.articleID) { index, article in
                    Button {
                        if homeViewModel.markAsRead(article) {
                            returningFromReader = true
                            selectedArticleIndex = index
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
                            homeViewModel.removeFromSavedList(article)
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
        .navigationDestination(item: $selectedArticleIndex) { index in
            ArticleReaderView(
                persistence: persistence,
                articles: homeViewModel.savedArticlesList,
                initialIndex: index,
                loadMore: homeViewModel.hasMoreSavedArticles ? { homeViewModel.loadMoreSavedArticlesAndReport() } : nil
            )
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
            if returningFromReader {
                returningFromReader = false
                return
            }
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
