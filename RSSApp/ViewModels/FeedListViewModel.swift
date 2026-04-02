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
    private(set) var isRefreshing = false
    var errorMessage: String?
    var opmlImportResult: OPMLImportResult?
    var opmlExportURL: URL?

    private let feedStorage: FeedStoring
    private let opmlService: OPMLServing
    private let feedFetching: FeedFetching

    init(
        feedStorage: FeedStoring = FeedStorageService(),
        opmlService: OPMLServing = OPMLService(),
        feedFetching: FeedFetching = FeedFetchingService()
    ) {
        self.feedStorage = feedStorage
        self.opmlService = opmlService
        self.feedFetching = feedFetching
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
        guard let data = readSecurityScopedData(from: url) else { return }
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

        var updatedFeeds = feeds
        var seenURLs = Set(updatedFeeds.map(\.url))
        var addedCount = 0
        var skippedCount = 0

        for entry in entries {
            if seenURLs.contains(entry.feedURL) {
                skippedCount += 1
                Self.logger.debug("Skipped duplicate: \(entry.feedURL.absoluteString, privacy: .public)")
            } else {
                seenURLs.insert(entry.feedURL)
                updatedFeeds.append(SubscribedFeed(
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
            try feedStorage.saveFeeds(updatedFeeds)
            feeds = updatedFeeds
            opmlImportResult = OPMLImportResult(
                addedCount: addedCount,
                skippedCount: skippedCount
            )
            errorMessage = nil
            Self.logger.notice("OPML import: added \(addedCount, privacy: .public), skipped \(skippedCount, privacy: .public)")
        } catch {
            errorMessage = "Unable to save imported feeds."
            Self.logger.error("Failed to persist OPML import: \(error, privacy: .public)")
        }
    }

    func exportOPML() {
        Self.logger.debug("exportOPML() called")
        do {
            let data = try opmlService.generateOPML(from: feeds)
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("RSS Subscriptions.opml")
            try data.write(to: tempURL)
            opmlExportURL = tempURL
        } catch {
            errorMessage = "Unable to export feeds."
            Self.logger.error("OPML export failed: \(error, privacy: .public)")
        }
    }

    // MARK: - OPML Import with Refresh

    func importOPMLAndRefresh(from url: URL) async {
        guard let data = readSecurityScopedData(from: url) else { return }
        await importOPMLAndRefresh(from: data)
    }

    func importOPMLAndRefresh(from data: Data) async {
        importOPML(from: data)
        guard let result = opmlImportResult, result.addedCount > 0 else { return }
        await refreshAllFeeds()
    }

    // MARK: - Helpers

    private func readSecurityScopedData(from url: URL) -> Data? {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        do {
            return try Data(contentsOf: url)
        } catch {
            errorMessage = "Unable to read the selected file."
            Self.logger.error("Failed to read OPML file: \(error, privacy: .public)")
            return nil
        }
    }

    // MARK: - Feed Metadata Refresh

    func refreshAllFeeds() async {
        Self.logger.debug("refreshAllFeeds() called for \(self.feeds.count, privacy: .public) feeds")
        guard !feeds.isEmpty, !isRefreshing else { return }
        errorMessage = nil
        isRefreshing = true
        defer { isRefreshing = false }

        let feedsToRefresh = feeds
        let feedFetching = self.feedFetching
        let logger = Self.logger
        let maxConcurrency = 6

        let results: [(UUID, Result<RSSFeed, any Error>)]
        do {
            results = try await withThrowingTaskGroup(
            of: (UUID, Result<RSSFeed, any Error>).self,
            returning: [(UUID, Result<RSSFeed, any Error>)].self
        ) { group in
            var collected: [(UUID, Result<RSSFeed, any Error>)] = []
            var iterator = feedsToRefresh.makeIterator()

            func enqueueNext(_ group: inout ThrowingTaskGroup<(UUID, Result<RSSFeed, any Error>), any Error>, _ iterator: inout IndexingIterator<[SubscribedFeed]>) -> Bool {
                guard let feed = iterator.next() else { return false }
                group.addTask {
                    do {
                        let rssFeed = try await feedFetching.fetchFeed(from: feed.url)
                        return (feed.id, .success(rssFeed))
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        logger.warning("Failed to refresh '\(feed.title, privacy: .public)' (\(feed.url.absoluteString, privacy: .public)): \(error, privacy: .public)")
                        return (feed.id, .failure(error))
                    }
                }
                return true
            }

            for _ in 0..<maxConcurrency {
                guard enqueueNext(&group, &iterator) else { break }
            }

            for try await result in group {
                collected.append(result)
                _ = enqueueNext(&group, &iterator)
            }

            return collected
        }
        } catch {
            Self.logger.debug("refreshAllFeeds() cancelled")
            return
        }

        var updatedFeeds = feeds
        let idToIndex = Dictionary(uniqueKeysWithValues: updatedFeeds.enumerated().map { ($1.id, $0) })
        var failureCount = 0
        for (id, result) in results {
            guard let index = idToIndex[id] else { continue }
            switch result {
            case .success(let rssFeed):
                updatedFeeds[index] = updatedFeeds[index].updatingMetadata(
                    title: rssFeed.title,
                    feedDescription: rssFeed.feedDescription
                )
            case .failure(let error):
                failureCount += 1
                updatedFeeds[index] = updatedFeeds[index].updatingError(Self.errorDescription(for: error))
            }
        }

        if updatedFeeds != feeds {
            let previousFeeds = feeds
            feeds = updatedFeeds
            do {
                try feedStorage.saveFeeds(updatedFeeds)
            } catch {
                feeds = previousFeeds
                errorMessage = "Unable to save updated feeds."
                Self.logger.error("Failed to persist refreshed feeds: \(error, privacy: .public)")
                return
            }
        }
        Self.logger.notice("Refresh complete: \(updatedFeeds.count - failureCount, privacy: .public) updated, \(failureCount, privacy: .public) failed")

        if failureCount > 0 {
            errorMessage = "\(failureCount) of \(feedsToRefresh.count) feed(s) could not be updated."
        }
    }

    private static func errorDescription(for error: any Error) -> String {
        switch error {
        case let fetchError as FeedFetchingError:
            switch fetchError {
            case .invalidResponse(let statusCode):
                return "HTTP \(statusCode)"
            case .invalidFeedURL:
                return "Invalid feed URL"
            }
        case is URLError:
            return "Network error"
        default:
            return "Fetch failed"
        }
    }
}
