import SwiftUI

struct SavedArticlesView: View {
    let persistence: FeedPersisting
    let homeViewModel: HomeViewModel

    @State private var selectedArticleIndex: Int?
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
                List(Array(homeViewModel.savedArticlesList.enumerated()), id: \.element.articleID) { index, article in
                    Button {
                        if homeViewModel.markAsRead(article) {
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
        .fullScreenCover(item: selectedArticleIndexBinding) { _ in
            ArticleReaderView(
                persistence: persistence,
                articles: homeViewModel.savedArticlesList,
                currentIndex: selectedArticleIndexNonOptionalBinding,
                loadMore: { homeViewModel.loadMoreSavedArticlesAndReport() }
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

    /// Wraps `selectedArticleIndex` as an `Identifiable` binding for `fullScreenCover(item:)`.
    private var selectedArticleIndexBinding: Binding<IdentifiableIndex?> {
        Binding(
            get: { selectedArticleIndex.map { IdentifiableIndex(value: $0) } },
            set: { selectedArticleIndex = $0?.value }
        )
    }

    /// Provides a non-optional binding to the current index for the reader view.
    private var selectedArticleIndexNonOptionalBinding: Binding<Int> {
        Binding(
            get: { selectedArticleIndex ?? 0 },
            set: { selectedArticleIndex = $0 }
        )
    }
}
