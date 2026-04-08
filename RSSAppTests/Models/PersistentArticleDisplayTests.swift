import Testing
import Foundation
@testable import RSSApp

/// Verifies the display-helper computed properties on `PersistentArticle` that the
/// row views read directly. These properties contain real predicate logic (the
/// `shouldShowUpdatedSuffix` tolerance check, the `displayedPublishedDate` clamp)
/// that needs unit coverage independent of any SwiftUI view machinery.
@Suite("PersistentArticle Display Helper Tests")
struct PersistentArticleDisplayTests {

    // MARK: - shouldShowUpdatedSuffix (issue #74)

    /// Constructs a minimal article with the given dates so the predicate can be
    /// exercised in isolation. `fetchedDate` is fixed to a known timestamp so
    /// `displayedPublishedDate`'s clamp behavior is deterministic across tests.
    private func makeRow(
        published: Date?,
        updated: Date?,
        fetched: Date = Date(timeIntervalSince1970: 1_700_000_000)
    ) -> PersistentArticle {
        PersistentArticle(
            articleID: "x",
            title: "t",
            publishedDate: published,
            updatedDate: updated,
            fetchedDate: fetched
        )
    }

    @Test("shouldShowUpdatedSuffix returns false when updatedDate is nil")
    func shouldShowUpdatedSuffixNilUpdated() {
        let base = Date(timeIntervalSince1970: 1_700_000_000 - 86_400)
        let row = makeRow(published: base, updated: nil)
        #expect(row.shouldShowUpdatedSuffix == false)
    }

    @Test("shouldShowUpdatedSuffix returns false when delta is exactly zero")
    func shouldShowUpdatedSuffixZeroDelta() {
        let base = Date(timeIntervalSince1970: 1_700_000_000 - 86_400)
        let row = makeRow(published: base, updated: base)
        #expect(row.shouldShowUpdatedSuffix == false)
    }

    @Test("shouldShowUpdatedSuffix returns false when delta is below the 1-second tolerance")
    func shouldShowUpdatedSuffixSubSecondDelta() {
        let base = Date(timeIntervalSince1970: 1_700_000_000 - 86_400)
        let row = makeRow(published: base, updated: base.addingTimeInterval(0.5))
        #expect(row.shouldShowUpdatedSuffix == false)
    }

    @Test("shouldShowUpdatedSuffix returns true for a typical 1-hour publisher revision")
    func shouldShowUpdatedSuffixTypicalRevision() {
        let base = Date(timeIntervalSince1970: 1_700_000_000 - 86_400)
        let row = makeRow(published: base, updated: base.addingTimeInterval(3600))
        #expect(row.shouldShowUpdatedSuffix == true)
    }

    @Test("shouldShowUpdatedSuffix uses absolute delta — updatedDate before displayedPublishedDate still triggers")
    func shouldShowUpdatedSuffixNegativeDelta() {
        // Past published, past updated even further back. The abs() in the predicate
        // means a negative delta (updated before displayed publication) still surfaces
        // the suffix. Catches a refactor that drops the abs() and silently hides
        // legitimate update timestamps.
        let fetched = Date(timeIntervalSince1970: 1_700_000_000)
        let published = fetched.addingTimeInterval(-3600) // 1h before fetch
        let updated = fetched.addingTimeInterval(-7200)   // 2h before fetch (and before published)
        let row = makeRow(published: published, updated: updated, fetched: fetched)
        // displayedPublishedDate == published (past, so unchanged); |updated - published| == 3600 > 1
        #expect(row.shouldShowUpdatedSuffix == true)
    }

    @Test("shouldShowUpdatedSuffix compares against displayedPublishedDate, not raw publishedDate")
    func shouldShowUpdatedSuffixUsesClampedDisplayDate() {
        // Future-dated publish gets clamped by `displayedPublishedDate` to `fetchedDate`.
        // If updatedDate exactly matches fetchedDate, the predicate must compare
        // against the *clamped* display date — yielding a delta of zero (within
        // tolerance) — and NOT against the raw future publishedDate (which would
        // yield a non-zero delta and incorrectly show the suffix). This is the
        // single highest-value regression guard for this predicate: a refactor that
        // "simplifies" the comparison to use `publishedDate` directly would defeat
        // PR 1's entire reason for adding `displayedPublishedDate`.
        let fetched = Date(timeIntervalSince1970: 1_700_000_000)
        let futurePublish = fetched.addingTimeInterval(86_400) // 1 day in the future
        let updated = fetched                                  // exactly == clamped display
        let row = makeRow(published: futurePublish, updated: updated, fetched: fetched)
        #expect(row.shouldShowUpdatedSuffix == false)
    }
}
