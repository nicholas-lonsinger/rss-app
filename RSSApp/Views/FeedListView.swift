import SwiftUI
import UniformTypeIdentifiers

struct FeedListView: View {
    @State private var viewModel = FeedListViewModel()
    @State private var showAddFeed = false
    @State private var showSettings = false
    @State private var showFileImporter = false
    @State private var showExportShare = false
    @State private var showImportResult = false

    private static let opmlContentTypes: [UTType] = {
        var types: [UTType] = [.xml]
        if let opmlType = UTType(filenameExtension: "opml") {
            types.insert(opmlType, at: 0)
        }
        return types
    }()

    var body: some View {
        NavigationStack {
            feedContent
                .navigationTitle("Feeds")
                .navigationDestination(for: SubscribedFeed.self) { feed in
                    ArticleListView(viewModel: FeedViewModel(feedURL: feed.url))
                }
                .toolbar { toolbarItems }
                .sheet(isPresented: $showAddFeed, onDismiss: {
                    viewModel.loadFeeds()
                }) {
                    AddFeedView()
                }
                .sheet(isPresented: $showSettings) {
                    APIKeySettingsView()
                }
                .sheet(isPresented: $showExportShare, onDismiss: {
                    viewModel.opmlExportData = nil
                }) {
                    exportShareSheet
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
                .onChange(of: viewModel.opmlExportData) { _, newValue in
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
                ForEach(viewModel.feeds) { feed in
                    NavigationLink(value: feed) {
                        FeedRowView(feed: feed)
                    }
                }
                .onDelete { offsets in
                    viewModel.removeFeed(at: offsets)
                }
            }
            .listStyle(.plain)
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

    @ViewBuilder
    private var exportShareSheet: some View {
        if let data = viewModel.opmlExportData {
            ActivityShareView(items: [writeExportFile(data)])
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
            viewModel.importOPML(from: url)
        case .failure:
            viewModel.errorMessage = "Unable to open the file picker."
        }
    }

    private func writeExportFile(_ data: Data) -> URL {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("RSS Subscriptions.opml")
        do {
            try data.write(to: tempURL)
        } catch {
            viewModel.errorMessage = "Unable to write export file."
        }
        return tempURL
    }
}
