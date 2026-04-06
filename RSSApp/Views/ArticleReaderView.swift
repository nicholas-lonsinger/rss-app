import SwiftUI
import os

struct ArticleReaderView: View {
    let persistence: FeedPersisting?

    /// The ordered list of articles from the originating list view.
    let articles: [PersistentArticle]

    /// Index of the currently displayed article within `articles`.
    @Binding var currentIndex: Int

    /// Closure to trigger loading more articles when the user navigates past the last loaded article.
    /// Returns `true` if more articles were loaded, `false` if no more are available.
    let loadMore: (() -> Bool)?

    private static let logger = Logger(category: "ArticleReaderView")

    @State private var showSummary = false
    @State private var showAPIKeySettings = false
    @State private var extractionState = ReaderExtractionState()
    @State private var hasAPIKey = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    private let keychainService = KeychainService()

    /// The currently displayed article.
    private var article: PersistentArticle {
        articles[currentIndex]
    }

    /// Whether the user can navigate to the previous article.
    private var canGoBack: Bool {
        currentIndex > 0
    }

    /// Whether the user can navigate to the next article.
    private var canGoForward: Bool {
        currentIndex < articles.count - 1
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
            if let loadMore, loadMore() {
                Self.logger.debug("Loaded more articles, advancing to next (index \(self.currentIndex + 1, privacy: .public))")
                currentIndex += 1
                onArticleChanged()
            } else {
                Self.logger.debug("No more articles available at end of list")
            }
        } else {
            Self.logger.debug("Navigating to next article (index \(self.currentIndex + 1, privacy: .public))")
            currentIndex += 1
            onArticleChanged()
        }
    }

    /// Resets extraction state and marks the new article as read after navigation.
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
            Self.logger.debug("Marked article '\(article.title, privacy: .public)' as read via navigation")
        } catch {
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
