import SwiftUI

struct EditGroupView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: EditGroupViewModel

    init(group: PersistentFeedGroup, persistence: FeedPersisting) {
        _viewModel = State(initialValue: EditGroupViewModel(group: group, persistence: persistence))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Group name", text: $viewModel.name)
                        .autocorrectionDisabled()
                } header: {
                    Text("Name")
                }

                if let error = viewModel.errorMessage {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    if viewModel.allFeeds.isEmpty {
                        Text("No feeds added yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(viewModel.allFeeds, id: \.id) { feed in
                            Button {
                                viewModel.toggleMembership(for: feed)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(feed.title)
                                            .foregroundStyle(.primary)
                                        Text(feed.feedURL.absoluteString)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    if viewModel.memberFeedIDs.contains(feed.id) {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.blue)
                                    }
                                }
                            }
                        }
                    }
                } header: {
                    Text("Feeds")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Edit Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        viewModel.saveNameIfChanged()
                        dismiss()
                    }
                }
            }
            .task {
                viewModel.loadFeeds()
            }
        }
    }
}
