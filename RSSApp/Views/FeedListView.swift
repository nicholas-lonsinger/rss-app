import SwiftUI
import UniformTypeIdentifiers

struct FeedListView: View {
    @State private var viewModel: FeedListViewModel
    @State private var showAddFeed = false
    @State private var showSettings = false
    @State private var showFileImporter = false
    @State private var showExportShare = false
    @State private var showImportResult = false
    @State private var feedToEdit: PersistentFeed?

    private let persistence: FeedPersisting

    // .opml is not a system-declared UTType on all iOS versions; .xml is the guaranteed fallback.
    private static let opmlContentTypes: [UTType] = {
        var types: [UTType] = [.xml]
        if let opmlType = UTType(filenameExtension: "opml") {
            types.insert(opmlType, at: 0)
        }
        return types
    }()

    init(persistence: FeedPersisting) {
        self.persistence = persistence
        _viewModel = State(initialValue: FeedListViewModel(persistence: persistence))
    }

    var body: some View {
        NavigationStack {
            feedContent
                .navigationTitle("Feeds")
                .navigationDestination(for: PersistentFeed.ID.self) { feedID in
                    if let feed = viewModel.feeds.first(where: { $0.id == feedID }) {
                        ArticleListView(
                            viewModel: FeedViewModel(feed: feed, persistence: persistence)
                        )
                    }
                }
                .toolbar { toolbarItems }
                .sheet(isPresented: $showAddFeed, onDismiss: {
                    viewModel.loadFeeds()
                }) {
                    AddFeedView(persistence: persistence)
                }
                .sheet(isPresented: $showSettings) {
                    APIKeySettingsView()
                }
                .sheet(item: $feedToEdit, onDismiss: {
                    viewModel.loadFeeds()
                }) { feed in
                    EditFeedView(feed: feed, persistence: persistence)
                }
                .sheet(isPresented: $showExportShare, onDismiss: {
                    viewModel.opmlExportURL = nil
                }) {
                    if let url = viewModel.opmlExportURL {
                        ActivityShareView(items: [url])
                    }
                }
                .fileImporter(
                    isPresented: $showFileImporter,
                    allowedContentTypes: Self.opmlContentTypes
                ) { result in
                    handleFileImport(result)
                }
                .alert("Import Complete", isPresented: $showImportResult, presenting: viewModel.opmlImportResult) { _ in
                    Button("OK") { viewModel.opmlImportResult = nil }
                } message: { result in
                    Text(importResultMessage(result))
                }
                .alert("Error", isPresented: errorAlertBinding) {
                    Button("OK") { viewModel.errorMessage = nil }
                } message: {
                    Text(viewModel.errorMessage ?? "")
                }
                .onChange(of: viewModel.opmlExportURL) { _, newValue in
                    if newValue != nil {
                        showExportShare = true
                    }
                }
                .onChange(of: viewModel.opmlImportResult) { _, newValue in
                    if newValue != nil {
                        showImportResult = true
                    }
                }
                .task {
                    viewModel.loadFeeds()
                }
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var feedContent: some View {
        if viewModel.feeds.isEmpty {
            ContentUnavailableView {
                Label("No Feeds", systemImage: "plus.circle")
            } description: {
                Text("Add an RSS feed to get started.")
            } actions: {
                Button("Add Feed") {
                    showAddFeed = true
                }
                .buttonStyle(.bordered)
            }
        } else {
            List {
                ForEach(viewModel.feeds, id: \.id) { feed in
                    NavigationLink(value: feed.id) {
                        FeedRowView(
                            feed: feed,
                            unreadCount: viewModel.unreadCount(for: feed)
                        )
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            feedToEdit = feed
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .tint(.blue)
                    }
                }
                .onDelete { offsets in
                    viewModel.removeFeed(at: offsets)
                }
            }
            .listStyle(.plain)
            .refreshable {
                await viewModel.refreshAllFeeds()
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                showAddFeed = true
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel("Add Feed")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button {
                    showFileImporter = true
                } label: {
                    Label("Import Feeds", systemImage: "square.and.arrow.down")
                }

                Button {
                    viewModel.exportOPML()
                } label: {
                    Label("Export Feeds", systemImage: "square.and.arrow.up")
                }
                .disabled(viewModel.feeds.isEmpty)

                Divider()

                Button {
                    showSettings = true
                } label: {
                    Label("Settings", systemImage: "gear")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityLabel("More Options")
        }
    }

    // MARK: - Helpers

    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )
    }

    private func importResultMessage(_ result: OPMLImportResult) -> String {
        if result.addedCount == 0 && result.skippedCount > 0 {
            return "All \(result.skippedCount) feeds were already in your list."
        } else if result.skippedCount == 0 {
            return "Added \(result.addedCount) feed(s)."
        } else {
            return "Added \(result.addedCount) feed(s). \(result.skippedCount) duplicate(s) skipped."
        }
    }

    private func handleFileImport(_ result: Result<URL, any Error>) {
        switch result {
        case .success(let url):
            Task {
                await viewModel.importOPMLAndRefresh(from: url)
            }
        case .failure:
            viewModel.errorMessage = "Unable to open the file picker."
        }
    }
}
