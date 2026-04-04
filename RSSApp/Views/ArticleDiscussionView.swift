import SwiftUI

struct ArticleDiscussionView: View {
    let article: Article
    let content: ArticleContent

    @State private var viewModel: DiscussionViewModel
    @State private var showSettings = false
    @Environment(\.dismiss) private var dismiss

    init(article: Article, content: ArticleContent) {
        self.article = article
        self.content = content
        self._viewModel = State(initialValue: DiscussionViewModel(article: article, content: content))
    }

    var body: some View {
        NavigationStack {
            Group {
                if let keychainError = viewModel.keychainError {
                    keychainErrorView(message: keychainError)
                } else if viewModel.hasAPIKey {
                    chatView
                } else {
                    noKeyView
                }
            }
            .navigationTitle("Discuss")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showSettings, onDismiss: {
                viewModel.refreshAPIKeyState()
            }) {
                NavigationStack {
                    APIKeySettingsView()
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Done") { showSettings = false }
                            }
                        }
                }
            }
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var chatView: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(viewModel.messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }
                        if viewModel.isGenerating && viewModel.messages.last?.role == .assistant && viewModel.messages.last?.content.isEmpty == true {
                            TypingIndicator()
                                .padding(.leading, 12)
                        }
                    }
                    .padding()
                }
                .onChange(of: viewModel.messages.count) {
                    if let last = viewModel.messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }

            Divider()

            inputBar
        }
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("Ask about this article…", text: $viewModel.currentInput, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)
                .submitLabel(.send)
                .onSubmit {
                    Task { await viewModel.sendMessage() }
                }

            Button {
                Task { await viewModel.sendMessage() }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(canSend ? .blue : .secondary)
            }
            .disabled(!canSend)
        }
        .padding(12)
        .background(.bar)
    }

    private var canSend: Bool {
        !viewModel.currentInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !viewModel.isGenerating
    }

    private func keychainErrorView(message: String) -> some View {
        ContentUnavailableView {
            Label("Keychain Error", systemImage: "exclamationmark.lock")
        } description: {
            Text(message)
        }
    }

    private var noKeyView: some View {
        ContentUnavailableView {
            Label("API Key Required", systemImage: "key.slash")
        } description: {
            Text("Add your Anthropic API key to start discussing articles with Claude.")
        } actions: {
            Button("Open Settings") { showSettings = true }
                .buttonStyle(.bordered)
        }
    }
}

// MARK: - MessageBubble

private struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 60) }
            Text(message.content.isEmpty ? " " : message.content)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(message.role == .user ? Color.blue : Color(.systemGray5))
                .foregroundStyle(message.role == .user ? .white : .primary)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            if message.role == .assistant { Spacer(minLength: 60) }
        }
    }
}

// MARK: - TypingIndicator

private struct TypingIndicator: View {
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { _ in
                Circle()
                    .frame(width: 6, height: 6)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(.systemGray5))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
