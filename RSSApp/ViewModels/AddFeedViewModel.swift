import Foundation
import os

@MainActor
@Observable
final class AddFeedViewModel {

    private static let logger = Logger(category: "AddFeedViewModel")

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

        // Atom feeds have nothing to upgrade to — only offer the switch when
        // the fetched feed is RSS and the site advertises an Atom alternative.
        if rssFeed.format == .rss,
           let atomURL = await atomDiscovery.discoverAtomAlternate(forFeedAt: url) {
            Self.logger.notice("Offering Atom alternate \(atomURL.absoluteString, privacy: .public) for \(url.absoluteString, privacy: .public)")
            guard let prompt = AtomAlternatePrompt(
                originalURL: url,
                atomURL: atomURL,
                originalFeed: rssFeed
            ) else {
                // AtomAlternatePrompt.init? refuses to build a prompt whose
                // invariants are already established upstream (RSS format,
                // distinct URLs). If we land here, an upstream refactor has
                // broken one of those guarantees — crash in debug, degrade
                // to the RSS-as-is path in release.
                Self.logger.fault("Failed to construct AtomAlternatePrompt despite upstream guards: url=\(url.absoluteString, privacy: .public) atomURL=\(atomURL.absoluteString, privacy: .public)")
                assertionFailure("AtomAlternatePrompt invariants violated upstream")
                persistFetchedFeed(rssFeed, url: url)
                return
            }
            atomAlternatePrompt = prompt
            return
        }

        persistFetchedFeed(rssFeed, url: url)
    }

    /// User dismissed the Atom prompt by choosing to keep the RSS feed as-is.
    /// Persists the feed that was already fetched in `addFeed()` so we avoid a
    /// second network round-trip.
    ///
    /// The `prompt` parameter is passed explicitly by the caller rather than
    /// re-read from `atomAlternatePrompt`. This keeps the shape symmetric with
    /// `switchToAtomAlternate(from:)` — which genuinely requires the parameter
    /// to avoid racing with SwiftUI's alert-dismissal binding clear — and
    /// ensures both branches of the alert operate on the same captured value.
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
        } catch is CancellationError {
            Self.logger.debug("Atom switch cancelled for \(atomURL, privacy: .public)")
            return
        } catch let urlError as URLError where urlError.code == .cancelled {
            Self.logger.debug("Atom switch cancelled for \(atomURL, privacy: .public)")
            return
        } catch {
            errorMessage = "Could not load feed. Check the URL and try again."
            Self.logger.error("Atom feed validation failed for \(atomURL, privacy: .public): \(error, privacy: .public)")
            return
        }

        // The switch has now committed. Reflect the Atom URL in the input
        // field *after* all failure paths above — if we fail earlier, the
        // user's originally-typed URL remains in the field.
        urlInput = atomURL.absoluteString
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
            errorMessage = "Could not save the feed. Please try again."
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
