import Testing
import Foundation
@testable import RSSApp

@Suite("AddFeedViewModel Tests")
struct AddFeedViewModelTests {

    @Test("addFeed succeeds with valid URL")
    @MainActor
    func addFeedSuccess() async {
        let mockFetching = MockFeedFetchingService()
        mockFetching.feedToReturn = TestFixtures.makeFeed(
            title: "My Feed",
            feedDescription: "A great feed"
        )
        let mockPersistence = MockFeedPersistenceService()

        let viewModel = AddFeedViewModel(feedFetching: mockFetching, persistence: mockPersistence)
        viewModel.urlInput = "https://example.com/feed"
        await viewModel.addFeed()

        #expect(viewModel.didAddFeed == true)
        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.isValidating == false)
        #expect(mockPersistence.feeds.count == 1)
        #expect(mockPersistence.feeds[0].title == "My Feed")
    }

    @Test("addFeed prepends https when scheme missing")
    @MainActor
    func addFeedPrependsScheme() async {
        let mockFetching = MockFeedFetchingService()
        mockFetching.feedToReturn = TestFixtures.makeFeed(title: "Feed")
        let mockPersistence = MockFeedPersistenceService()

        let viewModel = AddFeedViewModel(feedFetching: mockFetching, persistence: mockPersistence)
        viewModel.urlInput = "example.com/feed"
        await viewModel.addFeed()

        #expect(viewModel.didAddFeed == true)
        #expect(mockPersistence.feeds[0].feedURL == URL(string: "https://example.com/feed"))
    }

    @Test("addFeed rejects non-http schemes")
    @MainActor
    func addFeedRejectsNonHTTP() async {
        let mockPersistence = MockFeedPersistenceService()

        let viewModel = AddFeedViewModel(feedFetching: MockFeedFetchingService(), persistence: mockPersistence)
        viewModel.urlInput = "ftp://example.com/feed"
        await viewModel.addFeed()

        #expect(viewModel.didAddFeed == false)
        #expect(viewModel.errorMessage != nil)
        #expect(mockPersistence.feeds.isEmpty)
    }

    @Test("addFeed sets error for invalid URL")
    @MainActor
    func addFeedInvalidURL() async {
        let mockPersistence = MockFeedPersistenceService()

        let viewModel = AddFeedViewModel(feedFetching: MockFeedFetchingService(), persistence: mockPersistence)
        viewModel.urlInput = ""
        await viewModel.addFeed()

        #expect(viewModel.didAddFeed == false)
        #expect(viewModel.errorMessage != nil)
    }

    @Test("addFeed sets error for duplicate URL")
    @MainActor
    func addFeedDuplicate() async {
        let mockFetching = MockFeedFetchingService()
        mockFetching.feedToReturn = TestFixtures.makeFeed()
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [
            TestFixtures.makePersistentFeed(feedURL: URL(string: "https://example.com/feed")!),
        ]

        let viewModel = AddFeedViewModel(feedFetching: mockFetching, persistence: mockPersistence)
        viewModel.urlInput = "https://example.com/feed"
        await viewModel.addFeed()

        #expect(viewModel.didAddFeed == false)
        #expect(viewModel.errorMessage == "You are already subscribed to this feed.")
    }

    @Test("addFeed sets error on network failure")
    @MainActor
    func addFeedNetworkError() async {
        let mockFetching = MockFeedFetchingService()
        mockFetching.errorToThrow = FeedFetchingError.invalidResponse(statusCode: 500)
        let mockPersistence = MockFeedPersistenceService()

        let viewModel = AddFeedViewModel(feedFetching: mockFetching, persistence: mockPersistence)
        viewModel.urlInput = "https://example.com/feed"
        await viewModel.addFeed()

        #expect(viewModel.didAddFeed == false)
        #expect(viewModel.errorMessage == "Could not load feed. Check the URL and try again.")
        #expect(viewModel.isValidating == false)
    }

    @Test("addFeed sets distinct error copy on persistence failure")
    @MainActor
    func addFeedPersistenceError() async {
        let mockFetching = MockFeedFetchingService()
        mockFetching.feedToReturn = TestFixtures.makeFeed()
        let mockPersistence = MockFeedPersistenceService()
        // Only fail `addFeed()`, not `feedExists()` — we want to test the
        // persistence-failure branch of `persistFetchedFeed`, not the
        // duplicate-check failure branch (which has its own copy).
        mockPersistence.addFeedFailureAfterCount = 0

        let viewModel = AddFeedViewModel(feedFetching: mockFetching, persistence: mockPersistence)
        viewModel.urlInput = "https://example.com/feed"
        await viewModel.addFeed()

        #expect(viewModel.didAddFeed == false)
        // Regression guard: the persistence-failure copy MUST differ from the
        // fetch-failure copy so the user isn't told to "check the URL" when
        // the URL worked fine and SwiftData is the problem.
        #expect(viewModel.errorMessage == "Could not save the feed. Please try again.")
    }

    @Test("canSubmit returns false for empty input")
    @MainActor
    func canSubmitEmpty() {
        let viewModel = AddFeedViewModel(
            feedFetching: MockFeedFetchingService(),
            persistence: MockFeedPersistenceService()
        )
        viewModel.urlInput = ""
        #expect(viewModel.canSubmit == false)
    }

    @Test("canSubmit returns true for valid input")
    @MainActor
    func canSubmitValid() {
        let viewModel = AddFeedViewModel(
            feedFetching: MockFeedFetchingService(),
            persistence: MockFeedPersistenceService()
        )
        viewModel.urlInput = "https://example.com/feed"
        #expect(viewModel.canSubmit == true)
    }

    @Test("canSubmit returns false while validating")
    @MainActor
    func canSubmitWhileValidating() {
        let viewModel = AddFeedViewModel(
            feedFetching: MockFeedFetchingService(),
            persistence: MockFeedPersistenceService()
        )
        viewModel.urlInput = "https://example.com/feed"
        viewModel.isValidating = true
        #expect(viewModel.canSubmit == false)
    }

    @Test("addFeed is a no-op when already validating")
    @MainActor
    func addFeedReentrancyGuard() async {
        let mockFetching = MockFeedFetchingService()
        mockFetching.feedToReturn = TestFixtures.makeFeed()
        let mockPersistence = MockFeedPersistenceService()

        let viewModel = AddFeedViewModel(feedFetching: mockFetching, persistence: mockPersistence)
        viewModel.urlInput = "https://example.com/feed"
        viewModel.isValidating = true
        await viewModel.addFeed()

        #expect(viewModel.didAddFeed == false)
        #expect(mockPersistence.feeds.isEmpty)
    }

    @Test("addFeed detects duplicate when input omits scheme")
    @MainActor
    func addFeedDuplicateWithSchemeNormalization() async {
        let mockFetching = MockFeedFetchingService()
        mockFetching.feedToReturn = TestFixtures.makeFeed()
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [
            TestFixtures.makePersistentFeed(feedURL: URL(string: "https://example.com/feed")!),
        ]

        let viewModel = AddFeedViewModel(feedFetching: mockFetching, persistence: mockPersistence)
        viewModel.urlInput = "example.com/feed"
        await viewModel.addFeed()

        #expect(viewModel.didAddFeed == false)
        #expect(viewModel.errorMessage == "You are already subscribed to this feed.")
    }

    // MARK: - Icon Resolution

    @Test("addFeed triggers icon resolution on success")
    @MainActor
    func addFeedTriggersIconResolution() async {
        let mockFetching = MockFeedFetchingService()
        mockFetching.feedToReturn = TestFixtures.makeFeed(
            title: "My Feed",
            link: URL(string: "https://example.com"),
            imageURL: URL(string: "https://example.com/logo.png")
        )
        let mockPersistence = MockFeedPersistenceService()
        let mockIconService = MockFeedIconService()
        mockIconService.resolveAndCacheResult = URL(string: "https://example.com/icon.png")

        let viewModel = AddFeedViewModel(
            feedFetching: mockFetching,
            persistence: mockPersistence,
            feedIconService: mockIconService
        )
        viewModel.urlInput = "https://example.com/feed"
        await viewModel.addFeed()

        // Allow fire-and-forget icon resolution task to complete
        for _ in 0..<10 { await Task.yield() }

        #expect(viewModel.didAddFeed == true)
        #expect(mockIconService.resolveAndCacheCallCount == 1)
    }

    @Test("addFeed does not trigger icon resolution on fetch failure")
    @MainActor
    func addFeedSkipsIconResolutionOnFailure() async {
        let mockFetching = MockFeedFetchingService()
        mockFetching.errorToThrow = FeedFetchingError.invalidResponse(statusCode: 500)
        let mockPersistence = MockFeedPersistenceService()
        let mockIconService = MockFeedIconService()

        let viewModel = AddFeedViewModel(
            feedFetching: mockFetching,
            persistence: mockPersistence,
            feedIconService: mockIconService
        )
        viewModel.urlInput = "https://example.com/feed"
        await viewModel.addFeed()

        #expect(viewModel.didAddFeed == false)
        #expect(mockIconService.resolveAndCacheCallCount == 0)
    }

    @Test("addFeed clears previous error on retry")
    @MainActor
    func addFeedClearsPreviousError() async {
        let mockFetching = MockFeedFetchingService()
        mockFetching.errorToThrow = FeedFetchingError.invalidResponse(statusCode: 500)
        let mockPersistence = MockFeedPersistenceService()

        let viewModel = AddFeedViewModel(feedFetching: mockFetching, persistence: mockPersistence)
        viewModel.urlInput = "https://example.com/feed"
        await viewModel.addFeed()
        #expect(viewModel.errorMessage != nil)

        mockFetching.errorToThrow = nil
        mockFetching.feedToReturn = TestFixtures.makeFeed()
        await viewModel.addFeed()

        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.didAddFeed == true)
    }

    // MARK: - Atom Alternate Discovery

    @Test("addFeed offers Atom alternate and defers persistence when RSS feed has one")
    @MainActor
    func addFeedOffersAtomAlternate() async {
        let mockFetching = MockFeedFetchingService()
        mockFetching.feedToReturn = TestFixtures.makeFeed(title: "My RSS Feed", format: .rss)
        let mockPersistence = MockFeedPersistenceService()
        let mockDiscovery = MockAtomDiscoveryService()
        mockDiscovery.resultToReturn = URL(string: "https://example.com/atom.xml")

        let viewModel = AddFeedViewModel(
            feedFetching: mockFetching,
            persistence: mockPersistence,
            atomDiscovery: mockDiscovery
        )
        viewModel.urlInput = "https://example.com/feed"
        await viewModel.addFeed()

        // Flow should pause at the prompt — nothing persisted yet.
        #expect(viewModel.atomAlternatePrompt != nil)
        #expect(viewModel.atomAlternatePrompt?.atomURL.absoluteString == "https://example.com/atom.xml")
        #expect(viewModel.atomAlternatePrompt?.originalURL.absoluteString == "https://example.com/feed")
        #expect(viewModel.didAddFeed == false)
        #expect(mockPersistence.feeds.isEmpty)
        #expect(mockDiscovery.discoverCallCount == 1)
    }

    @Test("addFeed skips Atom discovery for Atom feeds")
    @MainActor
    func addFeedSkipsDiscoveryForAtom() async {
        let mockFetching = MockFeedFetchingService()
        mockFetching.feedToReturn = TestFixtures.makeFeed(title: "My Atom Feed", format: .atom)
        let mockPersistence = MockFeedPersistenceService()
        let mockDiscovery = MockAtomDiscoveryService()
        mockDiscovery.resultToReturn = URL(string: "https://example.com/something.xml")

        let viewModel = AddFeedViewModel(
            feedFetching: mockFetching,
            persistence: mockPersistence,
            atomDiscovery: mockDiscovery
        )
        viewModel.urlInput = "https://example.com/atom"
        await viewModel.addFeed()

        #expect(mockDiscovery.discoverCallCount == 0)
        #expect(viewModel.atomAlternatePrompt == nil)
        #expect(viewModel.didAddFeed == true)
        #expect(mockPersistence.feeds.count == 1)
    }

    @Test("addFeed proceeds immediately when discovery returns nil")
    @MainActor
    func addFeedProceedsWhenNoAtomFound() async {
        let mockFetching = MockFeedFetchingService()
        mockFetching.feedToReturn = TestFixtures.makeFeed(format: .rss)
        let mockPersistence = MockFeedPersistenceService()
        let mockDiscovery = MockAtomDiscoveryService()
        mockDiscovery.resultToReturn = nil

        let viewModel = AddFeedViewModel(
            feedFetching: mockFetching,
            persistence: mockPersistence,
            atomDiscovery: mockDiscovery
        )
        viewModel.urlInput = "https://example.com/feed"
        await viewModel.addFeed()

        #expect(mockDiscovery.discoverCallCount == 1)
        #expect(viewModel.atomAlternatePrompt == nil)
        #expect(viewModel.didAddFeed == true)
        #expect(mockPersistence.feeds.count == 1)
    }

    @Test("keepOriginalFeed persists the RSS feed that was already fetched")
    @MainActor
    func keepOriginalFeedPersistsFetchedFeed() async {
        let mockFetching = MockFeedFetchingService()
        mockFetching.feedToReturn = TestFixtures.makeFeed(title: "Original RSS", format: .rss)
        let mockPersistence = MockFeedPersistenceService()
        let mockDiscovery = MockAtomDiscoveryService()
        mockDiscovery.resultToReturn = URL(string: "https://example.com/atom.xml")

        let viewModel = AddFeedViewModel(
            feedFetching: mockFetching,
            persistence: mockPersistence,
            atomDiscovery: mockDiscovery
        )
        viewModel.urlInput = "https://example.com/feed"
        await viewModel.addFeed()
        let prompt = try! #require(viewModel.atomAlternatePrompt)

        // User declines the switch.
        let fetchesBefore = mockFetching.feedsByURL.count
        viewModel.keepOriginalFeed(from: prompt)

        #expect(viewModel.atomAlternatePrompt == nil)
        #expect(viewModel.didAddFeed == true)
        #expect(mockPersistence.feeds.count == 1)
        #expect(mockPersistence.feeds[0].title == "Original RSS")
        #expect(mockPersistence.feeds[0].feedURL == URL(string: "https://example.com/feed"))
        // No second fetch — the already-fetched feed is reused.
        #expect(mockFetching.feedsByURL.count == fetchesBefore)
    }

    @Test("switchToAtomAlternate fetches Atom URL and persists that feed")
    @MainActor
    func switchToAtomAlternatePersistsAtomFeed() async {
        let rssURL = URL(string: "https://example.com/feed")!
        let atomURL = URL(string: "https://example.com/atom.xml")!

        let mockFetching = MockFeedFetchingService()
        mockFetching.feedsByURL[rssURL] = TestFixtures.makeFeed(title: "RSS Version", format: .rss)
        mockFetching.feedsByURL[atomURL] = TestFixtures.makeFeed(title: "Atom Version", format: .atom)
        let mockPersistence = MockFeedPersistenceService()
        let mockDiscovery = MockAtomDiscoveryService()
        mockDiscovery.resultToReturn = atomURL

        let viewModel = AddFeedViewModel(
            feedFetching: mockFetching,
            persistence: mockPersistence,
            atomDiscovery: mockDiscovery
        )
        viewModel.urlInput = rssURL.absoluteString
        await viewModel.addFeed()
        let prompt = try! #require(viewModel.atomAlternatePrompt)

        // User accepts the switch.
        await viewModel.switchToAtomAlternate(from: prompt)

        #expect(viewModel.atomAlternatePrompt == nil)
        #expect(viewModel.didAddFeed == true)
        #expect(viewModel.urlInput == atomURL.absoluteString)
        #expect(mockPersistence.feeds.count == 1)
        #expect(mockPersistence.feeds[0].title == "Atom Version")
        #expect(mockPersistence.feeds[0].feedURL == atomURL)
    }

    @Test("switchToAtomAlternate completes even after the alert-binding clears atomAlternatePrompt")
    @MainActor
    func switchToAtomAlternateSurvivesAlertBindingRace() async {
        // Regression guard: SwiftUI's `.alert(isPresented:)` binding setter
        // clears the view-model prompt property as part of dismissing the
        // alert. If `switchToAtomAlternate` re-reads that property instead of
        // receiving the prompt as a parameter, it sees nil by the time the
        // spawned `Task` runs and silently no-ops — leaving the sheet stuck
        // open with nothing persisted. This test simulates that clear
        // between prompt capture and method invocation.
        let rssURL = URL(string: "https://example.com/feed")!
        let atomURL = URL(string: "https://example.com/atom.xml")!

        let mockFetching = MockFeedFetchingService()
        mockFetching.feedsByURL[rssURL] = TestFixtures.makeFeed(title: "RSS Version", format: .rss)
        mockFetching.feedsByURL[atomURL] = TestFixtures.makeFeed(title: "Atom Version", format: .atom)
        let mockPersistence = MockFeedPersistenceService()
        let mockDiscovery = MockAtomDiscoveryService()
        mockDiscovery.resultToReturn = atomURL

        let viewModel = AddFeedViewModel(
            feedFetching: mockFetching,
            persistence: mockPersistence,
            atomDiscovery: mockDiscovery
        )
        viewModel.urlInput = rssURL.absoluteString
        await viewModel.addFeed()
        let prompt = try! #require(viewModel.atomAlternatePrompt)

        // Simulate the alert dismissal clearing the prompt state *before*
        // the Task body runs.
        viewModel.atomAlternatePrompt = nil
        await viewModel.switchToAtomAlternate(from: prompt)

        #expect(viewModel.didAddFeed == true)
        #expect(mockPersistence.feeds.count == 1)
        #expect(mockPersistence.feeds[0].feedURL == atomURL)
    }

    @Test("keepOriginalFeed completes even after the alert-binding clears atomAlternatePrompt")
    @MainActor
    func keepOriginalFeedSurvivesAlertBindingRace() async {
        // Companion regression guard to the switch variant above.
        let mockFetching = MockFeedFetchingService()
        mockFetching.feedToReturn = TestFixtures.makeFeed(title: "Original RSS", format: .rss)
        let mockPersistence = MockFeedPersistenceService()
        let mockDiscovery = MockAtomDiscoveryService()
        mockDiscovery.resultToReturn = URL(string: "https://example.com/atom.xml")

        let viewModel = AddFeedViewModel(
            feedFetching: mockFetching,
            persistence: mockPersistence,
            atomDiscovery: mockDiscovery
        )
        viewModel.urlInput = "https://example.com/feed"
        await viewModel.addFeed()
        let prompt = try! #require(viewModel.atomAlternatePrompt)

        viewModel.atomAlternatePrompt = nil
        viewModel.keepOriginalFeed(from: prompt)

        #expect(viewModel.didAddFeed == true)
        #expect(mockPersistence.feeds.count == 1)
        #expect(mockPersistence.feeds[0].title == "Original RSS")
    }

    @Test("switchToAtomAlternate falls back to RSS and surfaces notice when Atom fetch fails")
    @MainActor
    func switchToAtomAlternateFallsBackOnFetchFailure() async {
        let rssURL = URL(string: "https://example.com/feed")!
        let atomURL = URL(string: "https://example.com/atom.xml")!

        let mockFetching = MockFeedFetchingService()
        mockFetching.feedsByURL[rssURL] = TestFixtures.makeFeed(title: "RSS Version", format: .rss)
        mockFetching.errorsByURL[atomURL] = FeedFetchingError.invalidResponse(statusCode: 500)
        let mockPersistence = MockFeedPersistenceService()
        let mockDiscovery = MockAtomDiscoveryService()
        mockDiscovery.resultToReturn = atomURL

        let viewModel = AddFeedViewModel(
            feedFetching: mockFetching,
            persistence: mockPersistence,
            atomDiscovery: mockDiscovery
        )
        viewModel.urlInput = rssURL.absoluteString
        await viewModel.addFeed()
        let prompt = try! #require(viewModel.atomAlternatePrompt)
        await viewModel.switchToAtomAlternate(from: prompt)

        // Fallback: the RSS feed (already fetched during addFeed) is persisted
        // and a notice is surfaced. The sheet does NOT dismiss yet — the view
        // waits for the user to acknowledge the notice, at which point
        // didAddFeed flips to true.
        #expect(viewModel.atomAlternatePrompt == nil)
        #expect(viewModel.atomFallbackNotice == atomURL)
        #expect(viewModel.didAddFeed == false)
        #expect(viewModel.errorMessage == nil)
        #expect(mockPersistence.feeds.count == 1)
        #expect(mockPersistence.feeds[0].title == "RSS Version")
        #expect(mockPersistence.feeds[0].feedURL == rssURL)
        // The user's original URL stays in the field while the notice is up.
        #expect(viewModel.urlInput == rssURL.absoluteString)

        // Simulate the user tapping OK on the notice.
        viewModel.acknowledgeAtomFallbackNotice()

        #expect(viewModel.atomFallbackNotice == nil)
        #expect(viewModel.didAddFeed == true)
    }

    @Test("Atom fallback surfaces chained error when RSS persistence also fails")
    @MainActor
    func switchToAtomAlternateFallbackSkippedOnPersistenceFailure() async {
        let rssURL = URL(string: "https://example.com/feed")!
        let atomURL = URL(string: "https://example.com/atom.xml")!

        let mockFetching = MockFeedFetchingService()
        mockFetching.feedsByURL[rssURL] = TestFixtures.makeFeed(title: "RSS Version", format: .rss)
        mockFetching.errorsByURL[atomURL] = FeedFetchingError.invalidResponse(statusCode: 500)
        let mockPersistence = MockFeedPersistenceService()
        // The prompt branch in addFeed() returns without persisting (the RSS
        // feed is only fetched). The single persistence.addFeed() call in
        // this flow happens inside switchToAtomAlternate's fallback path;
        // addFeedFailureAfterCount = 0 makes that first-and-only call throw.
        mockPersistence.addFeedFailureAfterCount = 0
        let mockDiscovery = MockAtomDiscoveryService()
        mockDiscovery.resultToReturn = atomURL

        let viewModel = AddFeedViewModel(
            feedFetching: mockFetching,
            persistence: mockPersistence,
            atomDiscovery: mockDiscovery
        )
        viewModel.urlInput = rssURL.absoluteString
        await viewModel.addFeed()
        let prompt = try! #require(viewModel.atomAlternatePrompt)
        await viewModel.switchToAtomAlternate(from: prompt)

        // Atom fetch failed → fallback persistence attempted → persistence
        // throws → we surface a chained error message so the user understands
        // the Atom attempt was the trigger (retrying the same flow won't help).
        #expect(viewModel.atomFallbackNotice == nil)
        #expect(viewModel.didAddFeed == false)
        #expect(viewModel.errorMessage == "The Atom feed couldn't be loaded, and saving the RSS version also failed. Please try again.")
        #expect(mockPersistence.feeds.isEmpty)
    }

    @Test("switchToAtomAlternate reports duplicate when Atom URL already subscribed")
    @MainActor
    func switchToAtomAlternateDetectsDuplicate() async {
        let rssURL = URL(string: "https://example.com/feed")!
        let atomURL = URL(string: "https://example.com/atom.xml")!

        let mockFetching = MockFeedFetchingService()
        mockFetching.feedsByURL[rssURL] = TestFixtures.makeFeed(title: "RSS Version", format: .rss)
        let mockPersistence = MockFeedPersistenceService()
        mockPersistence.feeds = [TestFixtures.makePersistentFeed(feedURL: atomURL)]
        let mockDiscovery = MockAtomDiscoveryService()
        mockDiscovery.resultToReturn = atomURL

        let viewModel = AddFeedViewModel(
            feedFetching: mockFetching,
            persistence: mockPersistence,
            atomDiscovery: mockDiscovery
        )
        viewModel.urlInput = rssURL.absoluteString
        await viewModel.addFeed()
        let prompt = try! #require(viewModel.atomAlternatePrompt)
        await viewModel.switchToAtomAlternate(from: prompt)

        #expect(viewModel.didAddFeed == false)
        #expect(viewModel.errorMessage == "You are already subscribed to this feed.")
        // Only the pre-existing Atom feed remains; no new feed was added.
        #expect(mockPersistence.feeds.count == 1)
        // Regression guard (see switchToAtomAlternateFallsBackOnFetchFailure).
        #expect(viewModel.urlInput == rssURL.absoluteString)
    }
}
