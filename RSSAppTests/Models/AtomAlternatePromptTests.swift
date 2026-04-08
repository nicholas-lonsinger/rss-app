import Testing
import Foundation
@testable import RSSApp

@Suite("AtomAlternatePrompt invariants")
struct AtomAlternatePromptTests {

    @Test("Successfully constructs for an RSS feed with distinct URLs")
    func constructsForRSSWithDistinctURLs() {
        let prompt = AtomAlternatePrompt(
            originalURL: URL(string: "https://example.com/feed")!,
            atomURL: URL(string: "https://example.com/atom.xml")!,
            originalFeed: TestFixtures.makeFeed(format: .rss)
        )
        #expect(prompt != nil)
    }

    @Test("Refuses to construct when originalURL equals atomURL")
    func refusesSameURL() {
        let url = URL(string: "https://example.com/feed")!
        let prompt = AtomAlternatePrompt(
            originalURL: url,
            atomURL: url,
            originalFeed: TestFixtures.makeFeed(format: .rss)
        )
        #expect(prompt == nil)
    }

    @Test("Refuses to construct when the feed is Atom format")
    func refusesAtomFeed() {
        // Offering an Atom upgrade for an Atom feed is nonsensical — the
        // failing init catches upstream-format-check refactors.
        let prompt = AtomAlternatePrompt(
            originalURL: URL(string: "https://example.com/feed")!,
            atomURL: URL(string: "https://example.com/atom.xml")!,
            originalFeed: TestFixtures.makeFeed(format: .atom)
        )
        #expect(prompt == nil)
    }
}
