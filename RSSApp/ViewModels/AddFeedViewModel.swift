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

    /// Set when `switchToAtomAlternate(from:)` fell back to persisting the
    /// original RSS feed because the Atom fetch failed. Drives a follow-up
    /// alert that explains the fallback to the user. The RSS feed is already
    /// persisted at this point — the view model waits for the user to
    /// acknowledge the notice (via `acknowledgeAtomFallbackNotice()`) before
    /// setting `didAddFeed = true` and allowing the sheet to dismiss.
    var atomFallbackNotice: URL?

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
                // to the RSS-as-is path in release. We have to mirror the
                // happy-path `if persistFetchedFeed(...) { didAddFeed = true }`
                // here, otherwise the release-mode degradation would persist
                // the feed but leave the sheet frozen.
                Self.logger.fault("Failed to construct AtomAlternatePrompt despite upstream guards: url=\(url.absoluteString, privacy: .public) atomURL=\(atomURL.absoluteString, privacy: .public)")
                assertionFailure("AtomAlternatePrompt invariants violated upstream")
                if persistFetchedFeed(rssFeed, url: url) {
                    didAddFeed = true
                }
                return
            }
            atomAlternatePrompt = prompt
            return
        }

        if persistFetchedFeed(rssFeed, url: url) {
            didAddFeed = true
        }
    }

    /// User dismissed the Atom prompt by choosing to keep the RSS feed as-is.
    /// Persists the feed that was already fetched in `addFeed()` so we avoid a
    /// second network round-trip.
    ///
    /// The caller passes the captured `prompt` explicitly rather than
    /// re-reading `atomAlternatePrompt`. SwiftUI's `.alert(isPresented:)`
    /// setter clears the view-model prompt as part of dismissing the alert,
    /// and the ordering between that setter and the button action closure is
    /// not guaranteed — both this method and `switchToAtomAlternate(from:)`
    /// would see nil if the setter fires first. `switchToAtomAlternate(from:)`
    /// has the same hazard in stronger form because its async Task extends
    /// the window; see the `*SurvivesAlertBindingRace` regression tests.
    func keepOriginalFeed(from prompt: AtomAlternatePrompt) {
        Self.logger.notice("User kept RSS feed \(prompt.originalURL.absoluteString, privacy: .public), declining Atom \(prompt.atomURL.absoluteString, privacy: .public)")
        atomAlternatePrompt = nil
        if persistFetchedFeed(prompt.originalFeed, url: prompt.originalURL) {
            didAddFeed = true
        }
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
            // The Atom alternative was advertised but could not be loaded as
            // a valid feed (network error, HTTP failure, or parse failure).
            // We already have a successfully-fetched RSS feed from the prompt
            // — persist it and surface a follow-up notice so the user knows
            // why we didn't honor their "Switch" choice.
            Self.logger.warning("Atom switch fetch failed for \(atomURL, privacy: .public), falling back to RSS: \(error, privacy: .public)")
            if persistFetchedFeed(prompt.originalFeed, url: prompt.originalURL) {
                atomFallbackNotice = atomURL
            } else {
                // persistFetchedFeed already set errorMessage to the generic
                // save-failure copy. Replace it with a chained message so the
                // user understands the Atom attempt was what triggered the
                // save attempt — retrying the same URL won't help.
                errorMessage = "The Atom feed couldn't be loaded, and saving the RSS version also failed. Please try again."
            }
            return
        }

        // Only update the visible URL once the Atom switch has actually
        // committed. Every other exit path above — cancellation, duplicate,
        // fetch-failure fallback — intentionally leaves the user's typed
        // URL in place so they can see what they entered.
        urlInput = atomURL.absoluteString
        if persistFetchedFeed(atomFeed, url: atomURL) {
            didAddFeed = true
        }
    }

    /// Called by the view after the user acknowledges the Atom-fallback
    /// notice alert. Clears the notice state and signals the sheet to
    /// dismiss now that the user has seen the message.
    ///
    /// The guard is defensive — SwiftUI's alert-binding setter can fire
    /// more than once during dismissal transitions on some iOS versions.
    /// Without the guard, the second call would re-set `didAddFeed = true`
    /// on an already-dismissing sheet, which is harmless but pollutes the
    /// observation tracker. Log + early-return makes unexpected re-entries
    /// visible instead of silently no-op'ing.
    func acknowledgeAtomFallbackNotice() {
        guard atomFallbackNotice != nil else {
            Self.logger.debug("acknowledgeAtomFallbackNotice called with no pending notice; ignoring")
            return
        }
        atomFallbackNotice = nil
        didAddFeed = true
    }

    /// Persists a fetched feed. Returns true on success, false if persistence
    /// failed (with `errorMessage` set). Does NOT toggle `didAddFeed` —
    /// callers decide when the sheet should dismiss. The fallback-notice
    /// path needs to defer dismissal until the user acknowledges the notice,
    /// which is why the signal is separated from the persistence step.
    private func persistFetchedFeed(_ rssFeed: RSSFeed, url: URL) -> Bool {
        // Compute nextSortOrder so the new feed appears at the end of any
        // user-customized order, not at position 0 where it would displace
        // existing feeds.
        let nextSortOrder: Int
        do {
            let existingFeeds = try persistence.allFeeds()
            nextSortOrder = (existingFeeds.map(\.sortOrder).max() ?? -1) + 1
        } catch {
            // If we can't read existing feeds, default to 0. The feed will
            // still be added; ordering is best-effort.
            nextSortOrder = 0
            Self.logger.warning("Could not compute nextSortOrder, defaulting to 0: \(error, privacy: .public)")
        }

        let newFeed = PersistentFeed(
            title: rssFeed.title,
            feedURL: url,
            feedDescription: rssFeed.feedDescription,
            sortOrder: nextSortOrder
        )
        do {
            try persistence.addFeed(newFeed)
        } catch {
            errorMessage = "Could not save the feed. Please try again."
            Self.logger.error("Failed to persist feed \(url, privacy: .public): \(error, privacy: .public)")
            return false
        }
        Self.logger.notice("Added feed '\(rssFeed.title, privacy: .public)' from \(url, privacy: .public)")

        // Fire-and-forget icon resolution
        let iconService = self.feedIconService
        let feedTitle = rssFeed.title
        let siteURL = rssFeed.link
        let feedImageURL = rssFeed.imageURL
        let persistenceRef = self.persistence
        Task {
            guard let resolved = await iconService.resolveAndCacheIcon(
                feedSiteURL: siteURL,
                feedImageURL: feedImageURL,
                feedID: newFeed.id
            ) else { return }
            do {
                try persistenceRef.updateFeedIcon(
                    newFeed,
                    iconURL: resolved.url,
                    backgroundStyle: resolved.backgroundStyle
                )
                try persistenceRef.save()
            } catch {
                Self.logger.error("Failed to persist icon for '\(feedTitle, privacy: .public)': \(error, privacy: .public)")
            }
        }
        return true
    }
}
