import Foundation
import os

@MainActor
@Observable
final class AddFeedViewModel {

    private static let logger = Logger(
        subsystem: "com.nicholas-lonsinger.rss-app",
        category: "AddFeedViewModel"
    )

    var urlInput: String = ""
    var isValidating = false
    var errorMessage: String?
    var didAddFeed = false

    var canSubmit: Bool {
        !urlInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isValidating
    }

    private let feedFetching: FeedFetching
    private let persistence: FeedPersisting

    init(feedFetching: FeedFetching = FeedFetchingService(), persistence: FeedPersisting) {
        self.feedFetching = feedFetching
        self.persistence = persistence
    }

    func addFeed() async {
        Self.logger.debug("addFeed() called with input: '\(self.urlInput, privacy: .public)'")
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

        do {
            if try persistence.feedExists(url: url) {
                errorMessage = "You are already subscribed to this feed."
                Self.logger.info("Duplicate feed URL: '\(url, privacy: .public)'")
                return
            }
        } catch {
            errorMessage = "Unable to load existing feeds. Please try again."
            Self.logger.error("Failed to check for duplicate: \(error, privacy: .public)")
            return
        }

        isValidating = true
        defer { isValidating = false }

        do {
            let rssFeed = try await feedFetching.fetchFeed(from: url)
            let newFeed = PersistentFeed(
                title: rssFeed.title,
                feedURL: url,
                feedDescription: rssFeed.feedDescription
            )
            try persistence.addFeed(newFeed)
            didAddFeed = true
            Self.logger.notice("Added feed '\(rssFeed.title, privacy: .public)' from \(url, privacy: .public)")
        } catch {
            errorMessage = "Could not load feed. Check the URL and try again."
            Self.logger.error("Feed validation failed for \(url, privacy: .public): \(error, privacy: .public)")
        }
    }
}
