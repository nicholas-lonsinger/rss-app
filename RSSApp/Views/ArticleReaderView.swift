import SwiftUI
import os

struct ArticleReaderView: View {
    let article: PersistentArticle
    let persistence: FeedPersisting?

    private static let logger = Logger(category: "ArticleReaderView")

    @State private var showSummary = false
    @State private var showAPIKeySettings = false
    @State private var extractionState = ReaderExtractionState()
    @State private var hasAPIKey = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    private let keychainService = KeychainService()

    /// Whether content extraction is still in progress (API key present but content not yet available).
    private var isExtracting: Bool {
        hasAPIKey && extractionState.content == nil && article.link != nil
    }

    var body: some View {
        NavigationStack {
            articleContent
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

    // MARK: - Actions

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
