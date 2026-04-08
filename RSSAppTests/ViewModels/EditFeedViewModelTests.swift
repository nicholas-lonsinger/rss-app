import Testing
import Foundation
@testable import RSSApp

@Suite("EditFeedViewModel Tests")
struct EditFeedViewModelTests {

    @Test("saveFeed succeeds with changed URL")
    @MainActor
    func saveFeedSuccess() async {
        let feed = TestFixtures.makePersistentFeed(
            title: "Old Feed",
            feedURL: URL(string: "https://old.com/feed")!
        )
        let mockFetching = MockFeedFetchingService()
        mockFetching.feedToReturn = TestFixtures.makeFeed(
            title: "New Feed",
            feedDescription: "New description"
        )
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]

        let viewModel = EditFeedViewModel(feed: feed, feedFetching: mockFetching, persistence: mockPersistence)
        viewModel.urlInput = "https://new.com/feed"
        await viewModel.saveFeed()

        #expect(viewModel.didSave == true)
        #expect(feed.feedURL == URL(string: "https://new.com/feed"))
        #expect(feed.title == "New Feed")
        #expect(feed.lastFetchError == nil)
        #expect(viewModel.errorMessage == nil)
    }

    @Test("saveFeed dismisses without changes when URL unchanged")
    @MainActor
    func saveFeedUnchangedURL() async {
        let feed = TestFixtures.makePersistentFeed(feedURL: URL(string: "https://example.com/feed")!)
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]

        let viewModel = EditFeedViewModel(feed: feed, feedFetching: MockFeedFetchingService(), persistence: mockPersistence)
        await viewModel.saveFeed()

        #expect(viewModel.didSave == true)
        #expect(viewModel.errorMessage == nil)
    }

    @Test("saveFeed sets error for invalid URL")
    @MainActor
    func saveFeedInvalidURL() async {
        let feed = TestFixtures.makePersistentFeed()
        let viewModel = EditFeedViewModel(
            feed: feed,
            feedFetching: MockFeedFetchingService(),
            persistence: MockFeedPersistenceService()
        )
        viewModel.urlInput = ""
        await viewModel.saveFeed()

        #expect(viewModel.didSave == false)
        #expect(viewModel.errorMessage != nil)
    }

    @Test("saveFeed sets error for duplicate URL")
    @MainActor
    func saveFeedDuplicate() async {
        let feedA = TestFixtures.makePersistentFeed(feedURL: URL(string: "https://a.com/feed")!)
        let feedB = TestFixtures.makePersistentFeed(feedURL: URL(string: "https://b.com/feed")!)
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feedA, feedB]

        let viewModel = EditFeedViewModel(
            feed: feedA,
            feedFetching: MockFeedFetchingService(),
            persistence: mockPersistence
        )
        viewModel.urlInput = "https://b.com/feed"
        await viewModel.saveFeed()

        #expect(viewModel.didSave == false)
        #expect(viewModel.errorMessage == "Another feed already uses this URL.")
    }

    @Test("saveFeed sets error on network failure")
    @MainActor
    func saveFeedNetworkError() async {
        let feed = TestFixtures.makePersistentFeed(feedURL: URL(string: "https://old.com/feed")!)
        let mockFetching = MockFeedFetchingService()
        mockFetching.errorToThrow = FeedFetchingError.invalidResponse(statusCode: 404)
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]

        let viewModel = EditFeedViewModel(feed: feed, feedFetching: mockFetching, persistence: mockPersistence)
        viewModel.urlInput = "https://new.com/feed"
        await viewModel.saveFeed()

        #expect(viewModel.didSave == false)
        #expect(viewModel.errorMessage == "Could not load feed. Check the URL and try again.")
    }

    @Test("saveFeed prepends https when scheme missing")
    @MainActor
    func saveFeedPrependsScheme() async {
        let feed = TestFixtures.makePersistentFeed(feedURL: URL(string: "https://old.com/feed")!)
        let mockFetching = MockFeedFetchingService()
        mockFetching.feedToReturn = TestFixtures.makeFeed(title: "Feed")
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]

        let viewModel = EditFeedViewModel(feed: feed, feedFetching: mockFetching, persistence: mockPersistence)
        viewModel.urlInput = "new.com/feed"
        await viewModel.saveFeed()

        #expect(feed.feedURL == URL(string: "https://new.com/feed"))
    }

    @Test("urlInput is pre-populated from feed URL")
    @MainActor
    func urlInputPrePopulated() {
        let feed = TestFixtures.makePersistentFeed(feedURL: URL(string: "https://example.com/feed")!)
        let viewModel = EditFeedViewModel(
            feed: feed,
            feedFetching: MockFeedFetchingService(),
            persistence: MockFeedPersistenceService()
        )

        #expect(viewModel.urlInput == "https://example.com/feed")
    }

    // MARK: - Atom Alternate Discovery

    @Test("saveFeed skips Atom discovery when URL is unchanged")
    @MainActor
    func saveFeedSkipsDiscoveryWhenUnchanged() async {
        let feed = TestFixtures.makePersistentFeed(feedURL: URL(string: "https://example.com/feed")!)
        let mockDiscovery = MockAtomDiscoveryService()
        mockDiscovery.resultToReturn = URL(string: "https://example.com/atom.xml")
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]

        let viewModel = EditFeedViewModel(
            feed: feed,
            feedFetching: MockFeedFetchingService(),
            persistence: mockPersistence,
            atomDiscovery: mockDiscovery
        )
        // urlInput already equals feed.feedURL — no change.
        await viewModel.saveFeed()

        #expect(mockDiscovery.discoverCallCount == 0)
        #expect(viewModel.didSave == true)
        #expect(viewModel.atomAlternatePrompt == nil)
    }

    @Test("saveFeed offers Atom alternate and defers persistence when new URL is RSS")
    @MainActor
    func saveFeedOffersAtomAlternate() async {
        let feed = TestFixtures.makePersistentFeed(feedURL: URL(string: "https://old.com/feed")!)
        let mockFetching = MockFeedFetchingService()
        mockFetching.feedToReturn = TestFixtures.makeFeed(title: "New RSS", format: .rss)
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]
        let mockDiscovery = MockAtomDiscoveryService()
        mockDiscovery.resultToReturn = URL(string: "https://new.com/atom.xml")

        let viewModel = EditFeedViewModel(
            feed: feed,
            feedFetching: mockFetching,
            persistence: mockPersistence,
            atomDiscovery: mockDiscovery
        )
        viewModel.urlInput = "https://new.com/feed"
        await viewModel.saveFeed()

        #expect(viewModel.atomAlternatePrompt != nil)
        #expect(viewModel.atomAlternatePrompt?.atomURL.absoluteString == "https://new.com/atom.xml")
        #expect(viewModel.didSave == false)
        // Persistence should not have been updated yet.
        #expect(feed.feedURL == URL(string: "https://old.com/feed"))
    }

    @Test("saveFeed skips discovery for Atom feeds")
    @MainActor
    func saveFeedSkipsDiscoveryForAtomFormat() async {
        let feed = TestFixtures.makePersistentFeed(feedURL: URL(string: "https://old.com/feed")!)
        let mockFetching = MockFeedFetchingService()
        mockFetching.feedToReturn = TestFixtures.makeFeed(title: "New Atom", format: .atom)
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]
        let mockDiscovery = MockAtomDiscoveryService()
        mockDiscovery.resultToReturn = URL(string: "https://anywhere/atom.xml")

        let viewModel = EditFeedViewModel(
            feed: feed,
            feedFetching: mockFetching,
            persistence: mockPersistence,
            atomDiscovery: mockDiscovery
        )
        viewModel.urlInput = "https://new.com/atom"
        await viewModel.saveFeed()

        #expect(mockDiscovery.discoverCallCount == 0)
        #expect(viewModel.didSave == true)
        #expect(feed.feedURL == URL(string: "https://new.com/atom"))
        #expect(feed.title == "New Atom")
    }

    @Test("keepOriginalFeed persists the RSS feed fetched during saveFeed")
    @MainActor
    func keepOriginalFeedPersistsRSS() async {
        let feed = TestFixtures.makePersistentFeed(feedURL: URL(string: "https://old.com/feed")!)
        let mockFetching = MockFeedFetchingService()
        mockFetching.feedToReturn = TestFixtures.makeFeed(title: "New RSS", format: .rss)
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]
        let mockDiscovery = MockAtomDiscoveryService()
        mockDiscovery.resultToReturn = URL(string: "https://new.com/atom.xml")

        let viewModel = EditFeedViewModel(
            feed: feed,
            feedFetching: mockFetching,
            persistence: mockPersistence,
            atomDiscovery: mockDiscovery
        )
        viewModel.urlInput = "https://new.com/feed"
        await viewModel.saveFeed()
        let prompt = try! #require(viewModel.atomAlternatePrompt)

        viewModel.keepOriginalFeed(from: prompt)

        #expect(viewModel.atomAlternatePrompt == nil)
        #expect(viewModel.didSave == true)
        #expect(feed.feedURL == URL(string: "https://new.com/feed"))
        #expect(feed.title == "New RSS")
    }

    @Test("switchToAtomAlternate fetches and persists the Atom URL")
    @MainActor
    func switchToAtomAlternatePersistsAtomURL() async {
        let feed = TestFixtures.makePersistentFeed(feedURL: URL(string: "https://old.com/feed")!)
        let rssURL = URL(string: "https://new.com/feed")!
        let atomURL = URL(string: "https://new.com/atom.xml")!

        let mockFetching = MockFeedFetchingService()
        mockFetching.feedsByURL[rssURL] = TestFixtures.makeFeed(title: "New RSS", format: .rss)
        mockFetching.feedsByURL[atomURL] = TestFixtures.makeFeed(title: "New Atom", format: .atom)
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]
        let mockDiscovery = MockAtomDiscoveryService()
        mockDiscovery.resultToReturn = atomURL

        let viewModel = EditFeedViewModel(
            feed: feed,
            feedFetching: mockFetching,
            persistence: mockPersistence,
            atomDiscovery: mockDiscovery
        )
        viewModel.urlInput = rssURL.absoluteString
        await viewModel.saveFeed()
        let prompt = try! #require(viewModel.atomAlternatePrompt)
        await viewModel.switchToAtomAlternate(from: prompt)

        #expect(viewModel.didSave == true)
        #expect(viewModel.urlInput == atomURL.absoluteString)
        #expect(feed.feedURL == atomURL)
        #expect(feed.title == "New Atom")
    }

    @Test("switchToAtomAlternate completes even after the alert-binding clears atomAlternatePrompt")
    @MainActor
    func switchToAtomAlternateSurvivesAlertBindingRace() async {
        // Regression guard — see AddFeedViewModelTests for the full rationale.
        let feed = TestFixtures.makePersistentFeed(feedURL: URL(string: "https://old.com/feed")!)
        let rssURL = URL(string: "https://new.com/feed")!
        let atomURL = URL(string: "https://new.com/atom.xml")!

        let mockFetching = MockFeedFetchingService()
        mockFetching.feedsByURL[rssURL] = TestFixtures.makeFeed(title: "New RSS", format: .rss)
        mockFetching.feedsByURL[atomURL] = TestFixtures.makeFeed(title: "New Atom", format: .atom)
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]
        let mockDiscovery = MockAtomDiscoveryService()
        mockDiscovery.resultToReturn = atomURL

        let viewModel = EditFeedViewModel(
            feed: feed,
            feedFetching: mockFetching,
            persistence: mockPersistence,
            atomDiscovery: mockDiscovery
        )
        viewModel.urlInput = rssURL.absoluteString
        await viewModel.saveFeed()
        let prompt = try! #require(viewModel.atomAlternatePrompt)

        // Simulate SwiftUI's alert dismissal clearing the prompt before the
        // Task body runs.
        viewModel.atomAlternatePrompt = nil
        await viewModel.switchToAtomAlternate(from: prompt)

        #expect(viewModel.didSave == true)
        #expect(feed.feedURL == atomURL)
        #expect(feed.title == "New Atom")
    }

    @Test("switchToAtomAlternate falls back to RSS when Atom fetch fails")
    @MainActor
    func switchToAtomAlternateFallsBackOnFetchFailure() async {
        let feed = TestFixtures.makePersistentFeed(
            title: "Original",
            feedURL: URL(string: "https://old.com/feed")!
        )
        let rssURL = URL(string: "https://new.com/feed")!
        let atomURL = URL(string: "https://new.com/atom.xml")!

        let mockFetching = MockFeedFetchingService()
        mockFetching.feedsByURL[rssURL] = TestFixtures.makeFeed(title: "New RSS", format: .rss)
        mockFetching.errorsByURL[atomURL] = FeedFetchingError.invalidResponse(statusCode: 500)
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]
        let mockDiscovery = MockAtomDiscoveryService()
        mockDiscovery.resultToReturn = atomURL

        let viewModel = EditFeedViewModel(
            feed: feed,
            feedFetching: mockFetching,
            persistence: mockPersistence,
            atomDiscovery: mockDiscovery
        )
        viewModel.urlInput = rssURL.absoluteString
        await viewModel.saveFeed()
        let prompt = try! #require(viewModel.atomAlternatePrompt)
        await viewModel.switchToAtomAlternate(from: prompt)

        // Fallback: the RSS edit is committed and a notice is surfaced.
        // The sheet waits for acknowledgment before dismissing.
        #expect(viewModel.atomFallbackNotice == atomURL)
        #expect(viewModel.didSave == false)
        #expect(viewModel.errorMessage == nil)
        #expect(feed.feedURL == rssURL)
        #expect(feed.title == "New RSS")
        // The user's original (pre-edit) URL stays in the field while the
        // notice is up — wait, actually they edited to rssURL, so rssURL
        // is what they typed and should remain.
        #expect(viewModel.urlInput == rssURL.absoluteString)

        viewModel.acknowledgeAtomFallbackNotice()

        #expect(viewModel.atomFallbackNotice == nil)
        #expect(viewModel.didSave == true)
    }

    @Test("switchToAtomAlternate is a no-op when Atom URL matches the feed's current URL")
    @MainActor
    func switchToAtomAlternateIsNoOpWhenAtomMatchesCurrentFeed() async {
        // Realistic scenario: user edits the RSS URL, but the site advertises
        // the already-subscribed Atom URL as the alternate. We should dismiss
        // without trying to update the feed (no network call, no persist).
        let currentURL = URL(string: "https://example.com/atom.xml")!
        let feed = TestFixtures.makePersistentFeed(
            title: "Already Subscribed",
            feedURL: currentURL
        )
        let rssURL = URL(string: "https://example.com/feed")!

        let mockFetching = MockFeedFetchingService()
        mockFetching.feedsByURL[rssURL] = TestFixtures.makeFeed(title: "New RSS", format: .rss)
        // Atom fetch must not be called — this is a no-op path.
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [feed]
        let mockDiscovery = MockAtomDiscoveryService()
        mockDiscovery.resultToReturn = currentURL

        let viewModel = EditFeedViewModel(
            feed: feed,
            feedFetching: mockFetching,
            persistence: mockPersistence,
            atomDiscovery: mockDiscovery
        )
        viewModel.urlInput = rssURL.absoluteString
        await viewModel.saveFeed()
        let prompt = try! #require(viewModel.atomAlternatePrompt)
        await viewModel.switchToAtomAlternate(from: prompt)

        // Dismisses successfully without mutating the feed.
        #expect(viewModel.didSave == true)
        #expect(viewModel.errorMessage == nil)
        #expect(feed.feedURL == currentURL)
        #expect(feed.title == "Already Subscribed")
        // urlInput reflects the matched URL so the sheet's text field isn't
        // stale if the user stares at it during the dismissal animation.
        #expect(viewModel.urlInput == currentURL.absoluteString)
    }
}
