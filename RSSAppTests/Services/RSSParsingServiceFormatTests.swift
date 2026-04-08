import Testing
import Foundation
@testable import RSSApp

@Suite("RSSParsingService FeedFormat detection")
struct RSSParsingServiceFormatTests {

    let service = RSSParsingService()

    @Test("RSS feed is tagged as .rss")
    func parsesRSSAsRSS() throws {
        let feed = try service.parse(Data(TestFixtures.sampleRSSXML.utf8))
        #expect(feed.format == .rss)
    }

    @Test("Atom feed is tagged as .atom")
    func parsesAtomAsAtom() throws {
        let feed = try service.parse(Data(TestFixtures.sampleAtomXML.utf8))
        #expect(feed.format == .atom)
    }
}
