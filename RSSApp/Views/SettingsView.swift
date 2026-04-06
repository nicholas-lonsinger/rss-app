import SwiftUI
import UIKit
import UniformTypeIdentifiers
import os

struct SettingsView: View {

    private static let logger = Logger(category: "SettingsView")

    let persistence: FeedPersisting
    let viewModel: FeedListViewModel
    let homeViewModel: HomeViewModel

    @State private var badgeEnabled: Bool
    @State private var showPermissionDeniedAlert = false
    // RATIONALE: Concrete AppBadgeService instead of `any AppBadgeUpdating` because
    // the protocol's `badgeEnabled` setter requires mutable access through existentials,
    // which is incompatible with SwiftUI's immutable view structs. Protocol abstraction
    // is used in HomeViewModel for testing.
    private let badgeService: AppBadgeService

    init(persistence: FeedPersisting, viewModel: FeedListViewModel, homeViewModel: HomeViewModel, badgeService: AppBadgeService = AppBadgeService()) {
        self.persistence = persistence
        self.viewModel = viewModel
        self.homeViewModel = homeViewModel
        self.badgeService = badgeService
        _badgeEnabled = State(initialValue: badgeService.badgeEnabled)
    }

    var body: some View {
        List {
            Toggle(isOn: $badgeEnabled) {
                Label("App Badge", systemImage: "app.badge")
            }
            .onChange(of: badgeEnabled) { _, newValue in
                badgeService.badgeEnabled = newValue
                Task {
                    if newValue {
                        let status = await badgeService.checkPermission()
                        if status == .denied {
                            Self.logger.notice("Badge toggle enabled but notification permission denied — reverting toggle and showing alert")
                            badgeEnabled = false
                            badgeService.badgeEnabled = false
                            showPermissionDeniedAlert = true
                        } else {
                            await homeViewModel.updateBadge()
                        }
                    } else {
                        await badgeService.clearBadge()
                    }
                }
            }

            NavigationLink {
                APIKeySettingsView()
            } label: {
                Label("API Key", systemImage: "key")
            }

            NavigationLink {
                ArticleLimitView(persistence: persistence)
            } label: {
                Label("Article Limit", systemImage: "tray.full")
            }

            NavigationLink {
                ImportExportView(persistence: persistence, viewModel: viewModel)
            } label: {
                Label("Import / Export", systemImage: "arrow.up.arrow.down")
            }
        }
        .navigationTitle("Settings")
        .alert("Notifications Disabled", isPresented: $showPermissionDeniedAlert) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Badge notifications require permission. Please enable notifications for this app in Settings.")
        }
    }
}

// MARK: - Article Limit Sub-screen

struct ArticleLimitView: View {

    private static let logger = Logger(category: "ArticleLimitView")

    @State private var selectedLimit: ArticleLimit
    private let retentionService: ArticleRetentionService
    private let persistence: FeedPersisting
    private let thumbnailService: ArticleThumbnailCaching

    /// The limit when the view appeared, used to detect whether the user lowered it.
    @State private var limitOnAppear: ArticleLimit?

    init(
        persistence: FeedPersisting,
        retentionService: ArticleRetentionService = ArticleRetentionService(),
        thumbnailService: ArticleThumbnailCaching = ArticleThumbnailService()
    ) {
        self.persistence = persistence
        self.retentionService = retentionService
        self.thumbnailService = thumbnailService
        _selectedLimit = State(initialValue: retentionService.articleLimit)
    }

    var body: some View {
        List {
            Section {
                ForEach(ArticleLimit.allCases) { limit in
                    Button {
                        selectedLimit = limit
                        retentionService.articleLimit = limit
                    } label: {
                        HStack {
                            Text(limit.displayLabel)
                                .foregroundStyle(.primary)
                            Spacer()
                            if limit == selectedLimit {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                                    .fontWeight(.semibold)
                            }
                        }
                    }
                }
            } footer: {
                Text("The maximum number of articles stored across all feeds. Oldest articles are removed when the limit is exceeded.")
            }
        }
        .navigationTitle("Article Limit")
        .onAppear {
            limitOnAppear = retentionService.articleLimit
        }
        .onDisappear {
            guard let initial = limitOnAppear else {
                Self.logger.warning("limitOnAppear was nil at disappear time — skipping retention enforcement")
                return
            }
            guard selectedLimit.rawValue < initial.rawValue else { return }
            Task {
                do {
                    try retentionService.enforceArticleLimit(
                        persistence: persistence,
                        thumbnailService: thumbnailService
                    )
                } catch {
                    // RATIONALE: onDisappear fires as this view leaves the navigation stack, so presenting
                    // an alert here is unreliable. The error is logged for diagnostics; enforcement will
                    // retry automatically on the next feed refresh.
                    Self.logger.error("Article retention cleanup on settings exit failed: \(error, privacy: .public)")
                }
            }
        }
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
