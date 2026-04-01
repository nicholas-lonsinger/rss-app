import Foundation
import os

@MainActor
@Observable
final class FeedListViewModel {

    private static let logger = Logger(
        subsystem: "com.nicholas-lonsinger.rss-app",
        category: "FeedListViewModel"
    )

    private(set) var feeds: [SubscribedFeed] = []
    var errorMessage: String?
    var opmlImportResult: OPMLImportResult?
    var opmlExportData: Data?

    private let feedStorage: FeedStoring
    private let opmlService: OPMLServing

    init(feedStorage: FeedStoring = FeedStorageService(), opmlService: OPMLServing = OPMLService()) {
        self.feedStorage = feedStorage
        self.opmlService = opmlService
    }

    func loadFeeds() {
        do {
            feeds = try feedStorage.loadFeeds()
            errorMessage = nil
            Self.logger.debug("Loaded \(self.feeds.count, privacy: .public) feeds")
        } catch {
            errorMessage = "Unable to load your feeds."
            Self.logger.error("Failed to load feeds: \(error, privacy: .public)")
        }
    }

    func removeFeed(_ feed: SubscribedFeed) {
        let previousFeeds = feeds
        feeds.removeAll { $0.id == feed.id }
        do {
            try feedStorage.saveFeeds(feeds)
            Self.logger.notice("Removed feed '\(feed.title, privacy: .public)'")
        } catch {
            feeds = previousFeeds
            errorMessage = "Unable to save changes."
            Self.logger.error("Failed to persist feed removal: \(error, privacy: .public)")
        }
    }

    func removeFeed(at offsets: IndexSet) {
        let previousFeeds = feeds
        let removed = offsets.map { feeds[$0] }
        feeds.remove(atOffsets: offsets)
        do {
            try feedStorage.saveFeeds(feeds)
            for feed in removed {
                Self.logger.notice("Removed feed '\(feed.title, privacy: .public)'")
            }
        } catch {
            feeds = previousFeeds
            errorMessage = "Unable to save changes."
            Self.logger.error("Failed to persist feed removal: \(error, privacy: .public)")
        }
    }

    // MARK: - OPML Import/Export

    func importOPML(from url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            errorMessage = "Unable to read the selected file."
            Self.logger.error("Failed to read OPML file: \(error, privacy: .public)")
            return
        }

        importOPML(from: data)
    }

    func importOPML(from data: Data) {
        Self.logger.debug("importOPML() called with \(data.count, privacy: .public) bytes")

        let entries: [OPMLFeedEntry]
        do {
            entries = try opmlService.parseOPML(data)
        } catch {
            errorMessage = "Unable to import feeds. The file may be invalid."
            Self.logger.error("OPML parse failed: \(error, privacy: .public)")
            return
        }

        let previousFeeds = feeds
        var seenURLs = Set(feeds.map(\.url))
        var addedCount = 0
        var skippedCount = 0

        for entry in entries {
            if seenURLs.contains(entry.feedURL) {
                skippedCount += 1
                Self.logger.debug("Skipped duplicate: \(entry.feedURL.absoluteString, privacy: .public)")
            } else {
                seenURLs.insert(entry.feedURL)
                feeds.append(SubscribedFeed(
                    id: UUID(),
                    title: entry.title,
                    url: entry.feedURL,
                    feedDescription: entry.description,
                    addedDate: Date()
                ))
                addedCount += 1
            }
        }

        do {
            try feedStorage.saveFeeds(feeds)
            opmlImportResult = OPMLImportResult(
                addedCount: addedCount,
                skippedCount: skippedCount
            )
            errorMessage = nil
            Self.logger.notice("OPML import: added \(addedCount, privacy: .public), skipped \(skippedCount, privacy: .public)")
        } catch {
            feeds = previousFeeds
            errorMessage = "Unable to save imported feeds."
            Self.logger.error("Failed to persist OPML import: \(error, privacy: .public)")
        }
    }

    func exportOPML() {
        Self.logger.debug("exportOPML() called")
        do {
            opmlExportData = try opmlService.generateOPML(from: feeds)
        } catch {
            errorMessage = "Unable to export feeds."
            Self.logger.error("OPML export failed: \(error, privacy: .public)")
        }
    }
}
