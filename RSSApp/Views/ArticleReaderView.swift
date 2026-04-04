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
                    hasAPIKey = (try? keychainService.hasAPIKey()) ?? false
                }
                .sheet(isPresented: $showAPIKeySettings, onDismiss: {
                    hasAPIKey = (try? keychainService.hasAPIKey()) ?? false
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
