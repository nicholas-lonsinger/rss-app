import SwiftUI

struct ArticleReaderView: View {
    let article: PersistentArticle

    @State private var showSummary = false
    @State private var showSettings = false
    @State private var extractionState = ReaderExtractionState()
    @Environment(\.dismiss) private var dismiss

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
                            showSettings = true
                        } label: {
                            Image(systemName: "gear")
                        }
                        .accessibilityLabel("Settings")

                        Button {
                            showSummary = true
                        } label: {
                            Image(systemName: "sparkles")
                        }
                        .accessibilityLabel("Summarize with AI")
                        .disabled(extractionState.content == nil)
                    }
                }
                .sheet(isPresented: $showSettings) {
                    APIKeySettingsView()
                }
                .sheet(isPresented: $showSummary) {
                    ArticleSummaryView(
                        article: article.toArticle(),
                        preExtractedContent: extractionState.content
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
