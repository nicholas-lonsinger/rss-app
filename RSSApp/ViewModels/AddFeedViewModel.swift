import Foundation
import os

@MainActor
@Observable
final class AddFeedViewModel {

    private static let logger = Logger(category: "AddFeedViewModel")

    /// Prompt payload surfaced when an Atom alternative is discovered for an
    /// RSS feed the user is about to add. The view binds to this to drive a
    /// two-button alert ("Switch to Atom" / "Keep RSS"); both branches resume
    /// the add flow via `switchToAtomAlternate()` / `keepOriginalFeed()`.
    struct AtomAlternatePrompt {
        let originalURL: URL
        let atomURL: URL
        let originalFeed: RSSFeed
    }

    var urlInput: String = ""
    var isValidating = false
    var errorMessage: String?
    var didAddFeed = false
    var atomAlternatePrompt: AtomAlternatePrompt?

    var canSubmit: Bool {
        !urlInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isValidating
    }

    private let feedFetching: FeedFetching
    private let persistence: FeedPersisting
    private let feedIconService: FeedIconResolving
    private let atomDiscovery: any AtomDiscovering

    init(
        feedFetching: FeedFetching = FeedFetchingService(),
        persistence: FeedPersisting,
        feedIconService: FeedIconResolving = FeedIconService(),
        atomDiscovery: any AtomDiscovering = AtomDiscoveryService()
    ) {
        self.feedFetching = feedFetching
        self.persistence = persistence
        self.feedIconService = feedIconService
        self.atomDiscovery = atomDiscovery
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

        let rssFeed: RSSFeed
        do {
            rssFeed = try await feedFetching.fetchFeed(from: url)
        } catch {
            errorMessage = "Could not load feed. Check the URL and try again."
            Self.logger.error("Feed validation failed for \(url, privacy: .public): \(error, privacy: .public)")
            return
        }

        // If the user picked an RSS feed and the site advertises an Atom
        // alternative, pause here and let them choose. `keepOriginalFeed()` or
        // `switchToAtomAlternate()` will complete the flow.
        if rssFeed.format == .rss,
           let atomURL = await atomDiscovery.discoverAtomAlternate(forFeedAt: url) {
            Self.logger.notice("Offering Atom alternate \(atomURL.absoluteString, privacy: .public) for \(url.absoluteString, privacy: .public)")
            atomAlternatePrompt = AtomAlternatePrompt(
                originalURL: url,
                atomURL: atomURL,
                originalFeed: rssFeed
            )
            return
        }

        persistFetchedFeed(rssFeed, url: url)
    }

    /// User dismissed the Atom prompt by choosing to keep the RSS feed as-is.
    /// Persists the feed that was already fetched in `addFeed()` so we avoid a
    /// second network round-trip.
    ///
    /// The caller (alert button action) must pass the `prompt` value captured
    /// from the alert's `presenting:` closure rather than relying on
    /// `atomAlternatePrompt` still being set. SwiftUI's `.alert(isPresented:)`
    /// binding setter clears the prompt state as part of dismissing the alert,
    /// so by the time a deferred `Task` body runs, reading the view-model
    /// property would race with that dismissal and often return nil.
    func keepOriginalFeed(from prompt: AtomAlternatePrompt) {
        Self.logger.notice("User kept RSS feed \(prompt.originalURL.absoluteString, privacy: .public), declining Atom \(prompt.atomURL.absoluteString, privacy: .public)")
        atomAlternatePrompt = nil
        persistFetchedFeed(prompt.originalFeed, url: prompt.originalURL)
    }

    /// User accepted the Atom prompt. Fetches the discovered Atom URL and
    /// persists that feed instead of the original RSS one.
    ///
    /// See the note on `keepOriginalFeed(from:)` — the prompt must be passed
    /// in by the caller rather than re-read from `atomAlternatePrompt`, which
    /// will have been cleared by the alert's dismissal binding by the time
    /// this task runs.
    func switchToAtomAlternate(from prompt: AtomAlternatePrompt) async {
        Self.logger.notice("User switching to Atom \(prompt.atomURL.absoluteString, privacy: .public) from \(prompt.originalURL.absoluteString, privacy: .public)")
        let atomURL = prompt.atomURL
        atomAlternatePrompt = nil
        urlInput = atomURL.absoluteString

        isValidating = true
        defer { isValidating = false }

        do {
            if try persistence.feedExists(url: atomURL) {
                errorMessage = "You are already subscribed to this feed."
                Self.logger.debug("Duplicate Atom feed URL: '\(atomURL, privacy: .public)'")
                return
            }
        } catch {
            errorMessage = "Unable to load existing feeds. Please try again."
            Self.logger.error("Failed to check for duplicate: \(error, privacy: .public)")
            return
        }

        let atomFeed: RSSFeed
        do {
            atomFeed = try await feedFetching.fetchFeed(from: atomURL)
        } catch {
            errorMessage = "Could not load feed. Check the URL and try again."
            Self.logger.error("Atom feed validation failed for \(atomURL, privacy: .public): \(error, privacy: .public)")
            return
        }

        persistFetchedFeed(atomFeed, url: atomURL)
    }

    private func persistFetchedFeed(_ rssFeed: RSSFeed, url: URL) {
        let newFeed = PersistentFeed(
            title: rssFeed.title,
            feedURL: url,
            feedDescription: rssFeed.feedDescription
        )
        do {
            try persistence.addFeed(newFeed)
        } catch {
            errorMessage = "Could not load feed. Check the URL and try again."
            Self.logger.error("Failed to persist feed \(url, privacy: .public): \(error, privacy: .public)")
            return
        }
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
    }
}
