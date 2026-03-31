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
            VStack(spacing: 0) {
                optionsPickers
                    .padding()
                Divider()
                summaryContent
            }
            .navigationTitle("Summary")
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
        .task(id: viewModel.options) {
            await viewModel.generate()
        }
    }

    // MARK: - Subviews

    private var optionsPickers: some View {
        HStack(spacing: 12) {
            Picker("Length", selection: $viewModel.options.length) {
                ForEach(SummaryLength.allCases, id: \.self) { length in
                    Text(length.rawValue).tag(length)
                }
            }
            .pickerStyle(.segmented)

            Picker("Format", selection: $viewModel.options.format) {
                ForEach(SummaryFormat.allCases, id: \.self) { format in
                    Text(format.rawValue).tag(format)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    @ViewBuilder
    private var summaryContent: some View {
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

        case .generating:
            VStack(spacing: 16) {
                ProgressView()
                Text("Generating summary…")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .ready(let text):
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if text.isEmpty {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text(.init(text))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Label("Summarized on-device", systemImage: "cpu")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .unavailable:
            ContentUnavailableView {
                Label("Not Available", systemImage: "cpu.fill")
            } description: {
                Text("Apple Intelligence is not available on this device. It requires an iPhone 15 Pro or later.")
            }

        case .failed(let message):
            ContentUnavailableView {
                Label("Summary Failed", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") {
                    Task { await viewModel.generate() }
                }
                .buttonStyle(.bordered)
            }
        }
    }
}
