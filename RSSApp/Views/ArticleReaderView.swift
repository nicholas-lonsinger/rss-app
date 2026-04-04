import SwiftUI
import os

struct ArticleReaderView: View {
    let article: PersistentArticle
    let persistence: FeedPersisting?

    private static let logger = Logger(category: "ArticleReaderView")

    @State private var showSummary = false
    @State private var showAPIKeySettings = false
    @State private var extractionState = ReaderExtractionState()
    @Environment(\.dismiss) private var dismiss

    private let keychainService = KeychainService()

    private var hasAPIKey: Bool {
        keychainService.hasAPIKey
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
                        .disabled(hasAPIKey && extractionState.content == nil)
                    }
                }
                .sheet(isPresented: $showAPIKeySettings) {
                    NavigationStack {
                        APIKeySettingsView()
                            .toolbar {
                                ToolbarItem(placement: .topBarTrailing) {
                                    Button("Done") { showAPIKeySettings = false }
                                }
                            }
                    }
                }
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
