import SwiftUI

struct EditFeedView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: EditFeedViewModel

    init(feed: SubscribedFeed) {
        _viewModel = State(initialValue: EditFeedViewModel(feed: feed))
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
            .onChange(of: viewModel.updatedFeed) { _, newValue in
                if newValue != nil { dismiss() }
            }
        }
    }
}
