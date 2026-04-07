import Testing
import Foundation
@testable import RSSApp

/// Verifies the `PersistentArticle.init(from: Article)` convenience initializer's
/// `sortDate` computation. The init must:
///   1. Preserve `publishedDate` exactly as the publisher provided it (the
///      content-update detection feature in `FeedPersistenceService.upsertArticles`
///      compares pubDate / updatedDate values across refreshes — clamping would
///      destroy that signal).
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

    // MARK: - updatedDate / wasUpdated round-trip (issue #74)

    @Test("updatedDate round-trips through Article → PersistentArticle → Article unchanged")
    func updatedDateRoundTrip() {
        let published = Date(timeIntervalSince1970: 1_700_000_000)
        let updated = Date(timeIntervalSince1970: 1_700_003_600) // +1 hour
        let article = TestFixtures.makeArticle(
            publishedDate: published,
            updatedDate: updated
        )

        let persistent = PersistentArticle(from: article)
        #expect(persistent.publishedDate == published)
        #expect(persistent.updatedDate == updated)
        // Fresh inserts must default wasUpdated to false. The true-side of the contract
        // (set by `FeedPersistenceService.upsertArticles` when an update bump is detected)
        // is pinned by the upsert tests in `FeedPersistenceServiceTests` — see issue #74.
        #expect(persistent.wasUpdated == false)

        let roundTripped = persistent.toArticle()
        #expect(roundTripped.publishedDate == published)
        #expect(roundTripped.updatedDate == updated)
    }

    @Test("Nil updatedDate round-trips as nil")
    func nilUpdatedDateRoundTrips() {
        let article = TestFixtures.makeArticle(
            publishedDate: Date(timeIntervalSince1970: 1_700_000_000),
            updatedDate: nil
        )

        let persistent = PersistentArticle(from: article)
        #expect(persistent.updatedDate == nil)
        #expect(persistent.wasUpdated == false)

        let roundTripped = persistent.toArticle()
        #expect(roundTripped.updatedDate == nil)
    }

    // MARK: - displayedPublishedDate (issue #74)

    @Test("displayedPublishedDate uses publishedDate when it predates fetchedDate")
    func displayedPublishedDateForPastPublication() {
        // Past publishedDate clamps through unchanged because it's <= fetchedDate.
        let past = Date(timeIntervalSince1970: 1_000_000)
        let article = TestFixtures.makeArticle(publishedDate: past)
        let persistent = PersistentArticle(from: article)

        #expect(persistent.displayedPublishedDate == past)
    }

    @Test("displayedPublishedDate clamps a future publishedDate to fetchedDate")
    func displayedPublishedDateClampsFuture() {
        // Future publishedDate (Cloudflare-style scheduled post) is clamped to fetchedDate
        // for display purposes — same guarantee that clampedSortDate provides at insert
        // time, but recomputed inline so the row view never shows a future date even
        // though `upsertArticles` mutates `sortDate` on content-update detection (issue #74).
        let future = Date().addingTimeInterval(4 * 60 * 60)
        let article = TestFixtures.makeArticle(publishedDate: future)
        let persistent = PersistentArticle(from: article)

        #expect(persistent.displayedPublishedDate == persistent.fetchedDate)
        #expect(persistent.displayedPublishedDate <= Date())
        // Symbolic invariant: regardless of which branch the formula takes, the result
        // must never exceed fetchedDate. Pins the formula shape against a refactor that
        // accidentally swaps the operand order (e.g., `min(publishedDate, fetchedDate) ?? fetchedDate`).
        #expect(persistent.displayedPublishedDate <= persistent.fetchedDate)
    }

    @Test("displayedPublishedDate falls back to fetchedDate when publishedDate is nil")
    func displayedPublishedDateFallsBackWhenNil() {
        let article = TestFixtures.makeArticle(publishedDate: nil)
        let persistent = PersistentArticle(from: article)

        #expect(persistent.displayedPublishedDate == persistent.fetchedDate)
        #expect(persistent.displayedPublishedDate <= persistent.fetchedDate)
    }

    @Test("displayedPublishedDate is always <= fetchedDate for past publication")
    func displayedPublishedDateSymbolicInvariantForPastPublication() {
        // Pin the symbolic <= fetchedDate invariant on the most common code path,
        // not just on the future-clamp path. Catches a refactor that accidentally
        // adds an unconditional `Date()` clamp at read time, which would make the
        // displayed value non-stable.
        let past = Date(timeIntervalSince1970: 1_000_000)
        let article = TestFixtures.makeArticle(publishedDate: past)
        let persistent = PersistentArticle(from: article)

        #expect(persistent.displayedPublishedDate <= persistent.fetchedDate)
    }
}
