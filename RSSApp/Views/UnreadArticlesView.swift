import SwiftUI

struct UnreadArticlesView: View {
    let persistence: FeedPersisting
    let homeViewModel: HomeViewModel

    @State private var selectedArticleIndex: Int?
    @State private var showMarkAllReadConfirmation = false
    @State private var hasAppeared = false

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
                List(Array(homeViewModel.unreadArticlesList.enumerated()), id: \.element.articleID) { index, article in
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
                        } label: {
                            Label(
                                article.isSaved ? "Unsave" : "Save",
                                systemImage: article.isSaved ? "bookmark.slash" : "bookmark"
                            )
                        }
                        .tint(.orange)
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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        homeViewModel.sortAscending.toggle()
                        homeViewModel.loadUnreadArticles()
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
        .fullScreenCover(item: $selectedArticleIndex.identifiableIndex) { _ in
            ArticleReaderView(
                persistence: persistence,
                articles: homeViewModel.unreadArticlesList,
                currentIndex: $selectedArticleIndex.nonOptionalIndex,
                loadMore: homeViewModel.hasMoreUnreadArticles ? { homeViewModel.loadMoreUnreadArticlesAndReport() } : nil
            )
        }
        .alert("Error", isPresented: errorAlertBinding) {
            Button("OK") { homeViewModel.clearError() }
        } message: {
            Text(homeViewModel.errorMessage ?? "")
        }
        .refreshable {
            await homeViewModel.refreshAllFeeds()
            homeViewModel.loadUnreadArticles()
            homeViewModel.loadUnreadCount()
        }
        .task {
            homeViewModel.loadUnreadArticles()
            hasAppeared = true
        }
        .onAppear {
            guard hasAppeared else { return }
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
