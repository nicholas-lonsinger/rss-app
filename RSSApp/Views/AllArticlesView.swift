import SwiftUI

struct AllArticlesView: View {
    let persistence: FeedPersisting
    let homeViewModel: HomeViewModel

    @State private var selectedArticleIndex: Int?
    @State private var showMarkAllReadConfirmation = false
    @State private var hasAppeared = false
    // RATIONALE: Snapshot preservation across reader push/pop. See
    // ARCHITECTURE.md → "`returningFromReader` flag suppresses post-pop reload".
    @State private var returningFromReader = false

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
                List(Array(homeViewModel.allArticlesList.enumerated()), id: \.element.articleID) { index, article in
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
                        } label: {
                            Label(
                                article.isSaved ? "Unsave" : "Save",
                                systemImage: article.isSaved ? "bookmark.slash" : "bookmark"
                            )
                        }
                        .tint(.orange)
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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        homeViewModel.sortAscending.toggle()
                        homeViewModel.loadAllArticles()
                    } label: {
                        Label(
                            homeViewModel.sortAscending ? "Newest First" : "Oldest First",
                            systemImage: homeViewModel.sortAscending ? "arrow.down" : "arrow.up"
                        )
                    }

                    Divider()

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
                articles: homeViewModel.allArticlesList,
                initialIndex: index,
                loadMore: homeViewModel.hasMoreAllArticles ? { homeViewModel.loadMoreAllArticlesAndReport() } : nil
            )
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
            // RATIONALE: SwiftUI re-runs `.task` when this view reappears after the
            // pushed reader pops, which would re-query persistence and reset
            // pagination/scroll. Gating on `hasAppeared` makes the initial load fire
            // exactly once; subsequent reloads are owned by `.onAppear`, which is
            // itself guarded by `returningFromReader`.
            guard !hasAppeared else { return }
            homeViewModel.loadAllArticles()
            hasAppeared = true
        }
        .onAppear {
            guard hasAppeared else { return }
            if returningFromReader {
                returningFromReader = false
                return
            }
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
