import Foundation

/// Payload surfaced to the add/edit feed UI when `AtomDiscoveryService`
/// finds an Atom alternative for an RSS feed the user is about to
/// subscribe to. Carries both the discovered `atomURL` (the target of the
/// "Switch to Atom" button) and the already-fetched `originalFeed` so the
/// "Keep RSS" path can persist without a second network round-trip.
///
/// The failing init enforces the two invariants the caller must already
/// have established (RSS format + distinct URLs). It is defense in depth,
/// not a new validation burden — `AtomDiscoveryService` already refuses
/// to return a candidate equal to the feed URL, and the view models only
/// construct a prompt when `rssFeed.format == .rss`. The failing init
/// makes those invariants visible on the type itself so a future refactor
/// that drops either check fails loudly at construction.
struct AtomAlternatePrompt: Sendable {
    let originalURL: URL
    let atomURL: URL
    let originalFeed: RSSFeed

    init?(originalURL: URL, atomURL: URL, originalFeed: RSSFeed) {
        guard originalURL != atomURL, originalFeed.format == .rss else {
            return nil
        }
        self.originalURL = originalURL
        self.atomURL = atomURL
        self.originalFeed = originalFeed
    }
}
