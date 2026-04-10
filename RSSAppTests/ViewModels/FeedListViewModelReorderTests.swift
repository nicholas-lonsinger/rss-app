import Testing
import Foundation
@testable import RSSApp

@Suite("FeedListViewModel Reorder Tests")
struct FeedListViewModelReorderTests {

    @Test("moveFeed reorders feeds and persists sortOrder")
    @MainActor
    func moveFeedSuccess() {
        let mockPersistence = MockFeedPersistenceService()
        let feedA = TestFixtures.makePersistentFeed(
            title: "Alpha",
            feedURL: URL(string: "https://alpha.com/feed")!,
            addedDate: Date(timeIntervalSince1970: 1_000_000),
            sortOrder: 0
        )
        let feedB = TestFixtures.makePersistentFeed(
            title: "Beta",
            feedURL: URL(string: "https://beta.com/feed")!,
            addedDate: Date(timeIntervalSince1970: 2_000_000),
            sortOrder: 1
        )
        let feedC = TestFixtures.makePersistentFeed(
            title: "Charlie",
            feedURL: URL(string: "https://charlie.com/feed")!,
            addedDate: Date(timeIntervalSince1970: 3_000_000),
            sortOrder: 2
        )
        mockPersistence.feeds = [feedA, feedB, feedC]

        let mockIconService = MockFeedIconService()
        let refreshService = FeedRefreshService(persistence: mockPersistence, feedIconService: mockIconService)
        let viewModel = FeedListViewModel(
            persistence: mockPersistence,
            refreshService: refreshService,
            feedIconService: mockIconService
        )
        viewModel.loadFeeds()
        #expect(viewModel.feeds.map(\.title) == ["Alpha", "Beta", "Charlie"])

        // Move Charlie (index 2) to index 0
        viewModel.moveFeed(from: IndexSet(integer: 2), to: 0)

        #expect(viewModel.feeds.map(\.title) == ["Charlie", "Alpha", "Beta"])
        #expect(viewModel.feeds[0].sortOrder == 0)
        #expect(viewModel.feeds[1].sortOrder == 1)
        #expect(viewModel.feeds[2].sortOrder == 2)
        #expect(viewModel.errorMessage == nil)
    }

    @Test("moveFeed restores order on persistence failure")
    @MainActor
    func moveFeedError() {
        let mockPersistence = MockFeedPersistenceService()
        let feedA = TestFixtures.makePersistentFeed(
            title: "Alpha",
            feedURL: URL(string: "https://alpha.com/feed")!,
            addedDate: Date(timeIntervalSince1970: 1_000_000),
            sortOrder: 0
        )
        let feedB = TestFixtures.makePersistentFeed(
            title: "Beta",
            feedURL: URL(string: "https://beta.com/feed")!,
            addedDate: Date(timeIntervalSince1970: 2_000_000),
            sortOrder: 1
        )
        mockPersistence.feeds = [feedA, feedB]

        let mockIconService = MockFeedIconService()
        let refreshService = FeedRefreshService(persistence: mockPersistence, feedIconService: mockIconService)
        let viewModel = FeedListViewModel(
            persistence: mockPersistence,
            refreshService: refreshService,
            feedIconService: mockIconService
        )
        viewModel.loadFeeds()

        // Inject error for the updateFeedOrder call
        mockPersistence.updateFeedOrderError = NSError(domain: "test", code: 1)

        viewModel.moveFeed(from: IndexSet(integer: 1), to: 0)

        // On failure, loadFeeds() reloads from persistence, restoring the original order
        #expect(viewModel.feeds.map(\.title) == ["Alpha", "Beta"])
        #expect(viewModel.errorMessage != nil)
    }

    @Test("moveFeed moves first feed to end")
    @MainActor
    func moveFeedToEnd() {
        let mockPersistence = MockFeedPersistenceService()
        let feedA = TestFixtures.makePersistentFeed(
            title: "Alpha",
            feedURL: URL(string: "https://alpha.com/feed")!,
            addedDate: Date(timeIntervalSince1970: 1_000_000),
            sortOrder: 0
        )
        let feedB = TestFixtures.makePersistentFeed(
            title: "Beta",
            feedURL: URL(string: "https://beta.com/feed")!,
            addedDate: Date(timeIntervalSince1970: 2_000_000),
            sortOrder: 1
        )
        let feedC = TestFixtures.makePersistentFeed(
            title: "Charlie",
            feedURL: URL(string: "https://charlie.com/feed")!,
            addedDate: Date(timeIntervalSince1970: 3_000_000),
            sortOrder: 2
        )
        mockPersistence.feeds = [feedA, feedB, feedC]

        let mockIconService = MockFeedIconService()
        let refreshService = FeedRefreshService(persistence: mockPersistence, feedIconService: mockIconService)
        let viewModel = FeedListViewModel(
            persistence: mockPersistence,
            refreshService: refreshService,
            feedIconService: mockIconService
        )
        viewModel.loadFeeds()

        // Move Alpha (index 0) to end (destination 3)
        viewModel.moveFeed(from: IndexSet(integer: 0), to: 3)

        #expect(viewModel.feeds.map(\.title) == ["Beta", "Charlie", "Alpha"])
        #expect(viewModel.feeds[0].sortOrder == 0)
        #expect(viewModel.feeds[1].sortOrder == 1)
        #expect(viewModel.feeds[2].sortOrder == 2)
    }
}
