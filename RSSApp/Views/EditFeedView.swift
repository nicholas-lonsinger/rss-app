import SwiftUI

struct EditFeedView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: EditFeedViewModel

    init(feed: PersistentFeed, persistence: FeedPersisting) {
        _viewModel = State(initialValue: EditFeedViewModel(feed: feed, persistence: persistence))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://example.com/feed", text: $viewModel.urlInput)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .textContentType(.URL)
                } header: {
                    Text("Feed URL")
                } footer: {
                    Text("Update the URL if the feed has moved.")
                }

                if let error = viewModel.errorMessage {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button {
                        Task { await viewModel.saveFeed() }
                    } label: {
                        if viewModel.isValidating {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text("Validating…")
                            }
                        } else {
                            Text("Save")
                        }
                    }
                    .disabled(!viewModel.canSubmit)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Edit Feed")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onChange(of: viewModel.didSave) { _, newValue in
                if newValue { dismiss() }
            }
            .alert(
                "Atom feed available",
                isPresented: Binding(
                    get: { viewModel.atomAlternatePrompt != nil },
                    set: { if !$0 { viewModel.atomAlternatePrompt = nil } }
                ),
                presenting: viewModel.atomAlternatePrompt
            ) { prompt in
                // RATIONALE: capture `prompt` synchronously here rather than
                // re-reading `viewModel.atomAlternatePrompt` inside the Task.
                // SwiftUI's `.alert(isPresented:)` clears the bound state as
                // the alert dismisses, which races with the spawned Task and
                // would cause switchToAtomAlternate/keepOriginalFeed to see
                // nil and no-op silently.
                Button("Switch to Atom") {
                    Task { await viewModel.switchToAtomAlternate(from: prompt) }
                }
                Button("Keep RSS", role: .cancel) {
                    viewModel.keepOriginalFeed(from: prompt)
                }
            } message: { prompt in
                Text("This site also publishes an Atom version of this feed at \(prompt.atomURL.absoluteString). Atom feeds often include richer metadata.")
            }
            .alert(
                "Atom feed unavailable",
                isPresented: Binding(
                    get: { viewModel.atomFallbackNotice != nil },
                    // Acknowledging the notice both clears it and signals
                    // the sheet to dismiss (didSave = true) so the
                    // successfully-persisted RSS edit is committed.
                    set: { if !$0 { viewModel.acknowledgeAtomFallbackNotice() } }
                ),
                presenting: viewModel.atomFallbackNotice
            ) { atomURL in
                Button("OK", role: .cancel) { }
            } message: { atomURL in
                Text("The Atom feed at \(atomURL.absoluteString) couldn't be loaded. The RSS version has been saved instead.")
            }
        }
    }
}
