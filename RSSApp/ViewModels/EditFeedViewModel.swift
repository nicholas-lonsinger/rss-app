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
    /// at this point — clearing this to `nil` (e.g. when the user taps OK)
    /// triggers `didSave = true` via `didSet` and allows the sheet to dismiss.
    // RATIONALE: No `private(set)` here — `AtomFeedAlerts` receives this as a
    // `@Binding`, which requires a public setter. Misuse is constrained by the
    // `didSet` guard: only a non-nil → nil transition triggers `didSave = true`.
    var atomFallbackNotice: URL? {
        didSet {
            // Guard against double-fire: only transition to didSave when the
            // property moves from a non-nil value to nil. Re-assigning nil
            // (e.g. a second binding-setter call during alert dismissal) is
            // a no-op so the observation tracker stays clean.
            guard oldValue != nil, atomFallbackNotice == nil else {
                if oldValue == nil, atomFallbackNotice == nil {
                    Self.logger.debug("atomFallbackNotice double-fire ignored (was already nil)")
                }
                return
            }
            didSave = true
        }
    }

    // MARK: - Group membership state

    private(set) var allGroups: [PersistentFeedGroup] = []
    private(set) var memberGroupIDs: Set<UUID> = []

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
                // Mirroring the happy-path `if persistEditedFeed(...) { didSave = true }`
                // here is load-bearing — without it, the release-mode fallback
                // persists the edit but leaves the sheet frozen.
                Self.logger.fault("Failed to construct AtomAlternatePrompt despite upstream guards: url=\(url.absoluteString, privacy: .public) atomURL=\(atomURL.absoluteString, privacy: .public)")
                assertionFailure("AtomAlternatePrompt invariants violated upstream")
                if persistEditedFeed(rssFeed, url: url) {
                    didSave = true
                }
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
    /// See the companion doc on `AddFeedViewModel.keepOriginalFeed(from:)`
    /// for the full race-defense rationale. Both this method and the async
    /// `switchToAtomAlternate(from:)` require the caller to pass `prompt`
    /// explicitly because SwiftUI's alert-binding setter clears
    /// `atomAlternatePrompt` during dismissal, and the ordering between
    /// that setter and the button action closure is not guaranteed.
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
            // The Atom alternative was advertised but could not be loaded as
            // a valid feed (network error, HTTP failure, or parse failure).
            // We already have a successfully-fetched RSS feed from the prompt
            // — persist it and surface a follow-up notice so the user knows
            // why we didn't honor their "Switch" choice.
            Self.logger.warning("Atom switch fetch failed for \(atomURL, privacy: .public), falling back to RSS: \(error, privacy: .public)")
            if persistEditedFeed(prompt.originalFeed, url: prompt.originalURL) {
                atomFallbackNotice = atomURL
            } else {
                // persistEditedFeed already set errorMessage to the generic
                // save-failure copy. Replace it with a chained message so the
                // user understands the Atom attempt was what triggered the
                // save attempt.
                errorMessage = "The Atom feed couldn't be loaded, and saving the RSS version also failed. Please try again."
            }
            return
        }

        // Only update the visible URL once the Atom switch has actually
        // committed. Every other exit path above — cancellation, duplicate,
        // fetch-failure fallback — intentionally leaves the user's typed
        // URL in place so they can see what they entered.
        urlInput = atomURL.absoluteString
        if persistEditedFeed(atomFeed, url: atomURL) {
            didSave = true
        }
    }

    /// Persists an edited feed. Returns true on success, false if persistence
    /// failed (with `errorMessage` set). Does NOT toggle `didSave` — callers
    /// decide when the sheet should dismiss. The fallback-notice path needs
    /// to defer dismissal until the user acknowledges the notice, which is
    /// why the signal is separated from the persistence step.
    private func persistEditedFeed(_ rssFeed: RSSFeed, url: URL) -> Bool {
        do {
            try persistence.updateFeedURL(feed, newURL: url)
            try persistence.updateFeedMetadata(feed, title: rssFeed.title, description: rssFeed.feedDescription, feedImageURL: rssFeed.imageURL)
        } catch {
            errorMessage = "Unable to save changes. Please try again."
            Self.logger.error("Failed to persist edited feed: \(error, privacy: .public)")
            return false
        }

        Self.logger.notice("Updated feed '\(rssFeed.title, privacy: .public)' URL to \(url, privacy: .public)")
        return true
    }

    // MARK: - Group Membership

    func loadGroups() {
        do {
            allGroups = try persistence.allGroups()
            let feedGroups = try persistence.groups(for: feed)
            memberGroupIDs = Set(feedGroups.map(\.id))
            Self.logger.debug("Feed '\(self.feed.title, privacy: .public)' belongs to \(self.memberGroupIDs.count, privacy: .public) of \(self.allGroups.count, privacy: .public) groups")
        } catch {
            errorMessage = "Unable to load groups."
            Self.logger.error("Failed to load groups for feed: \(error, privacy: .public)")
        }
    }

    func toggleGroupMembership(_ group: PersistentFeedGroup) {
        do {
            if memberGroupIDs.contains(group.id) {
                try persistence.removeFeed(feed, from: group)
                memberGroupIDs.remove(group.id)
                Self.logger.notice("Removed feed '\(self.feed.title, privacy: .public)' from group '\(group.name, privacy: .public)'")
            } else {
                try persistence.addFeed(feed, to: group)
                memberGroupIDs.insert(group.id)
                Self.logger.notice("Added feed '\(self.feed.title, privacy: .public)' to group '\(group.name, privacy: .public)'")
            }
        } catch {
            errorMessage = "Unable to update group membership."
            Self.logger.error("Failed to toggle group membership: \(error, privacy: .public)")
        }
    }
}
