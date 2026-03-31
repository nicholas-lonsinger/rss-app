import SwiftUI

struct ArticleReaderView: View {
    let article: Article

    @State private var viewModel: ArticleReaderViewModel
    @State private var showDiscussion = false
    @State private var showSettings = false
    @Environment(\.dismiss) private var dismiss

    init(article: Article) {
        self.article = article
        self._viewModel = State(initialValue: ArticleReaderViewModel(article: article))
    }

    var body: some View {
        NavigationStack {
            content
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
                            showDiscussion = true
                        } label: {
                            Image(systemName: "bubble.left.and.bubble.right")
                        }
                        .accessibilityLabel("Discuss with Claude")
                        .disabled(!isContentReady)
                    }
                }
                .sheet(isPresented: $showSettings) {
                    APIKeySettingsView()
                }
                .sheet(isPresented: $showDiscussion) {
                    if case .loaded(let articleContent) = viewModel.state {
                        ArticleDiscussionView(article: article, content: articleContent)
                    }
                }
                .task { await viewModel.extractContent() }
        }
    }

    // MARK: - Content states

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            ProgressView("Loading article…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .loaded(let articleContent):
            ArticleReaderWebView(content: articleContent, baseURL: article.link)
                .ignoresSafeArea(edges: .bottom)

        case .failed(let message):
            ContentUnavailableView {
                Label("Article Unavailable", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                if let link = article.link {
                    Link("Open in Safari", destination: link)
                        .buttonStyle(.bordered)
                }
                Button("Retry") {
                    Task { await viewModel.extractContent() }
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var isContentReady: Bool {
        if case .loaded = viewModel.state { return true }
        return false
    }
}
