import Testing
import Foundation
@testable import RSSApp

@Suite("FeedStorageService Tests")
struct FeedStorageServiceTests {

    private func makeService() -> (FeedStorageService, UserDefaults) {
        let suiteName = "FeedStorageServiceTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (FeedStorageService(defaults: defaults), defaults)
    }

    @Test("loadFeeds returns empty array when no data stored")
    func loadFeedsEmpty() throws {
        let (service, _) = makeService()
        #expect(try service.loadFeeds().isEmpty)
    }

    @Test("saveFeeds and loadFeeds roundtrip")
    func saveAndLoadRoundtrip() throws {
        let (service, _) = makeService()
        let feeds = [
            TestFixtures.makeSubscribedFeed(title: "Feed A"),
            TestFixtures.makeSubscribedFeed(title: "Feed B"),
        ]

        try service.saveFeeds(feeds)
        let loaded = try service.loadFeeds()

        #expect(loaded.count == 2)
        #expect(loaded[0] == feeds[0])
        #expect(loaded[1] == feeds[1])
    }

    @Test("removeFeed with non-existent ID is no-op")
    func removeNonExistentID() throws {
        let (service, _) = makeService()
        let feed = TestFixtures.makeSubscribedFeed()

        try service.saveFeeds([feed])

        var feeds = try service.loadFeeds()
        feeds.removeAll { $0.id == UUID() }
        try service.saveFeeds(feeds)

        #expect(try service.loadFeeds().count == 1)
    }

    @Test("saveFeeds overwrites previous data")
    func saveFeedsOverwrites() throws {
        let (service, _) = makeService()

        try service.saveFeeds([TestFixtures.makeSubscribedFeed(title: "Old")])
        try service.saveFeeds([TestFixtures.makeSubscribedFeed(title: "New")])

        let loaded = try service.loadFeeds()
        #expect(loaded.count == 1)
        #expect(loaded[0].title == "New")
    }

    @Test("loadFeeds throws on corrupt data")
    func loadFeedsCorruptData() throws {
        let (service, defaults) = makeService()
        defaults.set(Data("not valid json".utf8), forKey: "subscribedFeeds")

        #expect(throws: (any Error).self) {
            try service.loadFeeds()
        }
    }
}
