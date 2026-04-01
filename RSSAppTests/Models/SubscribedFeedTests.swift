import Testing
import Foundation
@testable import RSSApp

@Suite("SubscribedFeed Tests")
struct SubscribedFeedTests {

    @Test("updatingMetadata preserves id, url, and addedDate")
    func updatingMetadataPreservesIdentity() {
        let original = TestFixtures.makeSubscribedFeed(
            title: "Old Title",
            feedDescription: "Old Description"
        )
        let updated = original.updatingMetadata(
            title: "New Title",
            feedDescription: "New Description"
        )

        #expect(updated.id == original.id)
        #expect(updated.url == original.url)
        #expect(updated.addedDate == original.addedDate)
        #expect(updated.title == "New Title")
        #expect(updated.feedDescription == "New Description")
    }

    @Test("updatingMetadata does not mutate original")
    func updatingMetadataDoesNotMutate() {
        let original = TestFixtures.makeSubscribedFeed(
            title: "Original",
            feedDescription: "Original Desc"
        )
        let _ = original.updatingMetadata(title: "Changed", feedDescription: "Changed Desc")

        #expect(original.title == "Original")
        #expect(original.feedDescription == "Original Desc")
    }
}
