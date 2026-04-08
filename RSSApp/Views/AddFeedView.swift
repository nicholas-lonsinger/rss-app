import SwiftUI

struct AddFeedView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: AddFeedViewModel

    init(persistence: FeedPersisting) {
        _viewModel = State(initialValue: AddFeedViewModel(persistence: persistence))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(
                        text: $viewModel.urlInput,
                        prompt: Text("https://example.com/feed")
                    ) {
                        Text("Feed URL")
                    }
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .textContentType(.URL)
                } header: {
                    Text("Feed URL")
                } footer: {
                    Text("Enter the URL of an RSS feed.")
                }

                if let error = viewModel.errorMessage {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button {
                        Task { await viewModel.addFeed() }
                    } label: {
                        if viewModel.isValidating {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text("Validating…")
                            }
                        } else {
                            Text("Add Feed")
                        }
                    }
                    .disabled(!viewModel.canSubmit)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Add Feed")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onChange(of: viewModel.didAddFeed) { _, newValue in
                if newValue { dismiss() }
            }
        }
    }
}
