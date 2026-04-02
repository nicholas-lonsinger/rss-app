import Foundation
import os

@MainActor
@Observable
final class EditFeedViewModel {

    private static let logger = Logger(
        subsystem: "com.nicholas-lonsinger.rss-app",
        category: "EditFeedViewModel"
    )

    var urlInput: String
    private(set) var isValidating = false
    private(set) var errorMessage: String?
    private(set) var updatedFeed: SubscribedFeed?

    var canSubmit: Bool {
        !urlInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isValidating
    }

    private let feed: SubscribedFeed
    private let feedFetching: FeedFetching
    private let feedStorage: FeedStoring

    init(
        feed: SubscribedFeed,
        feedFetching: FeedFetching = FeedFetchingService(),
        feedStorage: FeedStoring = FeedStorageService()
    ) {
        self.feed = feed
        self.urlInput = feed.url.absoluteString
        self.feedFetching = feedFetching
        self.feedStorage = feedStorage
    }

    func saveFeed() async {
        guard !isValidating else { return }
        Self.logger.debug("saveFeed() called with input: '\(self.urlInput, privacy: .public)'")
        errorMessage = nil

        let url: URL
        switch FeedURLValidator.validate(urlInput) {
        case .success(let validURL):
            url = validURL
        case .failure:
            errorMessage = "Invalid URL. Please enter a valid feed address."
            Self.logger.info("Invalid URL input: '\(self.urlInput, privacy: .public)'")
            return
        }

        // No change — dismiss without saving
        if url == feed.url {
            Self.logger.debug("URL unchanged, dismissing without save")
            updatedFeed = feed
            return
        }

        // Check for duplicates against other feeds
        var existingFeeds: [SubscribedFeed]
        do {
            existingFeeds = try feedStorage.loadFeeds()
        } catch {
            errorMessage = "Unable to load existing feeds. Please try again."
            Self.logger.error("Failed to load feeds: \(error, privacy: .public)")
            return
        }

        if existingFeeds.contains(where: { $0.url == url && $0.id != feed.id }) {
            errorMessage = "Another feed already uses this URL."
            Self.logger.info("Duplicate feed URL: '\(url, privacy: .public)'")
            return
        }

        isValidating = true
        defer { isValidating = false }

        let rssFeed: RSSFeed
        do {
            rssFeed = try await feedFetching.fetchFeed(from: url)
        } catch {
            errorMessage = "Could not load feed. Check the URL and try again."
            Self.logger.error("Feed validation failed for \(url, privacy: .public): \(error, privacy: .public)")
            return
        }

        let updated = feed
            .updatingURL(url)
            .updatingMetadata(title: rssFeed.title, feedDescription: rssFeed.feedDescription)

        guard let index = existingFeeds.firstIndex(where: { $0.id == feed.id }) else {
            errorMessage = "This feed no longer exists."
            Self.logger.warning("Feed \(self.feed.id, privacy: .public) not found in storage during edit save")
            return
        }
        existingFeeds[index] = updated

        do {
            try feedStorage.saveFeeds(existingFeeds)
        } catch {
            errorMessage = "Unable to save changes. Please try again."
            Self.logger.error("Failed to persist edited feed: \(error, privacy: .public)")
            return
        }

        updatedFeed = updated
        Self.logger.notice("Updated feed '\(rssFeed.title, privacy: .public)' URL to \(url, privacy: .public)")
    }
}
