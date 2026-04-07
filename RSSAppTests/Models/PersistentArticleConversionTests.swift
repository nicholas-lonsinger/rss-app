import Testing
import Foundation
@testable import RSSApp

/// Verifies the `PersistentArticle.init(from: Article)` convenience initializer's
/// `sortDate` computation. The init must:
///   1. Preserve `publishedDate` exactly as the publisher provided it (used by a
///      planned content-update detection feature that compares pubDate values
///      across refreshes — clamping would destroy that signal).
///   2. Compute `sortDate` as `min(publishedDate ?? now, now)` so future-dated
///      articles sort as fresh (not pinned to the top of newest-first lists by
///      an inflated future timestamp).
///
/// These tests are intentionally standalone — no SwiftData container needed —
/// because they exercise pure struct-to-class conversion.
@Suite("PersistentArticle Conversion Tests")
struct PersistentArticleConversionTests {

    @Test("Future publishedDate is clamped in sortDate but preserved in publishedDate")
    func futureClampPreservesPublishedDate() {
        let future = Date().addingTimeInterval(4 * 60 * 60) // +4 hours, Cloudflare-style
        let article = TestFixtures.makeArticle(publishedDate: future)

        let before = Date()
        let persistent = PersistentArticle(from: article)
        let after = Date()

        // publishedDate is preserved verbatim
        #expect(persistent.publishedDate == future)
        // sortDate is clamped to ingestion time
        #expect(persistent.sortDate >= before)
        #expect(persistent.sortDate <= after)
    }

    @Test("Past publishedDate passes through unchanged into sortDate")
    func pastPublishedDatePassesThrough() {
        let past = Date(timeIntervalSince1970: 1_000_000)
        let article = TestFixtures.makeArticle(publishedDate: past)

        let persistent = PersistentArticle(from: article)

        #expect(persistent.publishedDate == past)
        #expect(persistent.sortDate == past)
    }

    @Test("Nil publishedDate falls back to ingestion time in sortDate")
    func nilPublishedDateFallsBackToNow() {
        let article = TestFixtures.makeArticle(publishedDate: nil)

        let before = Date()
        let persistent = PersistentArticle(from: article)
        let after = Date()

        // nil is preserved on publishedDate
        #expect(persistent.publishedDate == nil)
        // sortDate gets a stable, non-optional fallback
        #expect(persistent.sortDate >= before)
        #expect(persistent.sortDate <= after)
    }
}
