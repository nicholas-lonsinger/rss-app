import SwiftUI

struct AddFeedView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = AddFeedViewModel()

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
            .onChange(of: viewModel.addedFeed) { _, newValue in
                if newValue != nil { dismiss() }
            }
        }
    }
}
