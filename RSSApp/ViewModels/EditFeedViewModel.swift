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
    private(set) var didSave = false

    var canSubmit: Bool {
        !urlInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isValidating
    }

    private let feed: PersistentFeed
    private let feedFetching: FeedFetching
    private let persistence: FeedPersisting

    init(
        feed: PersistentFeed,
        feedFetching: FeedFetching = FeedFetchingService(),
        persistence: FeedPersisting
    ) {
        self.feed = feed
        self.urlInput = feed.feedURL.absoluteString
        self.feedFetching = feedFetching
        self.persistence = persistence
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
            Self.logger.debug("Invalid URL input: '\(self.urlInput, privacy: .public)'")
            return
        }

        // No change — dismiss without saving
        if url == feed.feedURL {
            Self.logger.debug("URL unchanged, dismissing without save")
            didSave = true
            return
        }

        // Check for duplicates against other feeds
        do {
            if try persistence.feedExists(url: url) {
                errorMessage = "Another feed already uses this URL."
                Self.logger.debug("Duplicate feed URL: '\(url, privacy: .public)'")
                return
            }
        } catch {
            errorMessage = "Unable to load existing feeds. Please try again."
            Self.logger.error("Failed to check for duplicate: \(error, privacy: .public)")
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

        do {
            try persistence.updateFeedURL(feed, newURL: url)
            try persistence.updateFeedMetadata(feed, title: rssFeed.title, description: rssFeed.feedDescription)
        } catch {
            errorMessage = "Unable to save changes. Please try again."
            Self.logger.error("Failed to persist edited feed: \(error, privacy: .public)")
            return
        }

        didSave = true
        Self.logger.notice("Updated feed '\(rssFeed.title, privacy: .public)' URL to \(url, privacy: .public)")
    }
}
