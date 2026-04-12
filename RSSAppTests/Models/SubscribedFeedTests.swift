import Testing
import Foundation
@testable import RSSApp

@Suite("SubscribedFeed Tests")
struct SubscribedFeedTests {

    @Test("updatingMetadata preserves id, url, siteURL, and addedDate")
    func updatingMetadataPreservesIdentity() {
        let siteURL = URL(string: "https://example.com")!
        let original = TestFixtures.makeSubscribedFeed(
            title: "Old Title",
            feedDescription: "Old Description",
            siteURL: siteURL
        )
        let updated = original.updatingMetadata(
            title: "New Title",
            feedDescription: "New Description"
        )

        #expect(updated.id == original.id)
        #expect(updated.url == original.url)
        #expect(updated.siteURL == siteURL)
        #expect(updated.addedDate == original.addedDate)
        #expect(updated.title == "New Title")
        #expect(updated.feedDescription == "New Description")
    }

    @Test("updatingMetadata clears error state")
    func updatingMetadataClearsError() {
        let feed = TestFixtures.makeSubscribedFeed(
            lastFetchError: "HTTP 404",
            lastFetchErrorDate: Date()
        )
        let updated = feed.updatingMetadata(title: "Title", feedDescription: "Desc")

        #expect(updated.lastFetchError == nil)
        #expect(updated.lastFetchErrorDate == nil)
    }

    @Test("updatingError sets error fields and preserves siteURL")
    func updatingErrorSetsFields() {
        let siteURL = URL(string: "https://example.com")!
        let feed = TestFixtures.makeSubscribedFeed(siteURL: siteURL)
        let updated = feed.updatingError("HTTP 404")

        #expect(updated.lastFetchError == "HTTP 404")
        #expect(updated.lastFetchErrorDate != nil)
        #expect(updated.id == feed.id)
        #expect(updated.url == feed.url)
        #expect(updated.siteURL == siteURL)
    }

    @Test("updatingURL changes URL, clears error, and preserves siteURL")
    func updatingURLChangesAndClearsError() {
        let siteURL = URL(string: "https://example.com")!
        let feed = TestFixtures.makeSubscribedFeed(
            siteURL: siteURL,
            lastFetchError: "HTTP 404",
            lastFetchErrorDate: Date()
        )
        let newURL = URL(string: "https://example.com/new-feed")!
        let updated = feed.updatingURL(newURL)

        #expect(updated.url == newURL)
        #expect(updated.lastFetchError == nil)
        #expect(updated.lastFetchErrorDate == nil)
        #expect(updated.id == feed.id)
        #expect(updated.title == feed.title)
        #expect(updated.siteURL == siteURL)
    }

    @Test("Codable roundtrip preserves error fields")
    func codableRoundtripWithError() throws {
        let feed = TestFixtures.makeSubscribedFeed(
            lastFetchError: "HTTP 404",
            lastFetchErrorDate: Date(timeIntervalSince1970: 1_712_000_000)
        )

        let data = try JSONEncoder().encode(feed)
        let decoded = try JSONDecoder().decode(SubscribedFeed.self, from: data)

        #expect(decoded.lastFetchError == "HTTP 404")
        #expect(decoded.lastFetchErrorDate == Date(timeIntervalSince1970: 1_712_000_000))
    }

    @Test("Codable backward compatibility — missing error fields decode as nil")
    func codableBackwardCompatibility() throws {
        let json = """
            {
                "id": "00000000-0000-0000-0000-000000000001",
                "title": "Old Feed",
                "url": "https://example.com/feed",
                "feedDescription": "A feed",
                "addedDate": 0
            }
            """
        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(SubscribedFeed.self, from: data)

        #expect(decoded.lastFetchError == nil)
        #expect(decoded.lastFetchErrorDate == nil)
        #expect(decoded.title == "Old Feed")
    }
}
