import Foundation
@testable import RSSApp

// RATIONALE: @unchecked Sendable is safe because this mock is only used in
// single-threaded test contexts where properties are set before the async call.
final class MockAtomDiscoveryService: AtomDiscovering, @unchecked Sendable {
    /// URL returned from `discoverAtomAlternate(forFeedAt:)` when no per-URL
    /// override is configured.
    var resultToReturn: URL?

    /// Per-feed overrides. When the key matches the feed URL passed to
    /// `discoverAtomAlternate`, that entry's value is returned verbatim (even
    /// when that value is nil — use this to express "no alternative for this
    /// URL" distinct from "no alternative by default").
    var resultsByURL: [URL: URL?] = [:]

    /// Counts how many times discovery was invoked. Lets tests assert that
    /// discovery is skipped for Atom feeds or unchanged-URL edit flows.
    private(set) var discoverCallCount = 0

    /// Feed URLs passed to the most recent calls, in call order.
    private(set) var discoverCallURLs: [URL] = []

    func discoverAtomAlternate(forFeedAt feedURL: URL) async -> URL? {
        discoverCallCount += 1
        discoverCallURLs.append(feedURL)
        if let override = resultsByURL[feedURL] {
            return override
        }
        return resultToReturn
    }
}
