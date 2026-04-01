import Testing
import Foundation
@testable import RSSApp

@Suite("FeedStorageService Tests")
struct FeedStorageServiceTests {

    private func makeService() -> FeedStorageService {
        let suiteName = "FeedStorageServiceTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return FeedStorageService(defaults: defaults)
    }

    @Test("loadFeeds returns empty array when no data stored")
    func loadFeedsEmpty() {
        let service = makeService()
        #expect(service.loadFeeds().isEmpty)
    }

    @Test("saveFeeds and loadFeeds roundtrip")
    func saveAndLoadRoundtrip() {
        let service = makeService()
        let feeds = [
            TestFixtures.makeSubscribedFeed(title: "Feed A"),
            TestFixtures.makeSubscribedFeed(title: "Feed B"),
        ]

        service.saveFeeds(feeds)
        let loaded = service.loadFeeds()

        #expect(loaded.count == 2)
        #expect(loaded[0].title == "Feed A")
        #expect(loaded[1].title == "Feed B")
    }

    @Test("addFeed appends to existing feeds")
    func addFeedAppends() {
        let service = makeService()
        let feed1 = TestFixtures.makeSubscribedFeed(title: "First")
        let feed2 = TestFixtures.makeSubscribedFeed(title: "Second")

        service.addFeed(feed1)
        service.addFeed(feed2)

        let loaded = service.loadFeeds()
        #expect(loaded.count == 2)
        #expect(loaded[0].title == "First")
        #expect(loaded[1].title == "Second")
    }

    @Test("removeFeed deletes by ID")
    func removeFeedByID() {
        let service = makeService()
        let feed1 = TestFixtures.makeSubscribedFeed(title: "Keep")
        let feed2 = TestFixtures.makeSubscribedFeed(title: "Remove")

        service.addFeed(feed1)
        service.addFeed(feed2)
        service.removeFeed(withID: feed2.id)

        let loaded = service.loadFeeds()
        #expect(loaded.count == 1)
        #expect(loaded[0].title == "Keep")
    }

    @Test("removeFeed with non-existent ID is no-op")
    func removeNonExistentID() {
        let service = makeService()
        let feed = TestFixtures.makeSubscribedFeed()

        service.addFeed(feed)
        service.removeFeed(withID: UUID())

        #expect(service.loadFeeds().count == 1)
    }

    @Test("saveFeeds overwrites previous data")
    func saveFeedsOverwrites() {
        let service = makeService()

        service.saveFeeds([TestFixtures.makeSubscribedFeed(title: "Old")])
        service.saveFeeds([TestFixtures.makeSubscribedFeed(title: "New")])

        let loaded = service.loadFeeds()
        #expect(loaded.count == 1)
        #expect(loaded[0].title == "New")
    }
}
