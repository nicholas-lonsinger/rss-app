import SwiftUI

struct ArticleSummaryView: View {
    let article: Article

    @State private var viewModel: ArticleSummaryViewModel
    @State private var showDiscussion = false
    @Environment(\.dismiss) private var dismiss

    init(
        article: Article,
        preExtractedContent: ArticleContent? = nil,
        persistentArticle: PersistentArticle? = nil,
        persistence: FeedPersisting? = nil
    ) {
        self.article = article
        self._viewModel = State(
            initialValue: ArticleSummaryViewModel(
                article: article,
                preExtractedContent: preExtractedContent,
                persistentArticle: persistentArticle,
                persistence: persistence
            )
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
                        .accessibilityLabel("Discuss with AI")
                        .disabled(!viewModel.isReady)
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
                    if viewModel.isContentStale {
                        staleContentBanner
                    }
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

    // MARK: - Stale Content Banner

    /// Shown above the article body when the cached article body pre-dates the
    /// publisher's most recent revision (issue #398). Non-intrusive: never
    /// auto-replaces content while the user is reading. The Refresh button triggers
    /// `viewModel.refreshContent()` as an explicit opt-in action. The button is
    /// disabled while a refresh is in progress to prevent concurrent refresh races.
    /// A "Refresh failed" label appears transiently when the last refresh attempt
    /// did not succeed, cleared automatically when the user taps Refresh again.
    private var staleContentBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.trianglehead.2.clockwise")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("A newer version of this article is available.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if viewModel.refreshFailed {
                    Text("Refresh failed. Tap to try again.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            Spacer()
            Button("Refresh") {
                Task { await viewModel.refreshContent() }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(viewModel.isRefreshing)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.orange.opacity(0.1))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            viewModel.refreshFailed
                ? "A newer version of this article is available. Refresh failed. Tap to try again."
                : "A newer version of this article is available. Tap Refresh to load it."
        )
    }
}
