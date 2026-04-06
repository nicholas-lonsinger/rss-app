import SwiftUI

struct ArticleListView: View {
    let viewModel: FeedViewModel
    let persistence: FeedPersisting
    let thumbnailService: ArticleThumbnailCaching
    @State private var selectedArticleIndex: Int?
    @State private var showMarkAllReadConfirmation = false
    @State private var hasAppeared = false

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
                List(Array(viewModel.articles.enumerated()), id: \.element.articleID) { index, article in
                    Button {
                        viewModel.markAsRead(article)
                        selectedArticleIndex = index
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
                    .swipeActions(edge: .trailing) {
                        Button {
                            viewModel.toggleSaved(article)
                        } label: {
                            Label(
                                article.isSaved ? "Unsave" : "Save",
                                systemImage: article.isSaved ? "bookmark.slash" : "bookmark"
                            )
                        }
                        .tint(.orange)
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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        viewModel.sortAscending.toggle()
                    } label: {
                        Label(
                            viewModel.sortAscending ? "Newest First" : "Oldest First",
                            systemImage: viewModel.sortAscending ? "arrow.down" : "arrow.up"
                        )
                    }

                    Button {
                        viewModel.showUnreadOnly.toggle()
                    } label: {
                        Label(
                            viewModel.showUnreadOnly ? "Show All Articles" : "Show Unread Only",
                            systemImage: viewModel.showUnreadOnly ? "envelope.open" : "envelope.badge"
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
                viewModel.markAllAsRead()
            }
        }
        .fullScreenCover(item: selectedArticleIndexBinding) { _ in
            ArticleReaderView(
                persistence: persistence,
                articles: viewModel.articles,
                currentIndex: selectedArticleIndexNonOptionalBinding,
                loadMore: { viewModel.loadMoreAndReport() }
            )
        }
        .task {
            await viewModel.loadFeed()
            hasAppeared = true
        }
        .onAppear {
            guard hasAppeared else { return }
            viewModel.reloadArticles()
        }
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

    /// Wraps `selectedArticleIndex` as an `Identifiable` binding for `fullScreenCover(item:)`.
    private var selectedArticleIndexBinding: Binding<IdentifiableIndex?> {
        Binding(
            get: { selectedArticleIndex.map { IdentifiableIndex(value: $0) } },
            set: { selectedArticleIndex = $0?.value }
        )
    }

    /// Provides a non-optional binding to the current index for the reader view.
    /// Defaults to 0 when `selectedArticleIndex` is nil (should never happen while the cover is presented).
    private var selectedArticleIndexNonOptionalBinding: Binding<Int> {
        Binding(
            get: { selectedArticleIndex ?? 0 },
            set: { selectedArticleIndex = $0 }
        )
    }
}
