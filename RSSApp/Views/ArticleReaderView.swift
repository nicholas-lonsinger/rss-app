import SwiftUI
import os

struct ArticleReaderView: View {
    let persistence: FeedPersisting?

    /// The ordered list of articles from the originating list view.
    let articles: [PersistentArticle]

    /// Index of the currently displayed article within `articles`.
    @Binding var currentIndex: Int

    /// Closure to trigger loading more articles when the user navigates past the last loaded article.
    /// Returns a `LoadMoreResult` indicating whether articles were loaded, the data source is exhausted, or an error occurred.
    let loadMore: (() -> LoadMoreResult)?

    private static let logger = Logger(category: "ArticleReaderView")

    @State private var showSummary = false
    @State private var showAPIKeySettings = false
    @State private var extractionState = ReaderExtractionState()
    @State private var hasAPIKey = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    private let keychainService = KeychainService()

    /// The currently displayed article.
    /// After `loadMore` in `navigateToNext()`, `currentIndex` may temporarily exceed the local
    /// `articles` snapshot until SwiftUI re-renders with the updated array from the view model.
    private var article: PersistentArticle {
        guard articles.indices.contains(currentIndex) else {
            Self.logger.fault("currentIndex \(self.currentIndex, privacy: .public) out of bounds for \(self.articles.count, privacy: .public) articles")
            assertionFailure("currentIndex \(currentIndex) out of bounds for \(articles.count) articles")
            guard !articles.isEmpty else {
                Self.logger.fault("articles array is empty — returning sentinel article")
                assertionFailure("article accessed with empty articles array")
                return PersistentArticle(articleID: "", title: "")
            }
            return articles[min(currentIndex, articles.count - 1)]
        }
        return articles[currentIndex]
    }

    /// Whether the user can navigate to the previous article.
    private var canGoBack: Bool {
        currentIndex > 0
    }

    /// Whether the user can navigate to the next article or trigger pagination for more.
    private var canGoForward: Bool {
        currentIndex < articles.count - 1 || loadMore != nil
    }

    /// Whether content extraction is still in progress (API key present but content not yet available).
    private var isExtracting: Bool {
        hasAPIKey && extractionState.content == nil && article.link != nil
    }

    var body: some View {
        NavigationStack {
            articleContent
                .id(article.articleID)
                .navigationTitle(article.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Done") { dismiss() }
                    }
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button {
                            toggleSaved()
                        } label: {
                            Image(systemName: article.isSaved ? "bookmark.fill" : "bookmark")
                        }
                        .accessibilityLabel(article.isSaved ? "Unsave article" : "Save article")

                        if isExtracting {
                            ProgressView()
                                .accessibilityLabel("Extracting article content")
                        } else {
                            Button {
                                if hasAPIKey {
                                    Self.logger.debug("AI button tapped — API key present, showing summary")
                                    showSummary = true
                                } else {
                                    Self.logger.debug("AI button tapped — no API key, showing API key settings")
                                    showAPIKeySettings = true
                                }
                            } label: {
                                Image(systemName: "sparkles")
                            }
                            .accessibilityLabel("Summarize with AI")
                        }
                    }
                    ToolbarItemGroup(placement: .bottomBar) {
                        Button {
                            navigateToPrevious()
                        } label: {
                            Image(systemName: "chevron.backward")
                        }
                        .disabled(!canGoBack)
                        .accessibilityLabel("Previous article")

                        Spacer()

                        Button {
                            navigateToNext()
                        } label: {
                            Image(systemName: "chevron.forward")
                        }
                        .disabled(!canGoForward)
                        .accessibilityLabel("Next article")
                    }
                }
                .onAppear {
                    do {
                        hasAPIKey = try keychainService.hasAPIKey()
                    } catch {
                        hasAPIKey = false
                        Self.logger.error("Keychain read failed in onAppear: \(error, privacy: .public)")
                    }
                }
                .onChange(of: currentIndex) {
                    // Deferred mark-as-read for the pagination path: after loadMore appends
                    // new articles to the view model, SwiftUI re-renders this view with the
                    // updated array, and this handler ensures the newly visible article is
                    // marked as read. For normal navigation, markCurrentArticleAsRead() is
                    // also called directly in onArticleChanged(); the isRead guard prevents
                    // double-work.
                    markCurrentArticleAsRead()
                }
                .sheet(isPresented: $showAPIKeySettings, onDismiss: {
                    do {
                        hasAPIKey = try keychainService.hasAPIKey()
                    } catch {
                        hasAPIKey = false
                        Self.logger.error("Keychain read failed on settings dismiss: \(error, privacy: .public)")
                    }
                }) {
                    NavigationStack {
                        APIKeySettingsView()
                            .toolbar {
                                ToolbarItem(placement: .topBarTrailing) {
                                    Button("Done") { showAPIKeySettings = false }
                                }
                            }
                    }
                }
                // RATIONALE: ArticleSummaryView has no navigation path to API key settings,
                // so no hasAPIKey cache refresh is needed on dismiss.
                .sheet(isPresented: $showSummary) {
                    ArticleSummaryView(
                        article: article.toArticle(),
                        preExtractedContent: extractionState.content,
                        persistentArticle: article,
                        persistence: persistence
                    )
                }
                .alert("Error", isPresented: errorAlertBinding) {
                    Button("OK") { errorMessage = nil }
                } message: {
                    Text(errorMessage ?? "")
                }
        }
    }

    // MARK: - Helpers

    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    // MARK: - Navigation

    private func navigateToPrevious() {
        guard canGoBack else { return }
        Self.logger.debug("Navigating to previous article (index \(self.currentIndex - 1, privacy: .public))")
        currentIndex -= 1
        onArticleChanged()
    }

    private func navigateToNext() {
        let isAtLastLoaded = currentIndex == articles.count - 1

        if isAtLastLoaded {
            // Try to load more articles before advancing
            guard let loadMore else {
                Self.logger.info("No more articles available at end of list (no loadMore closure)")
                return
            }
            switch loadMore() {
            case .loaded:
                Self.logger.info("Loaded more articles via pagination, advancing to next (index \(self.currentIndex + 1, privacy: .public))")
                // RATIONALE: After loadMore appends to the view model's array, the local
                // `articles` snapshot is stale (value-type copy). We update currentIndex via
                // the binding so SwiftUI re-renders with the updated array, but skip
                // onArticleChanged() because `articles[currentIndex + 1]` would be out of
                // bounds in the current snapshot. The extraction state reset and mark-as-read
                // are deferred to the onChange(of: currentIndex) handler which runs after
                // the view re-renders with the fresh array.
                extractionState = ReaderExtractionState()
                showSummary = false
                currentIndex += 1
            case .exhausted:
                Self.logger.info("No more articles available at end of list")
            case .failed(let message):
                Self.logger.error("Failed to load more articles: \(message, privacy: .public)")
                errorMessage = message
            }
        } else {
            Self.logger.debug("Navigating to next article (index \(self.currentIndex + 1, privacy: .public))")
            currentIndex += 1
            onArticleChanged()
        }
    }

    /// Resets extraction state, dismisses the summary sheet, and marks the new article as read after navigation.
    private func onArticleChanged() {
        extractionState = ReaderExtractionState()
        showSummary = false
        markCurrentArticleAsRead()
    }

    // MARK: - Actions

    private func markCurrentArticleAsRead() {
        guard !article.isRead else { return }
        guard let persistence else {
            Self.logger.fault("Cannot mark article as read — no persistence service")
            assertionFailure("markCurrentArticleAsRead called but persistence is nil")
            return
        }
        do {
            try persistence.markArticleRead(article, isRead: true)
            Self.logger.notice("Marked article '\(article.title, privacy: .public)' as read via navigation")
        } catch {
            errorMessage = "Unable to save read status."
            Self.logger.error("Failed to mark article as read: \(error, privacy: .public)")
        }
    }

    private func toggleSaved() {
        guard let persistence else {
            Self.logger.fault("Cannot toggle saved — no persistence service")
            assertionFailure("toggleSaved called but persistence is nil")
            return
        }
        do {
            try persistence.toggleArticleSaved(article)
            Self.logger.notice("Toggled saved state for '\(article.title, privacy: .public)'")
        } catch {
            errorMessage = "Unable to update saved status."
            Self.logger.error("Failed to toggle saved state: \(error, privacy: .public)")
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var articleContent: some View {
        if let url = article.link {
            ArticleReaderWebView(url: url, extractionState: extractionState, fallbackHTML: article.articleDescription)
                .ignoresSafeArea(edges: .bottom)
        } else {
            ContentUnavailableView {
                Label("Article Unavailable", systemImage: "exclamationmark.triangle")
            } description: {
                Text("This article has no URL.")
            }
        }
    }
}
