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
    var addedFeed: SubscribedFeed?

    var canSubmit: Bool {
        !urlInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isValidating
    }

    private let feedFetching: FeedFetching
    private let feedStorage: FeedStoring

    init(feedFetching: FeedFetching = FeedFetchingService(), feedStorage: FeedStoring = FeedStorageService()) {
        self.feedFetching = feedFetching
        self.feedStorage = feedStorage
    }

    func addFeed() async {
        Self.logger.debug("addFeed() called with input: '\(self.urlInput, privacy: .public)'")
        errorMessage = nil

        var trimmed = urlInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty && !trimmed.contains("://") {
            trimmed = "https://" + trimmed
        }

        guard let url = URL(string: trimmed), url.scheme != nil, url.host != nil else {
            errorMessage = "Invalid URL. Please enter a valid feed address."
            Self.logger.info("Invalid URL input: '\(trimmed, privacy: .public)'")
            return
        }

        var existingFeeds = feedStorage.loadFeeds()
        if existingFeeds.contains(where: { $0.url == url }) {
            errorMessage = "You are already subscribed to this feed."
            Self.logger.info("Duplicate feed URL: '\(url, privacy: .public)'")
            return
        }

        isValidating = true
        defer { isValidating = false }

        do {
            let rssFeed = try await feedFetching.fetchFeed(from: url)
            let subscribedFeed = SubscribedFeed(
                id: UUID(),
                title: rssFeed.title,
                url: url,
                feedDescription: rssFeed.feedDescription,
                addedDate: Date()
            )
            existingFeeds.append(subscribedFeed)
            feedStorage.saveFeeds(existingFeeds)
            addedFeed = subscribedFeed
            Self.logger.notice("Added feed '\(rssFeed.title, privacy: .public)' from \(url, privacy: .public)")
        } catch {
            errorMessage = "Could not load feed. Check the URL and try again."
            Self.logger.error("Feed validation failed for \(url, privacy: .public): \(error, privacy: .public)")
        }
    }
}
