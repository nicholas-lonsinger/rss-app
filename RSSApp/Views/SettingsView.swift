import SwiftUI
import UniformTypeIdentifiers
import os

struct SettingsView: View {

    let persistence: FeedPersisting
    let viewModel: FeedListViewModel

    var body: some View {
        List {
            NavigationLink {
                APIKeySettingsView()
            } label: {
                Label("API Key", systemImage: "key")
            }

            NavigationLink {
                ImportExportView(persistence: persistence, viewModel: viewModel)
            } label: {
                Label("Import / Export", systemImage: "arrow.up.arrow.down")
            }
        }
        .navigationTitle("Settings")
    }
}

// MARK: - Import / Export Sub-screen

struct ImportExportView: View {

    private static let logger = Logger(category: "ImportExportView")

    let persistence: FeedPersisting
    let viewModel: FeedListViewModel

    @State private var showFileImporter = false
    @State private var showExportShare = false
    @State private var showImportResult = false
    @State private var showError = false

    // .opml is not a system-declared UTType on all iOS versions; .xml is the guaranteed fallback.
    private static let opmlContentTypes: [UTType] = {
        var types: [UTType] = [.xml]
        if let opmlType = UTType(filenameExtension: "opml") {
            types.insert(opmlType, at: 0)
        }
        return types
    }()

    var body: some View {
        List {
            Section {
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
            } footer: {
                Text("Import or export your feed subscriptions using OPML files.")
            }
        }
        .navigationTitle("Import / Export")
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: Self.opmlContentTypes
        ) { result in
            handleFileImport(result)
        }
        .sheet(isPresented: $showExportShare, onDismiss: {
            viewModel.opmlExportURL = nil
        }) {
            if let url = viewModel.opmlExportURL {
                ActivityShareView(items: [url])
            }
        }
        .alert("Import Complete", isPresented: $showImportResult, presenting: viewModel.opmlImportResult) { _ in
            Button("OK") { viewModel.opmlImportResult = nil }
        } message: { result in
            Text(importResultMessage(result))
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") { viewModel.importExportErrorMessage = nil }
        } message: {
            Text(viewModel.importExportErrorMessage ?? "")
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
        .onChange(of: viewModel.importExportErrorMessage) { _, newValue in
            if newValue != nil {
                showError = true
            }
        }
    }

    // MARK: - Helpers

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
            Self.logger.debug("File selected for import: \(url.lastPathComponent, privacy: .public)")
            Task {
                await viewModel.importOPMLAndRefresh(from: url)
            }
        case .failure(let error):
            Self.logger.error("File import failed: \(error, privacy: .public)")
            viewModel.importExportErrorMessage = "Unable to access the selected file."
        }
    }
}
