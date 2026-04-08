import Foundation
import os

@MainActor
@Observable
final class EditFeedViewModel {

    private static let logger = Logger(category: "EditFeedViewModel")

    var urlInput: String
    private(set) var isValidating = false
    private(set) var errorMessage: String?
    private(set) var didSave = false
    var atomAlternatePrompt: AtomAlternatePrompt?

    /// Set when `switchToAtomAlternate(from:)` fell back to persisting the
    /// original RSS feed because the Atom fetch failed. Drives a follow-up
    /// alert that explains the fallback. The edit has already been committed
    /// at this point — the view model waits for the user to acknowledge the
    /// notice (via `acknowledgeAtomFallbackNotice()`) before setting
    /// `didSave = true` and allowing the sheet to dismiss.
    var atomFallbackNotice: URL?

    var canSubmit: Bool {
        !urlInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isValidating
    }

    private let feed: PersistentFeed
    private let feedFetching: FeedFetching
    private let persistence: FeedPersisting
    private let atomDiscovery: any AtomDiscovering

    init(
        feed: PersistentFeed,
        feedFetching: FeedFetching = FeedFetchingService(),
        persistence: FeedPersisting,
        atomDiscovery: any AtomDiscovering = AtomDiscoveryService()
    ) {
        self.feed = feed
        self.urlInput = feed.feedURL.absoluteString
        self.feedFetching = feedFetching
        self.persistence = persistence
        self.atomDiscovery = atomDiscovery
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
                // See the companion guard in `AddFeedViewModel.addFeed()`.
                Self.logger.fault("Failed to construct AtomAlternatePrompt despite upstream guards: url=\(url.absoluteString, privacy: .public) atomURL=\(atomURL.absoluteString, privacy: .public)")
                assertionFailure("AtomAlternatePrompt invariants violated upstream")
                persistEditedFeed(rssFeed, url: url)
                return
            }
            atomAlternatePrompt = prompt
            return
        }

        if persistEditedFeed(rssFeed, url: url) {
            didSave = true
        }
    }

    /// User dismissed the Atom prompt by choosing to keep the RSS feed.
    /// Persists the feed already fetched during `saveFeed()`.
    ///
    /// The `prompt` parameter is passed explicitly by the caller rather than
    /// re-read from `atomAlternatePrompt`. This keeps the shape symmetric with
    /// `switchToAtomAlternate(from:)` — which genuinely requires the parameter
    /// to avoid racing with SwiftUI's alert-dismissal binding clear — and
    /// ensures both branches of the alert operate on the same captured value.
    func keepOriginalFeed(from prompt: AtomAlternatePrompt) {
        Self.logger.notice("User kept RSS feed \(prompt.originalURL.absoluteString, privacy: .public), declining Atom \(prompt.atomURL.absoluteString, privacy: .public)")
        atomAlternatePrompt = nil
        if persistEditedFeed(prompt.originalFeed, url: prompt.originalURL) {
            didSave = true
        }
    }

    /// User accepted the Atom prompt. Fetches the discovered Atom URL and
    /// persists that feed as the new URL for this subscription.
    ///
    /// See the note on `keepOriginalFeed(from:)` — the prompt must be passed
    /// in by the caller rather than re-read from `atomAlternatePrompt`, which
    /// will have been cleared by the alert's dismissal binding by the time
    /// this task runs.
    func switchToAtomAlternate(from prompt: AtomAlternatePrompt) async {
        Self.logger.notice("User switching to Atom \(prompt.atomURL.absoluteString, privacy: .public) from \(prompt.originalURL.absoluteString, privacy: .public)")
        let atomURL = prompt.atomURL
        atomAlternatePrompt = nil

        // The user may have switched to an Atom URL that matches the feed's
        // existing URL (e.g. they edited the RSS URL but the site advertises
        // the already-subscribed Atom URL as the alternate). Treat as no-op.
        if atomURL == feed.feedURL {
            Self.logger.debug("Atom URL matches existing feed URL, dismissing without save")
            urlInput = atomURL.absoluteString
            didSave = true
            return
        }

        isValidating = true
        defer { isValidating = false }

        do {
            if try persistence.feedExists(url: atomURL) {
                errorMessage = "Another feed already uses this URL."
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
            // The Atom alternative was advertised but unreachable. We already
            // have a successfully-fetched RSS feed from the prompt — persist
            // it and surface a follow-up notice so the user knows why we
            // didn't honor their "Switch" choice.
            Self.logger.warning("Atom switch fetch failed for \(atomURL, privacy: .public), falling back to RSS: \(error, privacy: .public)")
            if persistEditedFeed(prompt.originalFeed, url: prompt.originalURL) {
                atomFallbackNotice = atomURL
            }
            return
        }

        // The switch has now committed. Reflect the Atom URL in the input
        // field *after* all failure paths above — if we fail earlier, the
        // user's originally-typed URL remains in the field.
        urlInput = atomURL.absoluteString
        if persistEditedFeed(atomFeed, url: atomURL) {
            didSave = true
        }
    }

    /// Called by the view after the user acknowledges the Atom-fallback
    /// notice alert. Clears the notice state and signals the sheet to
    /// dismiss now that the user has seen the message.
    func acknowledgeAtomFallbackNotice() {
        atomFallbackNotice = nil
        didSave = true
    }

    /// Persists an edited feed. Returns true on success, false if persistence
    /// failed (with `errorMessage` set). Does NOT toggle `didSave` — callers
    /// decide when the sheet should dismiss. The fallback-notice path needs
    /// to defer dismissal until the user acknowledges the notice, which is
    /// why the signal is separated from the persistence step.
    private func persistEditedFeed(_ rssFeed: RSSFeed, url: URL) -> Bool {
        do {
            try persistence.updateFeedURL(feed, newURL: url)
            try persistence.updateFeedMetadata(feed, title: rssFeed.title, description: rssFeed.feedDescription)
        } catch {
            errorMessage = "Unable to save changes. Please try again."
            Self.logger.error("Failed to persist edited feed: \(error, privacy: .public)")
            return false
        }

        Self.logger.notice("Updated feed '\(rssFeed.title, privacy: .public)' URL to \(url, privacy: .public)")
        return true
    }
}
