import Foundation
import os

@MainActor
@Observable
final class AddFeedViewModel {

    private static let logger = Logger(
        subsystem: Logger.appSubsystem,
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
    private let feedIconService: FeedIconResolving

    init(
        feedFetching: FeedFetching = FeedFetchingService(),
        persistence: FeedPersisting,
        feedIconService: FeedIconResolving = FeedIconService()
    ) {
        self.feedFetching = feedFetching
        self.persistence = persistence
        self.feedIconService = feedIconService
    }

    func addFeed() async {
        guard !isValidating else { return }
        Self.logger.debug("addFeed() called with input: '\(self.urlInput, privacy: .public)'")
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

        do {
            if try persistence.feedExists(url: url) {
                errorMessage = "You are already subscribed to this feed."
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

            // Fire-and-forget icon resolution
            let iconService = self.feedIconService
            let feedTitle = rssFeed.title
            let siteURL = rssFeed.link
            let feedImageURL = rssFeed.imageURL
            let persistenceRef = self.persistence
            Task {
                guard let iconURL = await iconService.resolveAndCacheIcon(
                    feedSiteURL: siteURL,
                    feedImageURL: feedImageURL,
                    feedID: newFeed.id
                ) else { return }
                do {
                    try persistenceRef.updateFeedIcon(newFeed, iconURL: iconURL)
                    try persistenceRef.save()
                } catch {
                    Self.logger.error("Failed to persist icon for '\(feedTitle, privacy: .public)': \(error, privacy: .public)")
                }
            }
        } catch {
            errorMessage = "Could not load feed. Check the URL and try again."
            Self.logger.error("Feed validation failed for \(url, privacy: .public): \(error, privacy: .public)")
        }
    }
}
