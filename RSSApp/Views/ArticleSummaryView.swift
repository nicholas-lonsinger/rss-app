import SwiftUI

struct ArticleSummaryView: View {
    let article: Article

    @State private var viewModel: ArticleSummaryViewModel
    @State private var showDiscussion = false
    @Environment(\.dismiss) private var dismiss

    init(article: Article, preExtractedContent: ArticleContent? = nil) {
        self.article = article
        self._viewModel = State(
            initialValue: ArticleSummaryViewModel(article: article, preExtractedContent: preExtractedContent)
        )
    }

    var body: some View {
        NavigationStack {
            contentView
                .navigationTitle("Extracted Content")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Done") { dismiss() }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showDiscussion = true
                        } label: {
                            Image(systemName: "bubble.left.and.bubble.right")
                        }
                        .accessibilityLabel("Discuss with Claude")
                        .disabled(viewModel.extractedContent == nil)
                    }
                }
                .sheet(isPresented: $showDiscussion) {
                    if let content = viewModel.extractedContent {
                        ArticleDiscussionView(article: article, content: content)
                    }
                }
        }
        .task {
            await viewModel.loadContent()
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var contentView: some View {
        switch viewModel.state {
        case .idle:
            EmptyView()

        case .extracting:
            VStack(spacing: 16) {
                ProgressView()
                Text("Reading article…")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .ready(let content):
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(content.title)
                        .font(.headline)
                    if let byline = content.byline {
                        Text(byline)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Divider()
                    Text(content.textContent)
                        .font(.body)
                }
                .padding()
            }

        case .failed(let message):
            ContentUnavailableView {
                Label("Extraction Failed", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") {
                    Task { await viewModel.loadContent() }
                }
                .buttonStyle(.bordered)
            }
        }
    }
}
