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

                if !viewModel.allGroups.isEmpty {
                    Section {
                        ForEach(viewModel.allGroups, id: \.id) { group in
                            Button {
                                viewModel.toggleGroupMembership(group)
                            } label: {
                                HStack {
                                    Label(group.name, systemImage: "folder")
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    if viewModel.memberGroupIDs.contains(group.id) {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.tint)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        Text("Groups")
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
            .task {
                viewModel.loadGroups()
            }
            .onChange(of: viewModel.didSave) { _, newValue in
                if newValue { dismiss() }
            }
            .atomFeedAlerts(
                atomAlternatePrompt: $viewModel.atomAlternatePrompt,
                atomFallbackNotice: $viewModel.atomFallbackNotice,
                switchToAtom: { prompt in await viewModel.switchToAtomAlternate(from: prompt) },
                keepRSS: { prompt in viewModel.keepOriginalFeed(from: prompt) },
                actionVerb: .saved
            )
        }
    }
}
