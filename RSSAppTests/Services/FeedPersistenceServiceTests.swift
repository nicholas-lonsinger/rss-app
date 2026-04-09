import Testing
import Foundation
import SwiftData
@testable import RSSApp

@Suite("FeedPersistenceService Tests", .serialized)
struct FeedPersistenceServiceTests {

    @MainActor
    private func makeService() throws -> (SwiftDataFeedPersistenceService, ModelContainer) {
        try SwiftDataTestHelpers.makeTestPersistenceService()
    }

    // MARK: - Feed Operations

    @Test("allFeeds returns empty array initially")
    @MainActor
    func allFeedsEmpty() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feeds = try service.allFeeds()
        #expect(feeds.isEmpty)
    }

    @Test("addFeed persists a feed")
    @MainActor
    func addFeedPersists() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feed = TestFixtures.makePersistentFeed(title: "My Feed")

        try service.addFeed(feed)
        let feeds = try service.allFeeds()

        #expect(feeds.count == 1)
        #expect(feeds[0].title == "My Feed")
    }

    @Test("deleteFeed removes a feed")
    @MainActor
    func deleteFeedRemoves() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feed = TestFixtures.makePersistentFeed()

        try service.addFeed(feed)
        try service.deleteFeed(feed)
        let feeds = try service.allFeeds()

        #expect(feeds.isEmpty)
    }

    @Test("updateFeedMetadata updates title and description, clears error state")
    @MainActor
    func updateFeedMetadata() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feed = TestFixtures.makePersistentFeed(
            title: "Old Title",
            lastFetchError: "some error",
            lastFetchErrorDate: Date()
        )

        try service.addFeed(feed)
        try service.updateFeedMetadata(feed, title: "New Title", description: "New Desc")

        #expect(feed.title == "New Title")
        #expect(feed.feedDescription == "New Desc")
        #expect(feed.lastRefreshDate != nil)
        #expect(feed.lastFetchError == nil)
        #expect(feed.lastFetchErrorDate == nil)
    }

    @Test("updateFeedError sets error state")
    @MainActor
    func updateFeedError() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feed = TestFixtures.makePersistentFeed()

        try service.addFeed(feed)
        try service.updateFeedError(feed, error: "Network error")

        #expect(feed.lastFetchError == "Network error")
        #expect(feed.lastFetchErrorDate != nil)
    }

    @Test("updateFeedError with nil clears error state")
    @MainActor
    func updateFeedErrorClears() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feed = TestFixtures.makePersistentFeed(
            lastFetchError: "old error",
            lastFetchErrorDate: Date()
        )

        try service.addFeed(feed)
        try service.updateFeedError(feed, error: nil)

        #expect(feed.lastFetchError == nil)
        #expect(feed.lastFetchErrorDate == nil)
    }

    @Test("updateFeedURL changes URL and clears error state")
    @MainActor
    func updateFeedURL() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feed = TestFixtures.makePersistentFeed(
            lastFetchError: "error",
            lastFetchErrorDate: Date()
        )

        try service.addFeed(feed)
        let newURL = URL(string: "https://new.example.com/feed")!
        try service.updateFeedURL(feed, newURL: newURL)

        #expect(feed.feedURL == newURL)
        #expect(feed.lastFetchError == nil)
    }

    @Test("feedExists returns true for existing URL")
    @MainActor
    func feedExistsTrue() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let url = URL(string: "https://example.com/feed")!
        let feed = TestFixtures.makePersistentFeed(feedURL: url)

        try service.addFeed(feed)

        #expect(try service.feedExists(url: url))
    }

    @Test("feedExists returns false for unknown URL")
    @MainActor
    func feedExistsFalse() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let url = URL(string: "https://unknown.com/feed")!

        #expect(try !service.feedExists(url: url))
    }

    @Test("updateFeedCacheHeaders stores etag and lastModified")
    @MainActor
    func updateCacheHeaders() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feed = TestFixtures.makePersistentFeed()

        try service.addFeed(feed)
        try service.updateFeedCacheHeaders(feed, etag: "abc123", lastModified: "Mon, 01 Jan 2026 00:00:00 GMT")

        #expect(feed.etag == "abc123")
        #expect(feed.lastModifiedHeader == "Mon, 01 Jan 2026 00:00:00 GMT")
    }

    // MARK: - Article Operations

    @Test("upsertArticles inserts new articles")
    @MainActor
    func upsertArticlesInserts() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feed = TestFixtures.makePersistentFeed()
        try service.addFeed(feed)

        let articles = [
            TestFixtures.makeArticle(id: "a1", title: "Article 1"),
            TestFixtures.makeArticle(id: "a2", title: "Article 2"),
        ]

        try service.upsertArticles(articles, for: feed)
        let persisted = try service.articles(for: feed)

        #expect(persisted.count == 2)
    }

    @Test("upsertArticles skips existing articles preserving read status")
    @MainActor
    func upsertArticlesSkipsExisting() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feed = TestFixtures.makePersistentFeed()
        try service.addFeed(feed)

        let articles = [TestFixtures.makeArticle(id: "a1", title: "Original")]
        try service.upsertArticles(articles, for: feed)

        // Mark as read
        let persisted = try service.articles(for: feed)
        try service.markArticleRead(persisted[0], isRead: true)

        // Re-upsert with no `updatedDate` (the default) — must no-op even though
        // the title differs. This pins the historical insert-only semantics for
        // feeds that don't expose `<updated>`. The update-detection mutation path
        // is exercised separately by `upsertArticlesMutatesOnNewerUpdatedDate`.
        let updatedArticles = [TestFixtures.makeArticle(id: "a1", title: "Updated")]
        try service.upsertArticles(updatedArticles, for: feed)

        let afterUpsert = try service.articles(for: feed)
        #expect(afterUpsert.count == 1)
        #expect(afterUpsert[0].isRead == true)
    }

    @Test("upsertArticles preserves thumbnail caching fields on existing articles")
    @MainActor
    func upsertArticlesPreservesThumbnailFields() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feed = TestFixtures.makePersistentFeed()
        try service.addFeed(feed)

        // Insert an article
        let articles = [TestFixtures.makeArticle(id: "thumb1", title: "Thumbnail Article")]
        try service.upsertArticles(articles, for: feed)

        // Set thumbnail state on the persisted article
        let persisted = try service.articles(for: feed)
        #expect(persisted.count == 1)
        try service.markThumbnailCached(persisted[0])
        try service.incrementThumbnailRetryCount(persisted[0])
        try service.incrementThumbnailRetryCount(persisted[0])
        try service.save()

        // Verify pre-conditions
        #expect(persisted[0].isThumbnailCached == true)
        #expect(persisted[0].thumbnailRetryCount == 2)

        // Re-upsert with no `updatedDate` — must no-op, leaving thumbnail state alone.
        // Preservation through the UPDATE-MUTATION path is pinned separately in
        // `upsertArticlesMutatesOnNewerUpdatedDatePreservesUntouchedFields`.
        let updatedArticles = [TestFixtures.makeArticle(id: "thumb1", title: "Updated Title")]
        try service.upsertArticles(updatedArticles, for: feed)

        let afterUpsert = try service.articles(for: feed)
        #expect(afterUpsert.count == 1)
        #expect(afterUpsert[0].isThumbnailCached == true)
        #expect(afterUpsert[0].thumbnailRetryCount == 2)
    }

    // MARK: - upsertArticles update detection (issue #74)

    @Test("Fresh inserts default wasUpdated to false")
    @MainActor
    func upsertArticlesFreshInsertsDefaultWasUpdatedFalse() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feed = TestFixtures.makePersistentFeed()
        try service.addFeed(feed)

        try service.upsertArticles(
            [TestFixtures.makeArticle(id: "fresh", updatedDate: Date())],
            for: feed
        )

        let persisted = try service.articles(for: feed)
        #expect(persisted.count == 1)
        #expect(persisted[0].wasUpdated == false)
    }

    @Test("Re-fetch with same updatedDate is a no-op")
    @MainActor
    func upsertArticlesNoOpForSameUpdatedDate() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feed = TestFixtures.makePersistentFeed()
        try service.addFeed(feed)

        let updated = Date(timeIntervalSince1970: 1_700_000_000)
        try service.upsertArticles(
            [TestFixtures.makeArticle(
                id: "same",
                title: "Original",
                articleDescription: "<p>Original body</p>",
                snippet: "Original body",
                updatedDate: updated
            )],
            for: feed
        )

        let beforeRefetch = try service.articles(for: feed)
        try service.markArticleRead(beforeRefetch[0], isRead: true)
        let originalSortDate = beforeRefetch[0].sortDate

        // Re-fetch with the SAME updatedDate but a different title AND a different
        // body — must not mutate any field. Passing different body content here pins
        // the contract that body content is overwritten ONLY when the update path
        // fires (which it doesn't here, because the timestamp didn't move).
        try service.upsertArticles(
            [TestFixtures.makeArticle(
                id: "same",
                title: "Different Title",
                articleDescription: "<p>Publisher-edited body without &lt;updated&gt; bump</p>",
                snippet: "Publisher-edited body without <updated> bump",
                updatedDate: updated
            )],
            for: feed
        )

        let afterRefetch = try service.articles(for: feed)
        #expect(afterRefetch.count == 1)
        #expect(afterRefetch[0].isRead == true)
        #expect(afterRefetch[0].wasUpdated == false)
        #expect(afterRefetch[0].title == "Original") // not overwritten
        #expect(afterRefetch[0].articleDescription == "<p>Original body</p>") // not overwritten
        #expect(afterRefetch[0].snippet == "Original body") // not overwritten
        #expect(afterRefetch[0].sortDate == originalSortDate) // not bumped
    }

    @Test("Re-fetch with strictly newer updatedDate mutates the existing row")
    @MainActor
    func upsertArticlesMutatesOnNewerUpdatedDate() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feed = TestFixtures.makePersistentFeed()
        try service.addFeed(feed)

        let originalPublished = Date(timeIntervalSince1970: 1_699_000_000)
        let originalUpdated = Date(timeIntervalSince1970: 1_700_000_000)
        let originalArticle = TestFixtures.makeArticle(
            id: "evolving",
            title: "Original Title",
            link: URL(string: "https://example.com/evolving"),
            articleDescription: "<p>Original body</p>",
            snippet: "Original body",
            publishedDate: originalPublished,
            updatedDate: originalUpdated,
            thumbnailURL: URL(string: "https://example.com/original-thumb.jpg"),
            author: "Original Author",
            categories: ["original-category"]
        )
        try service.upsertArticles([originalArticle], for: feed)

        let beforeRefetch = try service.articles(for: feed)
        // Prime user-generated and system-managed state so we can verify each field
        // is preserved through the mutation path.
        try service.markArticleRead(beforeRefetch[0], isRead: true)
        try service.toggleArticleSaved(beforeRefetch[0])
        try service.markThumbnailCached(beforeRefetch[0])
        try service.incrementThumbnailRetryCount(beforeRefetch[0])
        try service.incrementThumbnailRetryCount(beforeRefetch[0])
        try service.save()

        let originalSortDate = beforeRefetch[0].sortDate
        let originalSavedDate = beforeRefetch[0].savedDate
        let originalFetchedDate = beforeRefetch[0].fetchedDate

        // Re-fetch with a strictly newer updatedDate and revised body content. Pass
        // *different* values for every preserved-on-update field too — title, link,
        // author, categories, thumbnailURL — so any future refactor that adds those
        // to the mutation block will fail this test.
        let newerUpdated = originalUpdated.addingTimeInterval(3600) // +1 hour
        let revisedArticle = TestFixtures.makeArticle(
            id: "evolving",
            title: "Publisher-Revised Title", // intentionally different
            link: URL(string: "https://example.com/different-link"),
            articleDescription: "<p>Revised body with corrections</p>",
            snippet: "Revised body with corrections",
            publishedDate: originalPublished.addingTimeInterval(86400), // intentionally different
            updatedDate: newerUpdated,
            thumbnailURL: URL(string: "https://example.com/different-thumb.jpg"),
            author: "Different Author",
            categories: ["different-category"]
        )
        try service.upsertArticles([revisedArticle], for: feed)

        let afterRefetch = try service.articles(for: feed)
        #expect(afterRefetch.count == 1)
        let row = afterRefetch[0]

        // ----- Mutated (publisher-visible body content) -----
        #expect(row.updatedDate == newerUpdated)
        #expect(row.wasUpdated == true)
        #expect(row.articleDescription == "<p>Revised body with corrections</p>")
        #expect(row.snippet == "Revised body with corrections")
        #expect(row.sortDate > originalSortDate) // bumped to "now"

        // ----- Reset (article re-surfaces as unread) -----
        #expect(row.isRead == false)
        #expect(row.readDate == nil)

        // ----- Cross-field invariant: wasUpdated == true → updatedDate != nil -----
        #expect(row.wasUpdated == false || row.updatedDate != nil)

        // ----- Preserved (user-generated state and identity not owned by publisher) -----
        // Title / link / author / categories / thumbnailURL — publisher revisions
        // to these are intentionally dropped; only the body refreshes.
        #expect(row.title == "Original Title")
        #expect(row.link?.absoluteString == "https://example.com/evolving")
        #expect(row.author == "Original Author")
        #expect(row.categories == ["original-category"])
        #expect(row.thumbnailURL?.absoluteString == "https://example.com/original-thumb.jpg")
        // publishedDate — verbatim publisher value, never mutated post-insert
        #expect(row.publishedDate == originalPublished)
        // fetchedDate — load-bearing for displayedPublishedDate's clamp ceiling
        #expect(row.fetchedDate == originalFetchedDate)
        // User-generated saved state
        #expect(row.isSaved == true)
        #expect(row.savedDate == originalSavedDate)
        // System-managed thumbnail caching state
        #expect(row.isThumbnailCached == true)
        #expect(row.thumbnailRetryCount == 2)

        // ----- Idempotency: a second call with the same newerUpdated must be a no-op -----
        // Catches a careless `>` → `>=` refactor and a refresh-loop double-pull that
        // would otherwise re-bump sortDate, double-reset isRead, and re-drop content.
        let afterFirstMutationSort = row.sortDate
        try service.upsertArticles([revisedArticle], for: feed)
        let afterIdempotent = try service.articles(for: feed)[0]
        #expect(afterIdempotent.sortDate == afterFirstMutationSort)
        #expect(afterIdempotent.wasUpdated == true)
    }

    @Test("upsertArticles detection path clears readDate on a previously-read article (issue #283)")
    @MainActor
    func upsertArticlesDetectionClearsReadDate() throws {
        // Focused regression pin for issue #283: the `existing.readDate = nil` reset
        // on the `upsertArticles` update-detection path. The primary coverage in
        // `upsertArticlesMutatesOnNewerUpdatedDate` above also asserts this, but
        // that test mutates many fields at once — this test isolates the single
        // sanctioned destructive transition called out in the `markArticleRead`
        // doc comment so grepping for `#283` lands somewhere obvious.
        //
        // Priming is load-bearing: `PersistentArticle.readDate` defaults to nil on
        // insert and `upsertArticles` never stamps it, so without the explicit
        // `markArticleRead(_, isRead: true)` below, `readDate == nil` would hold
        // vacuously and the assertion would not pin the regression.
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feed = TestFixtures.makePersistentFeed()
        try service.addFeed(feed)

        let baseline = Date(timeIntervalSince1970: 1_700_000_000)
        try service.upsertArticles(
            [TestFixtures.makeArticle(id: "u1", updatedDate: baseline)],
            for: feed
        )

        // Prime: user reads the article. This stamps `readDate` to a non-nil value,
        // which is the only state in which the `existing.readDate = nil` line on the
        // detection path can be observed doing any work.
        let seeded = try service.articles(for: feed)[0]
        try service.markArticleRead(seeded, isRead: true)
        let firstReadDate = try #require(seeded.readDate)

        // Trigger detection with a strictly newer updatedDate.
        try service.upsertArticles(
            [TestFixtures.makeArticle(id: "u1", updatedDate: baseline.addingTimeInterval(3600))],
            for: feed
        )

        // Detection must reset `readDate` (sanctioned destructive transition per
        // the `markArticleRead` doc comment), flip `isRead` back to false, and
        // set the `wasUpdated` badge.
        let updated = try service.articles(for: feed)[0]
        #expect(updated.readDate == nil)
        #expect(updated.readDate != firstReadDate)
        #expect(updated.isRead == false)
        #expect(updated.wasUpdated == true)
    }

    @Test("Re-fetch with older updatedDate is a no-op")
    @MainActor
    func upsertArticlesNoOpForOlderUpdatedDate() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feed = TestFixtures.makePersistentFeed()
        try service.addFeed(feed)

        let baseline = Date(timeIntervalSince1970: 1_700_000_000)
        try service.upsertArticles(
            [TestFixtures.makeArticle(id: "stable", updatedDate: baseline)],
            for: feed
        )

        // Re-fetch with an OLDER updatedDate — possible from clock skew or republishing
        // an old <atom:updated>. Must not trigger detection.
        let older = baseline.addingTimeInterval(-3600)
        try service.upsertArticles(
            [TestFixtures.makeArticle(id: "stable", updatedDate: older)],
            for: feed
        )

        let afterRefetch = try service.articles(for: feed)
        #expect(afterRefetch.count == 1)
        #expect(afterRefetch[0].updatedDate == baseline) // not regressed to the older value
        #expect(afterRefetch[0].wasUpdated == false)
    }

    @Test("Re-fetch with no updatedDate is a no-op even when existing has one")
    @MainActor
    func upsertArticlesNoOpWhenIncomingUpdatedDateNil() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feed = TestFixtures.makePersistentFeed()
        try service.addFeed(feed)

        let baseline = Date(timeIntervalSince1970: 1_700_000_000)
        try service.upsertArticles(
            [TestFixtures.makeArticle(id: "had-updated", updatedDate: baseline)],
            for: feed
        )

        // Re-fetch with no updatedDate at all (e.g., the publisher dropped the element).
        // Must not trigger detection — preserves the historical insert-only semantics
        // for feeds that don't expose <updated>.
        try service.upsertArticles(
            [TestFixtures.makeArticle(id: "had-updated", updatedDate: nil)],
            for: feed
        )

        let afterRefetch = try service.articles(for: feed)
        #expect(afterRefetch.count == 1)
        #expect(afterRefetch[0].updatedDate == baseline) // not cleared
        #expect(afterRefetch[0].wasUpdated == false)
    }

    @Test("Pre-feature row (existing.updatedDate == nil) compares against publishedDate")
    @MainActor
    func upsertArticlesFallbackToPublishedDateForPreFeatureRow() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feed = TestFixtures.makePersistentFeed()
        try service.addFeed(feed)

        // Simulate an article persisted before the updatedDate column existed:
        // updatedDate is nil but publishedDate is set.
        let publishedDate = Date(timeIntervalSince1970: 1_700_000_000)
        try service.upsertArticles(
            [TestFixtures.makeArticle(
                id: "pre-feature",
                publishedDate: publishedDate,
                updatedDate: nil
            )],
            for: feed
        )

        let beforeRefetch = try service.articles(for: feed)
        #expect(beforeRefetch[0].updatedDate == nil)

        // Re-fetch with an updatedDate strictly newer than the existing publishedDate.
        // The fallback chain should kick in and trigger detection.
        let newerUpdate = publishedDate.addingTimeInterval(3600)
        try service.upsertArticles(
            [TestFixtures.makeArticle(
                id: "pre-feature",
                publishedDate: publishedDate,
                updatedDate: newerUpdate
            )],
            for: feed
        )

        let afterRefetch = try service.articles(for: feed)
        #expect(afterRefetch[0].updatedDate == newerUpdate)
        #expect(afterRefetch[0].wasUpdated == true)
    }

    @Test("Update detection deletes the cached PersistentArticleContent row from the store")
    @MainActor
    func upsertArticlesDropsCachedContentOnUpdate() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feed = TestFixtures.makePersistentFeed()
        try service.addFeed(feed)

        let baseline = Date(timeIntervalSince1970: 1_700_000_000)
        try service.upsertArticles(
            [TestFixtures.makeArticle(id: "with-content", updatedDate: baseline)],
            for: feed
        )

        // Cache extracted content for the article.
        let inserted = try service.articles(for: feed)[0]
        let extracted = TestFixtures.makeArticleContent(
            title: "Extracted Title",
            htmlContent: "<p>Extracted body</p>",
            textContent: "Extracted body"
        )
        try service.cacheContent(extracted, for: inserted)
        try service.save()

        // Pre-condition: cached content is present both via the relationship pointer
        // AND as a row in the underlying store.
        #expect(try service.cachedContent(for: inserted) != nil)
        let contentBefore = try container.mainContext.fetch(FetchDescriptor<PersistentArticleContent>())
        #expect(contentBefore.count == 1)

        // Re-fetch with a strictly newer updatedDate — should drop the cached content.
        try service.upsertArticles(
            [TestFixtures.makeArticle(
                id: "with-content",
                updatedDate: baseline.addingTimeInterval(3600)
            )],
            for: feed
        )
        try service.save()

        let afterRefetch = try service.articles(for: feed)[0]
        #expect(afterRefetch.wasUpdated == true)
        // Relationship pointer cleared on the article side.
        #expect(afterRefetch.content == nil)
        // AND the underlying PersistentArticleContent row is actually gone from the
        // store — not just orphaned. This is what `cachedContent(for:)` couldn't
        // distinguish: that helper just reads the relationship, which would return
        // nil even if the row were leaking. Direct fetch is the only honest check.
        let contentAfter = try container.mainContext.fetch(FetchDescriptor<PersistentArticleContent>())
        #expect(contentAfter.isEmpty)
    }

    @Test("Re-fetch when both existing baselines are nil — skip detection rather than oscillate")
    @MainActor
    func upsertArticlesSkipsWhenBothBaselinesNil() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feed = TestFixtures.makePersistentFeed()
        try service.addFeed(feed)

        // Seed an article with neither publishedDate nor updatedDate — the only way
        // this happens in production is when the parser rejected every date format.
        try service.upsertArticles(
            [TestFixtures.makeArticle(id: "no-baseline", publishedDate: nil, updatedDate: nil)],
            for: feed
        )

        let beforeRefetch = try service.articles(for: feed)
        #expect(beforeRefetch[0].publishedDate == nil)
        #expect(beforeRefetch[0].updatedDate == nil)
        let originalSortDate = beforeRefetch[0].sortDate

        // Re-fetch with an incoming updatedDate. Without a baseline date on the
        // existing row we cannot establish "strictly newer," so detection must be
        // skipped — otherwise the article would oscillate between read and unread
        // forever (the user would never be able to make it stop).
        try service.upsertArticles(
            [TestFixtures.makeArticle(id: "no-baseline", publishedDate: nil, updatedDate: Date())],
            for: feed
        )

        let afterRefetch = try service.articles(for: feed)
        #expect(afterRefetch.count == 1)
        // No mutation: the row's updatedDate stays nil and wasUpdated stays false.
        #expect(afterRefetch[0].updatedDate == nil)
        #expect(afterRefetch[0].wasUpdated == false)
        #expect(afterRefetch[0].sortDate == originalSortDate)
    }

    @Test("upsertArticles handles a mixed insert / update / no-op batch in one call")
    @MainActor
    func upsertArticlesMixedBatch() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feed = TestFixtures.makePersistentFeed()
        try service.addFeed(feed)

        let baseline = Date(timeIntervalSince1970: 1_700_000_000)

        // Seed two existing articles: one will be updated, one will be a no-op.
        try service.upsertArticles(
            [
                TestFixtures.makeArticle(id: "will-update", title: "A", updatedDate: baseline),
                TestFixtures.makeArticle(id: "will-noop",   title: "B", updatedDate: baseline),
            ],
            for: feed
        )

        let seeded = try service.articles(for: feed)
        let willUpdateOriginalSort = seeded.first { $0.articleID == "will-update" }!.sortDate

        // Second call: one new insert, one genuine update, one no-op (same updatedDate).
        // This is the realistic call shape — production passes the entire feed's
        // worth of articles in one call, often mixing all three categories.
        try service.upsertArticles(
            [
                TestFixtures.makeArticle(id: "will-insert", title: "C", updatedDate: baseline),
                TestFixtures.makeArticle(id: "will-update", title: "A", updatedDate: baseline.addingTimeInterval(3600)),
                TestFixtures.makeArticle(id: "will-noop",   title: "B", updatedDate: baseline),
            ],
            for: feed
        )

        let after = try service.articles(for: feed)
        #expect(after.count == 3)

        let inserted = after.first { $0.articleID == "will-insert" }!
        let updated  = after.first { $0.articleID == "will-update" }!
        let noop     = after.first { $0.articleID == "will-noop" }!

        #expect(inserted.wasUpdated == false)
        #expect(updated.wasUpdated == true)
        #expect(updated.sortDate > willUpdateOriginalSort)
        #expect(noop.wasUpdated == false)
    }

    @Test("markArticleRead toggles read status")
    @MainActor
    func markArticleRead() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feed = TestFixtures.makePersistentFeed()
        try service.addFeed(feed)
        try service.upsertArticles([TestFixtures.makeArticle(id: "a1")], for: feed)

        let articles = try service.articles(for: feed)
        #expect(articles[0].isRead == false)

        try service.markArticleRead(articles[0], isRead: true)
        #expect(articles[0].isRead == true)
        #expect(articles[0].readDate != nil)
        // Fresh articles default `wasUpdated` to false; marking read keeps it false.
        #expect(articles[0].wasUpdated == false)

        try service.markArticleRead(articles[0], isRead: false)
        #expect(articles[0].isRead == false)
        #expect(articles[0].readDate == nil)
        #expect(articles[0].wasUpdated == false)
    }

    @Test("markArticleRead clears wasUpdated when transitioning to read (issue #74)")
    @MainActor
    func markArticleReadClearsWasUpdatedOnRead() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feed = TestFixtures.makePersistentFeed()
        try service.addFeed(feed)

        // Drive the upsert update-detection path to set wasUpdated = true:
        // seed an article, then re-fetch with a strictly newer updatedDate.
        let baseline = Date(timeIntervalSince1970: 1_700_000_000)
        try service.upsertArticles(
            [TestFixtures.makeArticle(id: "u1", updatedDate: baseline)],
            for: feed
        )
        try service.upsertArticles(
            [TestFixtures.makeArticle(id: "u1", updatedDate: baseline.addingTimeInterval(3600))],
            for: feed
        )

        let updated = try service.articles(for: feed)[0]
        // Pre-condition: detection set the flag and reset isRead. (Full detection-path
        // mutation coverage lives in the `upsertArticles` test cluster above; here we
        // only need the read-clear pre-conditions to be true.)
        #expect(updated.wasUpdated == true)
        #expect(updated.isRead == false)

        // Acting on the read transition clears the flag.
        try service.markArticleRead(updated, isRead: true)
        #expect(updated.isRead == true)
        #expect(updated.wasUpdated == false)
    }

    @Test("markArticleRead does NOT re-set wasUpdated when transitioning read → unread")
    @MainActor
    func markArticleReadDoesNotReSetWasUpdatedOnUnread() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feed = TestFixtures.makePersistentFeed()
        try service.addFeed(feed)

        // Set up a wasUpdated == true article via the upsert detection path.
        let baseline = Date(timeIntervalSince1970: 1_700_000_000)
        try service.upsertArticles(
            [TestFixtures.makeArticle(id: "u1", updatedDate: baseline)],
            for: feed
        )
        try service.upsertArticles(
            [TestFixtures.makeArticle(id: "u1", updatedDate: baseline.addingTimeInterval(3600))],
            for: feed
        )

        let updated = try service.articles(for: feed)[0]
        // Read it (clears wasUpdated), then mark unread again.
        try service.markArticleRead(updated, isRead: true)
        #expect(updated.wasUpdated == false)

        try service.markArticleRead(updated, isRead: false)
        #expect(updated.isRead == false)
        // Manual mark-unread must NOT lie about the article having been updated —
        // the publisher revision is a fact about the content, not a function of
        // the user's read toggle. Once cleared, wasUpdated stays cleared.
        #expect(updated.wasUpdated == false)
    }

    @Test("markArticleRead(isRead: false) on a wasUpdated article preserves the flag")
    @MainActor
    func markArticleReadFalseOnUpdatedArticlePreservesFlag() throws {
        // Round-trip distinct from `markArticleReadDoesNotReSetWasUpdatedOnUnread`:
        // there, the flag is cleared first via a read, then we verify the unread
        // transition doesn't re-set it. Here, the user *never reads* the article —
        // they directly mark unread (e.g., a swipe gesture or a hypothetical
        // "mark unread" affordance) on a row that is already unread but carries the
        // orange "Updated" badge. The flag must survive: the user never opened the
        // article, so the call-to-action is still valid.
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feed = TestFixtures.makePersistentFeed()
        try service.addFeed(feed)

        let baseline = Date(timeIntervalSince1970: 1_700_000_000)
        try service.upsertArticles(
            [TestFixtures.makeArticle(id: "u1", updatedDate: baseline)],
            for: feed
        )
        try service.upsertArticles(
            [TestFixtures.makeArticle(id: "u1", updatedDate: baseline.addingTimeInterval(3600))],
            for: feed
        )

        let updated = try service.articles(for: feed)[0]
        #expect(updated.wasUpdated == true)
        #expect(updated.isRead == false)

        try service.markArticleRead(updated, isRead: false)
        #expect(updated.isRead == false)
        #expect(updated.wasUpdated == true) // preserved — never read
    }

    @Test("markArticleRead preserves the first-read timestamp on repeated isRead: true calls (issue #271)")
    @MainActor
    func markArticleReadPreservesFirstReadDate() async throws {
        // Pins the issue #271 contract: `readDate` is "the moment the user *first*
        // read the article" — not "the most recent read action." Calling
        // `markArticleRead(_, isRead: true)` twice in a row must NOT bump the
        // timestamp; the second call is a no-op for `readDate`.
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feed = TestFixtures.makePersistentFeed()
        try service.addFeed(feed)
        try service.upsertArticles([TestFixtures.makeArticle(id: "a1")], for: feed)

        let articles = try service.articles(for: feed)
        try service.markArticleRead(articles[0], isRead: true)
        let firstReadDate = try #require(articles[0].readDate)

        // Sleep long enough that a re-stamp would be observable. `Date()` has
        // sub-millisecond resolution on iOS, so 10ms is generous headroom.
        try await Task.sleep(nanoseconds: 10_000_000)

        try service.markArticleRead(articles[0], isRead: true)
        let secondReadDate = try #require(articles[0].readDate)
        #expect(secondReadDate == firstReadDate)
    }

    @Test("markArticleRead stamps a fresh readDate after an unread round-trip (issue #271)")
    @MainActor
    func markArticleReadStampsFreshDateAfterUnreadRoundTrip() async throws {
        // Companion to `markArticleReadPreservesFirstReadDate`: verifies the
        // "round-trip through unread clears the timestamp" half of the contract.
        // If the user explicitly marks the article unread (nulling `readDate`),
        // a subsequent `isRead: true` must stamp a *new* first-read time — the
        // previous read was deliberately undone, so the stored timestamp no
        // longer represents "the moment the user first read the article."
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feed = TestFixtures.makePersistentFeed()
        try service.addFeed(feed)
        try service.upsertArticles([TestFixtures.makeArticle(id: "a1")], for: feed)

        let articles = try service.articles(for: feed)
        try service.markArticleRead(articles[0], isRead: true)
        let firstReadDate = try #require(articles[0].readDate)

        try service.markArticleRead(articles[0], isRead: false)
        #expect(articles[0].readDate == nil)

        try await Task.sleep(nanoseconds: 10_000_000)

        try service.markArticleRead(articles[0], isRead: true)
        let newReadDate = try #require(articles[0].readDate)
        #expect(newReadDate > firstReadDate)
    }

    @Test("markAllArticlesRead(for:) clears wasUpdated for every article in the feed")
    @MainActor
    func markAllArticlesReadForFeedClearsWasUpdated() throws {
        // Pins the issue #74 invariant for the per-feed bulk read path: tapping
        // "Mark all as read" on a feed must dismiss the orange "Updated" badge for
        // every article in that feed, not just the ones the user opens individually.
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feed = TestFixtures.makePersistentFeed()
        try service.addFeed(feed)

        // Drive two articles through the upsert detection path to set wasUpdated.
        let baseline = Date(timeIntervalSince1970: 1_700_000_000)
        try service.upsertArticles(
            [
                TestFixtures.makeArticle(id: "u1", updatedDate: baseline),
                TestFixtures.makeArticle(id: "u2", updatedDate: baseline),
            ],
            for: feed
        )
        try service.upsertArticles(
            [
                TestFixtures.makeArticle(id: "u1", updatedDate: baseline.addingTimeInterval(3600)),
                TestFixtures.makeArticle(id: "u2", updatedDate: baseline.addingTimeInterval(3600)),
            ],
            for: feed
        )

        let beforeBulk = try service.articles(for: feed)
        #expect(beforeBulk.allSatisfy { $0.wasUpdated == true })
        #expect(beforeBulk.allSatisfy { $0.isRead == false })

        try service.markAllArticlesRead(for: feed)

        let afterBulk = try service.articles(for: feed)
        #expect(afterBulk.allSatisfy { $0.isRead == true })
        #expect(afterBulk.allSatisfy { $0.wasUpdated == false })
    }

    @Test("markAllArticlesRead() (global) clears wasUpdated across every feed")
    @MainActor
    func markAllArticlesReadGlobalClearsWasUpdated() throws {
        // Same invariant as the per-feed bulk path, but for the global "Mark all as
        // read" action. Articles across MULTIPLE feeds must all have their badges
        // dismissed in one call.
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feedA = TestFixtures.makePersistentFeed(title: "Feed A")
        let feedB = TestFixtures.makePersistentFeed(title: "Feed B")
        try service.addFeed(feedA)
        try service.addFeed(feedB)

        let baseline = Date(timeIntervalSince1970: 1_700_000_000)
        try service.upsertArticles(
            [TestFixtures.makeArticle(id: "a1", updatedDate: baseline)],
            for: feedA
        )
        try service.upsertArticles(
            [TestFixtures.makeArticle(id: "a1", updatedDate: baseline.addingTimeInterval(3600))],
            for: feedA
        )
        try service.upsertArticles(
            [TestFixtures.makeArticle(id: "b1", updatedDate: baseline)],
            for: feedB
        )
        try service.upsertArticles(
            [TestFixtures.makeArticle(id: "b1", updatedDate: baseline.addingTimeInterval(3600))],
            for: feedB
        )

        // Pre-condition: both articles carry the flag.
        let aBefore = try service.articles(for: feedA)
        let bBefore = try service.articles(for: feedB)
        #expect(aBefore[0].wasUpdated == true)
        #expect(bBefore[0].wasUpdated == true)

        try service.markAllArticlesRead()

        let aAfter = try service.articles(for: feedA)
        let bAfter = try service.articles(for: feedB)
        #expect(aAfter[0].isRead == true)
        #expect(aAfter[0].wasUpdated == false)
        #expect(bAfter[0].isRead == true)
        #expect(bAfter[0].wasUpdated == false)
    }

    @Test("markAllArticlesRead(for:) preserves the first-read timestamp on already-read articles (issue #271)")
    @MainActor
    func markAllArticlesReadForFeedPreservesFirstReadDate() async throws {
        // Pins the predicate-based safety documented in `PersistentArticle.readDate`:
        // the `!$0.isRead` fetch predicate in `markAllArticlesRead(for:)` must never
        // touch articles whose `readDate` is already set. A future refactor that drops
        // the predicate would silently overwrite first-read timestamps on already-read
        // articles — this test would catch that regression immediately.
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feed = TestFixtures.makePersistentFeed()
        try service.addFeed(feed)
        try service.upsertArticles(
            [
                TestFixtures.makeArticle(id: "already-read"),
                TestFixtures.makeArticle(id: "still-unread"),
            ],
            for: feed
        )

        let articles = try service.articles(for: feed)
        let alreadyRead = try #require(articles.first { $0.articleID == "already-read" })
        try service.markArticleRead(alreadyRead, isRead: true)
        let originalReadDate = try #require(alreadyRead.readDate)

        // Sleep long enough that a re-stamp would be observable. `Date()` has
        // sub-millisecond resolution on iOS, so 10ms is generous headroom.
        try await Task.sleep(nanoseconds: 10_000_000)

        try service.markAllArticlesRead(for: feed)

        // Already-read article: readDate must be unchanged (predicate excluded it).
        #expect(alreadyRead.readDate == originalReadDate)

        // Previously-unread sibling: must now have a fresh stamp after originalReadDate.
        let stillUnread = try #require(try service.articles(for: feed).first { $0.articleID == "still-unread" })
        let freshStamp = try #require(stillUnread.readDate)
        #expect(freshStamp > originalReadDate)
    }

    @Test("markAllArticlesRead() (global) preserves the first-read timestamp on already-read articles (issue #271)")
    @MainActor
    func markAllArticlesReadGlobalPreservesFirstReadDate() async throws {
        // Same contract as the per-feed variant: the global `!$0.isRead` predicate
        // must exclude already-read articles so their first-read timestamps survive
        // the bulk operation.
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feed = TestFixtures.makePersistentFeed()
        try service.addFeed(feed)
        try service.upsertArticles(
            [
                TestFixtures.makeArticle(id: "already-read"),
                TestFixtures.makeArticle(id: "still-unread"),
            ],
            for: feed
        )

        let articles = try service.articles(for: feed)
        let alreadyRead = try #require(articles.first { $0.articleID == "already-read" })
        try service.markArticleRead(alreadyRead, isRead: true)
        let originalReadDate = try #require(alreadyRead.readDate)

        // Sleep long enough that a re-stamp would be observable.
        try await Task.sleep(nanoseconds: 10_000_000)

        try service.markAllArticlesRead()

        // Already-read article: readDate must be unchanged (predicate excluded it).
        #expect(alreadyRead.readDate == originalReadDate)

        // Previously-unread sibling: must now have a fresh stamp after originalReadDate.
        let stillUnread = try #require(try service.articles(for: feed).first { $0.articleID == "still-unread" })
        let freshStamp = try #require(stillUnread.readDate)
        #expect(freshStamp > originalReadDate)
    }

    @Test("unreadCount returns correct count")
    @MainActor
    func unreadCountCorrect() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feed = TestFixtures.makePersistentFeed()
        try service.addFeed(feed)

        let articles = [
            TestFixtures.makeArticle(id: "a1"),
            TestFixtures.makeArticle(id: "a2"),
            TestFixtures.makeArticle(id: "a3"),
        ]
        try service.upsertArticles(articles, for: feed)

        #expect(try service.unreadCount(for: feed) == 3)

        let persisted = try service.articles(for: feed)
        try service.markArticleRead(persisted[0], isRead: true)

        #expect(try service.unreadCount(for: feed) == 2)
    }

    // MARK: - Cross-Feed Article Queries

    @Test("allArticles returns articles from all feeds sorted by date descending")
    @MainActor
    func allArticlesAcrossFeeds() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feed1 = TestFixtures.makePersistentFeed(title: "Feed 1", feedURL: URL(string: "https://one.com/feed")!)
        let feed2 = TestFixtures.makePersistentFeed(title: "Feed 2", feedURL: URL(string: "https://two.com/feed")!)
        try service.addFeed(feed1)
        try service.addFeed(feed2)

        try service.upsertArticles([
            TestFixtures.makeArticle(id: "a1", publishedDate: Date(timeIntervalSince1970: 1_000_000)),
        ], for: feed1)
        try service.upsertArticles([
            TestFixtures.makeArticle(id: "a2", publishedDate: Date(timeIntervalSince1970: 2_000_000)),
        ], for: feed2)
        try service.save()

        let all = try service.allArticles()
        #expect(all.count == 2)
        #expect(all[0].articleID == "a2")
        #expect(all[1].articleID == "a1")
    }

    @Test("allUnreadArticles returns only unread articles across feeds")
    @MainActor
    func allUnreadArticlesFilters() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feed = TestFixtures.makePersistentFeed()
        try service.addFeed(feed)

        try service.upsertArticles([
            TestFixtures.makeArticle(id: "a1", publishedDate: Date(timeIntervalSince1970: 2_000_000)),
            TestFixtures.makeArticle(id: "a2", publishedDate: Date(timeIntervalSince1970: 1_000_000)),
        ], for: feed)
        try service.save()

        // articles(for:) sorts by publishedDate descending, so a1 is first
        let articles = try service.articles(for: feed)
        #expect(articles[0].articleID == "a1")
        try service.markArticleRead(articles[0], isRead: true)

        let unread = try service.allUnreadArticles()
        #expect(unread.count == 1)
        #expect(unread[0].articleID == "a2")
    }

    @Test("totalUnreadCount returns sum across all feeds")
    @MainActor
    func totalUnreadCountAcrossFeeds() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feed1 = TestFixtures.makePersistentFeed(title: "Feed 1", feedURL: URL(string: "https://one.com/feed")!)
        let feed2 = TestFixtures.makePersistentFeed(title: "Feed 2", feedURL: URL(string: "https://two.com/feed")!)
        try service.addFeed(feed1)
        try service.addFeed(feed2)

        try service.upsertArticles([
            TestFixtures.makeArticle(id: "a1"),
            TestFixtures.makeArticle(id: "a2"),
        ], for: feed1)
        try service.upsertArticles([
            TestFixtures.makeArticle(id: "a3"),
        ], for: feed2)
        try service.save()

        #expect(try service.totalUnreadCount() == 3)

        let articles = try service.articles(for: feed1)
        try service.markArticleRead(articles[0], isRead: true)

        #expect(try service.totalUnreadCount() == 2)
    }

    // MARK: - Paginated Article Queries

    @Test("allArticles(offset:limit:) returns correct page")
    @MainActor
    func allArticlesPaginated() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feed = TestFixtures.makePersistentFeed()
        try service.addFeed(feed)

        // Insert 5 articles with distinct dates
        for i in 0..<5 {
            try service.upsertArticles([
                TestFixtures.makeArticle(
                    id: "a\(i)",
                    publishedDate: Date(timeIntervalSince1970: Double(i) * 1_000_000)
                ),
            ], for: feed)
        }
        try service.save()

        // First page: offset 0, limit 2 (should get newest two: a4, a3)
        let page1 = try service.allArticles(offset: 0, limit: 2)
        #expect(page1.count == 2)
        #expect(page1[0].articleID == "a4")
        #expect(page1[1].articleID == "a3")

        // Second page: offset 2, limit 2 (should get a2, a1)
        let page2 = try service.allArticles(offset: 2, limit: 2)
        #expect(page2.count == 2)
        #expect(page2[0].articleID == "a2")
        #expect(page2[1].articleID == "a1")

        // Third page: offset 4, limit 2 (should get a0 only)
        let page3 = try service.allArticles(offset: 4, limit: 2)
        #expect(page3.count == 1)
        #expect(page3[0].articleID == "a0")
    }

    @Test("allUnreadArticles(offset:limit:) returns correct page of unread articles")
    @MainActor
    func allUnreadArticlesPaginated() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feed = TestFixtures.makePersistentFeed()
        try service.addFeed(feed)

        for i in 0..<4 {
            try service.upsertArticles([
                TestFixtures.makeArticle(
                    id: "a\(i)",
                    publishedDate: Date(timeIntervalSince1970: Double(i) * 1_000_000)
                ),
            ], for: feed)
        }
        try service.save()

        // Mark a3 (newest) as read
        let articles = try service.articles(for: feed)
        let newestArticle = articles.first { $0.articleID == "a3" }!
        try service.markArticleRead(newestArticle, isRead: true)

        // Page 1: offset 0, limit 2 — should skip a3 (read) and return a2, a1
        let page1 = try service.allUnreadArticles(offset: 0, limit: 2)
        #expect(page1.count == 2)
        #expect(page1[0].articleID == "a2")
        #expect(page1[1].articleID == "a1")

        // Page 2: offset 2, limit 2 — should return a0 only
        let page2 = try service.allUnreadArticles(offset: 2, limit: 2)
        #expect(page2.count == 1)
        #expect(page2[0].articleID == "a0")
    }

    @Test("articles(for:offset:limit:) returns correct page for a specific feed")
    @MainActor
    func articlesForFeedPaginated() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feed = TestFixtures.makePersistentFeed()
        try service.addFeed(feed)

        for i in 0..<3 {
            try service.upsertArticles([
                TestFixtures.makeArticle(
                    id: "a\(i)",
                    publishedDate: Date(timeIntervalSince1970: Double(i) * 1_000_000)
                ),
            ], for: feed)
        }
        try service.save()

        let page1 = try service.articles(for: feed, offset: 0, limit: 2)
        #expect(page1.count == 2)
        #expect(page1[0].articleID == "a2")

        let page2 = try service.articles(for: feed, offset: 2, limit: 2)
        #expect(page2.count == 1)
        #expect(page2[0].articleID == "a0")
    }

    @Test("paginated query with offset beyond data returns empty")
    @MainActor
    func paginatedOffsetBeyondData() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feed = TestFixtures.makePersistentFeed()
        try service.addFeed(feed)

        try service.upsertArticles([
            TestFixtures.makeArticle(id: "a1"),
        ], for: feed)
        try service.save()

        let page = try service.allArticles(offset: 10, limit: 5)
        #expect(page.isEmpty)
    }

    // MARK: - Content Cache

    @Test("cacheContent stores and retrieves article content")
    @MainActor
    func cacheContentRoundtrip() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feed = TestFixtures.makePersistentFeed()
        try service.addFeed(feed)
        try service.upsertArticles([TestFixtures.makeArticle(id: "a1")], for: feed)

        let articles = try service.articles(for: feed)
        let content = TestFixtures.makeArticleContent(title: "Extracted", htmlContent: "<p>Full</p>")

        try service.cacheContent(content, for: articles[0])

        let cached = try service.cachedContent(for: articles[0])
        #expect(cached != nil)
        #expect(cached?.title == "Extracted")
        #expect(cached?.htmlContent == "<p>Full</p>")
    }

    @Test("cacheContent updates existing content")
    @MainActor
    func cacheContentUpdates() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feed = TestFixtures.makePersistentFeed()
        try service.addFeed(feed)
        try service.upsertArticles([TestFixtures.makeArticle(id: "a1")], for: feed)

        let articles = try service.articles(for: feed)

        let content1 = TestFixtures.makeArticleContent(title: "First")
        try service.cacheContent(content1, for: articles[0])

        let content2 = TestFixtures.makeArticleContent(title: "Updated")
        try service.cacheContent(content2, for: articles[0])

        let cached = try service.cachedContent(for: articles[0])
        #expect(cached?.title == "Updated")
    }

    @Test("cachedContent returns nil when no content cached")
    @MainActor
    func cachedContentNil() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feed = TestFixtures.makePersistentFeed()
        try service.addFeed(feed)
        try service.upsertArticles([TestFixtures.makeArticle(id: "a1")], for: feed)

        let articles = try service.articles(for: feed)
        #expect(try service.cachedContent(for: articles[0]) == nil)
    }

    @Test("deleting feed cascades to articles and content")
    @MainActor
    func deleteFeedCascades() throws {
        let (service, container) = try makeService()
        let feed = TestFixtures.makePersistentFeed()
        try service.addFeed(feed)
        try service.upsertArticles([TestFixtures.makeArticle(id: "a1")], for: feed)

        let articles = try service.articles(for: feed)
        try service.cacheContent(TestFixtures.makeArticleContent(), for: articles[0])

        try service.deleteFeed(feed)

        let articleDescriptor = FetchDescriptor<PersistentArticle>()
        let contentDescriptor = FetchDescriptor<PersistentArticleContent>()
        #expect(try container.mainContext.fetchCount(articleDescriptor) == 0)
        #expect(try container.mainContext.fetchCount(contentDescriptor) == 0)
    }

    // MARK: - Thumbnail Tracking

    @Test("articlesNeedingThumbnails returns uncached articles under retry cap")
    @MainActor
    func articlesNeedingThumbnailsReturnsUncached() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feed = TestFixtures.makePersistentFeed()
        try service.addFeed(feed)
        try service.upsertArticles([
            TestFixtures.makeArticle(id: "uncached"),
            TestFixtures.makeArticle(id: "cached"),
        ], for: feed)

        let articles = try service.articles(for: feed)
        let cachedArticle = articles.first { $0.articleID == "cached" }!
        try service.markThumbnailCached(cachedArticle)
        try service.save()

        let needing = try service.articlesNeedingThumbnails(maxRetryCount: 3)
        #expect(needing.count == 1)
        #expect(needing[0].articleID == "uncached")
    }

    @Test("articlesNeedingThumbnails excludes articles at retry cap")
    @MainActor
    func articlesNeedingThumbnailsExcludesAtCap() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feed = TestFixtures.makePersistentFeed()
        try service.addFeed(feed)
        try service.upsertArticles([TestFixtures.makeArticle(id: "maxed")], for: feed)

        let articles = try service.articles(for: feed)
        let article = articles[0]
        for _ in 0..<3 {
            try service.incrementThumbnailRetryCount(article)
        }
        try service.save()

        let needing = try service.articlesNeedingThumbnails(maxRetryCount: 3)
        #expect(needing.isEmpty)
    }

    @Test("articlesNeedingThumbnails returns articles in sortDate descending (newest first)")
    @MainActor
    func articlesNeedingThumbnailsSortsBySortDateDescending() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feed = TestFixtures.makePersistentFeed()
        try service.addFeed(feed)

        // Insert two uncached articles: one with a past pubDate, one with a future
        // pubDate. Without the sortDate migration, the future article would come first
        // by an inflated future timestamp; with sortDate clamping, both have sortDate
        // ≈ now, but the past article (sortDate = now - 1h) comes after.
        try service.upsertArticles([
            TestFixtures.makeArticle(id: "future", publishedDate: Date().addingTimeInterval(4 * 60 * 60)),
            TestFixtures.makeArticle(id: "past", publishedDate: Date().addingTimeInterval(-3600)),
        ], for: feed)
        try service.save()

        let needing = try service.articlesNeedingThumbnails(maxRetryCount: 3)
        #expect(needing.count == 2)
        // Newest-first by sortDate: future is clamped to ~now, past is -1h.
        #expect(needing[0].articleID == "future")
        #expect(needing[1].articleID == "past")
        // The clamped future article must NOT be sorted by its raw publishedDate;
        // its sortDate is bounded by the past article's sortDate plus a small window.
        #expect(needing[0].sortDate >= needing[1].sortDate)
    }

    @Test("markThumbnailCached sets isThumbnailCached to true")
    @MainActor
    func markThumbnailCachedSetsFlag() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feed = TestFixtures.makePersistentFeed()
        try service.addFeed(feed)
        try service.upsertArticles([TestFixtures.makeArticle(id: "a1")], for: feed)

        let articles = try service.articles(for: feed)
        #expect(articles[0].isThumbnailCached == false)

        try service.markThumbnailCached(articles[0])
        try service.save()

        #expect(articles[0].isThumbnailCached == true)
    }

    @Test("incrementThumbnailRetryCount increases count by one")
    @MainActor
    func incrementThumbnailRetryCountIncreases() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feed = TestFixtures.makePersistentFeed()
        try service.addFeed(feed)
        try service.upsertArticles([TestFixtures.makeArticle(id: "a1")], for: feed)

        let articles = try service.articles(for: feed)
        #expect(articles[0].thumbnailRetryCount == 0)

        try service.incrementThumbnailRetryCount(articles[0])
        try service.save()

        #expect(articles[0].thumbnailRetryCount == 1)

        try service.incrementThumbnailRetryCount(articles[0])
        try service.save()

        #expect(articles[0].thumbnailRetryCount == 2)
    }

    // MARK: - Sort Order

    @Test("articles(for:offset:limit:ascending:true) returns oldest first")
    @MainActor
    func articlesForFeedAscending() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feed = TestFixtures.makePersistentFeed()
        try service.addFeed(feed)

        for i in 0..<3 {
            try service.upsertArticles([
                TestFixtures.makeArticle(
                    id: "a\(i)",
                    publishedDate: Date(timeIntervalSince1970: Double(i) * 1_000_000)
                ),
            ], for: feed)
        }
        try service.save()

        let ascending = try service.articles(for: feed, offset: 0, limit: 10, ascending: true)
        #expect(ascending[0].articleID == "a0")
        #expect(ascending[2].articleID == "a2")

        let descending = try service.articles(for: feed, offset: 0, limit: 10, ascending: false)
        #expect(descending[0].articleID == "a2")
        #expect(descending[2].articleID == "a0")
    }

    @Test("allArticles(offset:limit:ascending:true) returns oldest first")
    @MainActor
    func allArticlesAscending() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feed = TestFixtures.makePersistentFeed()
        try service.addFeed(feed)

        for i in 0..<3 {
            try service.upsertArticles([
                TestFixtures.makeArticle(
                    id: "a\(i)",
                    publishedDate: Date(timeIntervalSince1970: Double(i) * 1_000_000)
                ),
            ], for: feed)
        }
        try service.save()

        let ascending = try service.allArticles(offset: 0, limit: 10, ascending: true)
        #expect(ascending[0].articleID == "a0")
        #expect(ascending[2].articleID == "a2")
    }

    @Test("allUnreadArticles(offset:limit:ascending:true) returns oldest first")
    @MainActor
    func allUnreadArticlesAscending() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feed = TestFixtures.makePersistentFeed()
        try service.addFeed(feed)

        for i in 0..<3 {
            try service.upsertArticles([
                TestFixtures.makeArticle(
                    id: "a\(i)",
                    publishedDate: Date(timeIntervalSince1970: Double(i) * 1_000_000)
                ),
            ], for: feed)
        }
        try service.save()

        let ascending = try service.allUnreadArticles(offset: 0, limit: 10, ascending: true)
        #expect(ascending[0].articleID == "a0")
        #expect(ascending[2].articleID == "a2")
    }

    // MARK: - Unread Articles For Feed

    @Test("unreadArticles(for:offset:limit:ascending:) returns only unread articles for feed")
    @MainActor
    func unreadArticlesForFeed() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feed = TestFixtures.makePersistentFeed()
        try service.addFeed(feed)

        for i in 0..<3 {
            try service.upsertArticles([
                TestFixtures.makeArticle(
                    id: "a\(i)",
                    publishedDate: Date(timeIntervalSince1970: Double(i) * 1_000_000)
                ),
            ], for: feed)
        }
        try service.save()

        // Mark one as read
        let allArticles = try service.articles(for: feed)
        let middle = allArticles.first { $0.articleID == "a1" }!
        try service.markArticleRead(middle, isRead: true)

        let unread = try service.unreadArticles(for: feed, offset: 0, limit: 10, ascending: true)
        #expect(unread.count == 2)
        #expect(unread[0].articleID == "a0")
        #expect(unread[1].articleID == "a2")
    }

    // MARK: - Mark All Articles Read

    @Test("markAllArticlesRead(for:) marks all articles in feed as read")
    @MainActor
    func markAllArticlesReadForFeed() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feed1 = TestFixtures.makePersistentFeed(title: "Feed 1")
        let feed2 = TestFixtures.makePersistentFeed(title: "Feed 2")
        try service.addFeed(feed1)
        try service.addFeed(feed2)

        try service.upsertArticles([
            TestFixtures.makeArticle(id: "f1-a1"),
            TestFixtures.makeArticle(id: "f1-a2"),
        ], for: feed1)
        try service.upsertArticles([
            TestFixtures.makeArticle(id: "f2-a1"),
        ], for: feed2)
        try service.save()

        try service.markAllArticlesRead(for: feed1)

        let feed1Articles = try service.articles(for: feed1)
        let feed1AllRead = feed1Articles.allSatisfy(\.isRead)
        let feed1AllHaveReadDate = feed1Articles.allSatisfy { $0.readDate != nil }
        #expect(feed1AllRead)
        #expect(feed1AllHaveReadDate)

        // Feed 2 articles should be unaffected
        let feed2Articles = try service.articles(for: feed2)
        let feed2AllUnread = feed2Articles.allSatisfy { !$0.isRead }
        #expect(feed2AllUnread)
    }

    @Test("markAllSavedArticlesRead marks only saved articles and leaves non-saved unread")
    @MainActor
    func markAllSavedArticlesReadScoped() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feed = TestFixtures.makePersistentFeed()
        try service.addFeed(feed)
        try service.upsertArticles([
            TestFixtures.makeArticle(id: "saved"),
            TestFixtures.makeArticle(id: "unsaved"),
        ], for: feed)
        try service.save()

        // Save one, leave the other untouched. Both are unread at this point.
        let articles = try service.articles(for: feed)
        let saved = try #require(articles.first { $0.articleID == "saved" })
        try service.toggleArticleSaved(saved)
        try service.save()

        try service.markAllSavedArticlesRead()

        let after = try service.articles(for: feed)
        let savedAfter = try #require(after.first { $0.articleID == "saved" })
        let unsavedAfter = try #require(after.first { $0.articleID == "unsaved" })

        // Saved article is now read.
        #expect(savedAfter.isRead == true)
        #expect(savedAfter.readDate != nil)

        // Non-saved article is untouched — the old global path marked it,
        // which was the exact bug we are fixing.
        #expect(unsavedAfter.isRead == false)
        #expect(unsavedAfter.readDate == nil)

        // Unread count reflects the scoped mutation.
        #expect(try service.totalUnreadCount() == 1)
    }

    @Test("markAllArticlesRead() marks all articles across all feeds as read")
    @MainActor
    func markAllArticlesReadGlobal() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feed1 = TestFixtures.makePersistentFeed(title: "Feed 1")
        let feed2 = TestFixtures.makePersistentFeed(title: "Feed 2")
        try service.addFeed(feed1)
        try service.addFeed(feed2)

        try service.upsertArticles([
            TestFixtures.makeArticle(id: "f1-a1"),
        ], for: feed1)
        try service.upsertArticles([
            TestFixtures.makeArticle(id: "f2-a1"),
        ], for: feed2)
        try service.save()

        try service.markAllArticlesRead()

        let all = try service.allArticles()
        let allRead = all.allSatisfy(\.isRead)
        let allHaveReadDate = all.allSatisfy { $0.readDate != nil }
        #expect(allRead)
        #expect(allHaveReadDate)
        #expect(try service.totalUnreadCount() == 0)
    }

    @Test("markAllArticlesRead(for:) is no-op when all articles already read")
    @MainActor
    func markAllArticlesReadForFeedNoOp() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feed = TestFixtures.makePersistentFeed()
        try service.addFeed(feed)

        try service.upsertArticles([TestFixtures.makeArticle(id: "a1")], for: feed)
        try service.save()

        let articles = try service.articles(for: feed)
        try service.markArticleRead(articles[0], isRead: true)

        // Should not throw
        try service.markAllArticlesRead(for: feed)
        #expect(try service.unreadCount(for: feed) == 0)
    }

    // MARK: - Article Cleanup

    @Test("totalArticleCount returns zero initially")
    @MainActor
    func totalArticleCountEmpty() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        #expect(try service.totalArticleCount() == 0)
    }

    @Test("totalArticleCount returns correct count across feeds")
    @MainActor
    func totalArticleCountAcrossFeeds() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feed1 = TestFixtures.makePersistentFeed(title: "Feed 1")
        let feed2 = TestFixtures.makePersistentFeed(title: "Feed 2")
        try service.addFeed(feed1)
        try service.addFeed(feed2)

        try service.upsertArticles([
            TestFixtures.makeArticle(id: "f1-a1"),
            TestFixtures.makeArticle(id: "f1-a2"),
        ], for: feed1)
        try service.upsertArticles([
            TestFixtures.makeArticle(id: "f2-a1"),
        ], for: feed2)
        try service.save()

        #expect(try service.totalArticleCount() == 3)
    }

    @Test("oldestArticleIDsExceedingLimit returns empty when within limit")
    @MainActor
    func oldestArticleIDsWithinLimit() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feed = TestFixtures.makePersistentFeed()
        try service.addFeed(feed)

        try service.upsertArticles([
            TestFixtures.makeArticle(id: "a1", publishedDate: Date(timeIntervalSince1970: 1000)),
            TestFixtures.makeArticle(id: "a2", publishedDate: Date(timeIntervalSince1970: 2000)),
        ], for: feed)
        try service.save()

        let result = try service.oldestArticleIDsExceedingLimit(10)
        #expect(result.isEmpty)
    }

    @Test("oldestArticleIDsExceedingLimit returns oldest articles exceeding limit")
    @MainActor
    func oldestArticleIDsExceedingLimit() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feed = TestFixtures.makePersistentFeed()
        try service.addFeed(feed)

        try service.upsertArticles([
            TestFixtures.makeArticle(id: "oldest", publishedDate: Date(timeIntervalSince1970: 1000)),
            TestFixtures.makeArticle(id: "middle", publishedDate: Date(timeIntervalSince1970: 2000)),
            TestFixtures.makeArticle(id: "newest", publishedDate: Date(timeIntervalSince1970: 3000)),
        ], for: feed)
        try service.save()

        let result = try service.oldestArticleIDsExceedingLimit(1)
        #expect(result.count == 2)
        let ids = Set(result.map(\.articleID))
        #expect(ids.contains("oldest"))
        #expect(ids.contains("middle"))
    }

    @Test("oldestArticleIDsExceedingLimit includes isThumbnailCached flag")
    @MainActor
    func oldestArticleIDsIncludesThumbnailFlag() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feed = TestFixtures.makePersistentFeed()
        try service.addFeed(feed)

        try service.upsertArticles([
            TestFixtures.makeArticle(id: "cached-old", publishedDate: Date(timeIntervalSince1970: 1000)),
            TestFixtures.makeArticle(id: "uncached-old", publishedDate: Date(timeIntervalSince1970: 2000)),
            TestFixtures.makeArticle(id: "newest", publishedDate: Date(timeIntervalSince1970: 3000)),
        ], for: feed)

        let articles = try service.articles(for: feed)
        let cachedArticle = articles.first { $0.articleID == "cached-old" }!
        try service.markThumbnailCached(cachedArticle)
        try service.save()

        let result = try service.oldestArticleIDsExceedingLimit(1)
        let cachedResult = result.first { $0.articleID == "cached-old" }
        let uncachedResult = result.first { $0.articleID == "uncached-old" }
        #expect(cachedResult?.isThumbnailCached == true)
        #expect(uncachedResult?.isThumbnailCached == false)
    }

    @Test("deleteArticles removes specified articles")
    @MainActor
    func deleteArticlesByID() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feed = TestFixtures.makePersistentFeed()
        try service.addFeed(feed)

        try service.upsertArticles([
            TestFixtures.makeArticle(id: "keep"),
            TestFixtures.makeArticle(id: "delete-1"),
            TestFixtures.makeArticle(id: "delete-2"),
        ], for: feed)
        try service.save()

        try service.deleteArticles(withIDs: ["delete-1", "delete-2"])

        let remaining = try service.articles(for: feed)
        #expect(remaining.count == 1)
        #expect(remaining[0].articleID == "keep")
    }

    @Test("deleteArticles cascade-deletes associated content")
    @MainActor
    func deleteArticlesCascadesContent() throws {
        let (service, container) = try makeService()
        let feed = TestFixtures.makePersistentFeed()
        try service.addFeed(feed)

        try service.upsertArticles([
            TestFixtures.makeArticle(id: "with-content"),
        ], for: feed)
        let articles = try service.articles(for: feed)
        try service.cacheContent(TestFixtures.makeArticleContent(), for: articles[0])

        try service.deleteArticles(withIDs: ["with-content"])

        let contentDescriptor = FetchDescriptor<PersistentArticleContent>()
        #expect(try container.mainContext.fetchCount(contentDescriptor) == 0)
    }

    @Test("deleteArticles with empty set is no-op")
    @MainActor
    func deleteArticlesEmptySet() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feed = TestFixtures.makePersistentFeed()
        try service.addFeed(feed)

        try service.upsertArticles([
            TestFixtures.makeArticle(id: "a1"),
        ], for: feed)
        try service.save()

        try service.deleteArticles(withIDs: [])

        #expect(try service.totalArticleCount() == 1)
    }

    @Test("deleteArticles handles count exceeding batch size")
    @MainActor
    func deleteArticlesBatched() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feed = TestFixtures.makePersistentFeed()
        try service.addFeed(feed)

        // Create 600 articles to delete + 5 to keep (exceeds the 500 batch size)
        let deleteCount = 600
        let keepCount = 5
        var articles: [Article] = []
        for i in 0..<deleteCount {
            articles.append(TestFixtures.makeArticle(id: "delete-\(i)"))
        }
        for i in 0..<keepCount {
            articles.append(TestFixtures.makeArticle(id: "keep-\(i)"))
        }
        try service.upsertArticles(articles, for: feed)
        try service.save()

        let deleteIDs = Set((0..<deleteCount).map { "delete-\($0)" })
        try service.deleteArticles(withIDs: deleteIDs)

        let remaining = try service.articles(for: feed)
        #expect(remaining.count == keepCount)
        for i in 0..<keepCount {
            #expect(remaining.contains { $0.articleID == "keep-\(i)" })
        }
    }

    // MARK: - Saved Article Operations

    @Test("toggleArticleSaved saves an unsaved article")
    @MainActor
    func toggleArticleSavedSaves() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feed = TestFixtures.makePersistentFeed()
        try service.addFeed(feed)
        try service.upsertArticles([TestFixtures.makeArticle(id: "a1")], for: feed)
        try service.save()

        let articles = try service.articles(for: feed)
        let article = articles[0]
        #expect(!article.isSaved)
        #expect(article.savedDate == nil)

        try service.toggleArticleSaved(article)

        #expect(article.isSaved)
        #expect(article.savedDate != nil)
    }

    @Test("toggleArticleSaved unsaves a saved article")
    @MainActor
    func toggleArticleSavedUnsaves() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feed = TestFixtures.makePersistentFeed()
        try service.addFeed(feed)
        try service.upsertArticles([TestFixtures.makeArticle(id: "a1")], for: feed)
        try service.save()

        let articles = try service.articles(for: feed)
        let article = articles[0]
        try service.toggleArticleSaved(article)
        #expect(article.isSaved)

        try service.toggleArticleSaved(article)
        #expect(!article.isSaved)
        #expect(article.savedDate == nil)
    }

    @Test("allSavedArticles returns only saved articles sorted by sortDate descending by default")
    @MainActor
    func allSavedArticlesSortedBySortDateDescending() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feed = TestFixtures.makePersistentFeed()
        try service.addFeed(feed)
        // Distinct publish dates so the sortDate ordering is deterministic and
        // does not collapse to the articleID tiebreaker. The saved order is
        // intentionally the REVERSE of the publish order — a1 is saved last,
        // a3 first — to confirm the result is ordered by sortDate, not by
        // savedDate.
        try service.upsertArticles([
            TestFixtures.makeArticle(id: "a1", publishedDate: Date(timeIntervalSince1970: 3_000)),
            TestFixtures.makeArticle(id: "a2", publishedDate: Date(timeIntervalSince1970: 2_000)),
            TestFixtures.makeArticle(id: "a3", publishedDate: Date(timeIntervalSince1970: 1_000)),
        ], for: feed)
        try service.save()

        let articles = try service.articles(for: feed)
        let a1 = articles.first { $0.articleID == "a1" }!
        let a3 = articles.first { $0.articleID == "a3" }!
        try service.toggleArticleSaved(a3) // saved first
        try service.toggleArticleSaved(a1) // saved last

        let saved = try service.allSavedArticles(offset: 0, limit: 10, ascending: false)
        #expect(saved.count == 2)
        #expect(saved[0].articleID == "a1") // newest publishedDate, despite saved last
        #expect(saved[1].articleID == "a3") // oldest publishedDate, despite saved first
    }

    @Test("allSavedArticles honors ascending: true for oldest-first ordering")
    @MainActor
    func allSavedArticlesSortedBySortDateAscending() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feed = TestFixtures.makePersistentFeed()
        try service.addFeed(feed)
        try service.upsertArticles([
            TestFixtures.makeArticle(id: "a1", publishedDate: Date(timeIntervalSince1970: 3_000)),
            TestFixtures.makeArticle(id: "a2", publishedDate: Date(timeIntervalSince1970: 2_000)),
            TestFixtures.makeArticle(id: "a3", publishedDate: Date(timeIntervalSince1970: 1_000)),
        ], for: feed)
        try service.save()

        let articles = try service.articles(for: feed)
        for article in articles where article.articleID != "a2" {
            try service.toggleArticleSaved(article)
        }

        let saved = try service.allSavedArticles(offset: 0, limit: 10, ascending: true)
        #expect(saved.count == 2)
        #expect(saved[0].articleID == "a3") // oldest first
        #expect(saved[1].articleID == "a1")
    }

    @Test("allSavedArticles respects offset and limit")
    @MainActor
    func allSavedArticlesPagination() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feed = TestFixtures.makePersistentFeed()
        try service.addFeed(feed)
        try service.upsertArticles([
            TestFixtures.makeArticle(id: "a1", publishedDate: Date(timeIntervalSince1970: 2_000)),
            TestFixtures.makeArticle(id: "a2", publishedDate: Date(timeIntervalSince1970: 1_000)),
        ], for: feed)
        try service.save()

        let articles = try service.articles(for: feed)
        for article in articles {
            try service.toggleArticleSaved(article)
        }

        let page = try service.allSavedArticles(offset: 1, limit: 1, ascending: false)
        #expect(page.count == 1)
    }

    @Test("savedCount returns count of saved articles")
    @MainActor
    func savedCountReturnsCorrectCount() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feed = TestFixtures.makePersistentFeed()
        try service.addFeed(feed)
        try service.upsertArticles([
            TestFixtures.makeArticle(id: "a1"),
            TestFixtures.makeArticle(id: "a2"),
            TestFixtures.makeArticle(id: "a3"),
        ], for: feed)
        try service.save()

        #expect(try service.savedCount() == 0)

        let articles = try service.articles(for: feed)
        try service.toggleArticleSaved(articles[0])
        try service.toggleArticleSaved(articles[1])

        #expect(try service.savedCount() == 2)
    }

    @Test("savedCount decreases after unsaving an article")
    @MainActor
    func savedCountDecrementsAfterUnsave() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feed = TestFixtures.makePersistentFeed()
        try service.addFeed(feed)
        try service.upsertArticles([
            TestFixtures.makeArticle(id: "a1"),
            TestFixtures.makeArticle(id: "a2"),
        ], for: feed)
        try service.save()

        let articles = try service.articles(for: feed)
        try service.toggleArticleSaved(articles[0])
        try service.toggleArticleSaved(articles[1])
        #expect(try service.savedCount() == 2)

        // Unsave one article
        try service.toggleArticleSaved(articles[0])
        #expect(try service.savedCount() == 1)
    }

    @Test("allSavedArticles returns empty after unsaving all articles")
    @MainActor
    func allSavedArticlesEmptyAfterUnsave() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feed = TestFixtures.makePersistentFeed()
        try service.addFeed(feed)
        try service.upsertArticles([
            TestFixtures.makeArticle(id: "a1"),
            TestFixtures.makeArticle(id: "a2"),
        ], for: feed)
        try service.save()

        let articles = try service.articles(for: feed)
        // Save both
        try service.toggleArticleSaved(articles[0])
        try service.toggleArticleSaved(articles[1])
        #expect(try service.allSavedArticles(offset: 0, limit: 10, ascending: false).count == 2)

        // Unsave both
        try service.toggleArticleSaved(articles[0])
        try service.toggleArticleSaved(articles[1])
        #expect(try service.allSavedArticles(offset: 0, limit: 10, ascending: false).isEmpty)
    }

    @Test("oldestArticleIDsExceedingLimit excludes saved articles")
    @MainActor
    func oldestArticleIDsExcludesSaved() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feed = TestFixtures.makePersistentFeed()
        try service.addFeed(feed)
        // Create 3 articles, oldest first
        try service.upsertArticles([
            TestFixtures.makeArticle(id: "old", publishedDate: Date(timeIntervalSince1970: 1_000)),
            TestFixtures.makeArticle(id: "mid", publishedDate: Date(timeIntervalSince1970: 2_000)),
            TestFixtures.makeArticle(id: "new", publishedDate: Date(timeIntervalSince1970: 3_000)),
        ], for: feed)
        try service.save()

        // Save the oldest article — it should be exempt from cleanup
        let articles = try service.articles(for: feed)
        let oldest = articles.first { $0.articleID == "old" }!
        try service.toggleArticleSaved(oldest)

        // With a limit of 2, we have 3 articles total, 1 excess
        // The oldest unsaved article ("mid") should be selected for cleanup, not "old" (saved)
        let toDelete = try service.oldestArticleIDsExceedingLimit(2)
        #expect(toDelete.count == 1)
        #expect(toDelete[0].articleID == "mid")
    }

    @Test("oldestArticleIDsExceedingLimit caps at available unsaved articles when most are saved")
    @MainActor
    func oldestArticleIDsCapsAtAvailableUnsaved() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feed = TestFixtures.makePersistentFeed()
        try service.addFeed(feed)
        // Create 4 articles
        try service.upsertArticles([
            TestFixtures.makeArticle(id: "a1", publishedDate: Date(timeIntervalSince1970: 1_000)),
            TestFixtures.makeArticle(id: "a2", publishedDate: Date(timeIntervalSince1970: 2_000)),
            TestFixtures.makeArticle(id: "a3", publishedDate: Date(timeIntervalSince1970: 3_000)),
            TestFixtures.makeArticle(id: "a4", publishedDate: Date(timeIntervalSince1970: 4_000)),
        ], for: feed)
        try service.save()

        // Save 3 of the 4 articles — only 1 unsaved remains
        let articles = try service.articles(for: feed)
        for article in articles where article.articleID != "a2" {
            try service.toggleArticleSaved(article)
        }

        // Limit of 2 means 2 excess (4 total - 2 limit), but only 1 unsaved article exists
        // Should return only the 1 available unsaved article, not crash or return saved ones
        let toDelete = try service.oldestArticleIDsExceedingLimit(2)
        #expect(toDelete.count == 1)
        #expect(toDelete[0].articleID == "a2")
    }

    // MARK: - sortDate Behavior

    // The two tests below pin the cross-feed sort and retention behavior against
    // future-dated articles, the bug that motivated `sortDate`. Real-world feeds
    // (e.g., the Cloudflare blog) publish scheduled posts whose `pubDate` lies
    // hours in the future relative to the feed's `lastBuildDate`. Sorting by raw
    // `publishedDate` would pin those articles to the top of newest-first lists
    // and shield genuinely-old articles from retention. `sortDate` clamps any
    // future date to ingestion time at insert.

    @Test("allArticles uses clamped sortDate for future-dated articles, preserving original publishedDate")
    @MainActor
    func allArticlesClampsFutureDatedArticleSortDate() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feed = TestFixtures.makePersistentFeed()
        try service.addFeed(feed)

        // Reproduces the Cloudflare bug: a feed contains an article whose pubDate
        // is 4 hours in the future (a scheduled post). The bug was that this
        // article would sort by its 4-hour-future raw pubDate, pinning it to the
        // top of newest-first lists by an enormous margin. With sortDate, the
        // article is clamped to ingestion time and sorts as a freshly-ingested
        // article (its sortDate ≈ now), while the original publishedDate is
        // preserved verbatim for the planned content-update detection feature.
        let before = Date()
        try service.upsertArticles([
            TestFixtures.makeArticle(id: "cloudflare", publishedDate: Date().addingTimeInterval(4 * 60 * 60)),
            TestFixtures.makeArticle(id: "verge", publishedDate: Date().addingTimeInterval(-30)),
        ], for: feed)
        let after = Date()
        try service.save()

        let result = try service.allArticles()
        #expect(result.count == 2)

        let cloudflare = try #require(result.first { $0.articleID == "cloudflare" })
        let verge = try #require(result.first { $0.articleID == "verge" })

        // Load-bearing: publishedDate is preserved exactly as the publisher provided
        // it. A planned content-update detection feature compares pubDate values
        // across refreshes, so any mutation here would destroy that signal.
        let preservedPubDate = try #require(cloudflare.publishedDate)
        #expect(preservedPubDate > Date()) // still 4 hours in the future, untouched

        // sortDate is clamped to ingestion time (somewhere between `before` and
        // `after`). It must NOT equal the raw 4-hour-future publishedDate.
        #expect(cloudflare.sortDate >= before)
        #expect(cloudflare.sortDate <= after)
        #expect(cloudflare.sortDate < preservedPubDate)

        // verge's past pubDate passes through unchanged (min(past, now) == past).
        #expect(verge.sortDate == verge.publishedDate)

        // Ordering: cloudflare's clamped sortDate (≈ now) is later than verge's
        // sortDate (now − 30s), so cloudflare appears at index 0 in the descending
        // newest-first sort. This is the post-fix expected ordering — the bug was
        // that cloudflare appeared at index 0 by ~4 hours, dominating verge by an
        // enormous margin. With sortDate, the gap is ~30 seconds (verge's offset),
        // not ~4 hours. Pin the position so a regression that reverts to raw
        // publishedDate sorting still produces the same index but for the wrong
        // reason — the sortDate clamp assertion above is the load-bearing check.
        #expect(result[0].articleID == "cloudflare")
        #expect(result[1].articleID == "verge")
    }

    @Test("oldestArticleIDsExceedingLimit uses sortDate so future-dated articles are not deleted prematurely")
    @MainActor
    func oldestArticleIDsExceedingLimitUsesSortDate() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feed = TestFixtures.makePersistentFeed()
        try service.addFeed(feed)

        // Three articles by ingestion-clamped sortDate ordering:
        //   - "genuinely-old": publishedDate = 1970-epoch+1000 → sortDate = past
        //   - "recent-real":   publishedDate = -60s → sortDate = -60s
        //   - "future-claimed": publishedDate = +10h → sortDate ≈ now (clamped)
        // With limit=1 (excess=2), the two oldest by sortDate should be returned:
        // "genuinely-old" and "recent-real". "future-claimed" must NOT be returned
        // because its sortDate ≈ now is the freshest, even though its publishedDate
        // would otherwise sort it as the newest if we used the raw value.
        try service.upsertArticles([
            TestFixtures.makeArticle(id: "genuinely-old", publishedDate: Date(timeIntervalSince1970: 1000)),
            TestFixtures.makeArticle(id: "future-claimed", publishedDate: Date().addingTimeInterval(10 * 60 * 60)),
            TestFixtures.makeArticle(id: "recent-real", publishedDate: Date().addingTimeInterval(-60)),
        ], for: feed)
        try service.save()

        let result = try service.oldestArticleIDsExceedingLimit(1)
        #expect(result.count == 2)
        let ids = Set(result.map(\.articleID))
        #expect(ids.contains("genuinely-old"))
        #expect(ids.contains("recent-real"))
        #expect(!ids.contains("future-claimed"))
    }

    // The four tests below close coverage on the per-feed and unread-only sort
    // descriptors that the cross-feed `allArticles` and retention tests above don't
    // exercise. Each pins a single migrated SortDescriptor with a future + past pair
    // so a regression that reverts one descriptor to `\.publishedDate` would fail.

    @Test("articles(for:offset:limit:ascending:false) clamps future-dated article")
    @MainActor
    func perFeedDescendingClampsFutureDatedArticle() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feed = TestFixtures.makePersistentFeed()
        try service.addFeed(feed)
        try service.upsertArticles([
            TestFixtures.makeArticle(id: "future", publishedDate: Date().addingTimeInterval(4 * 60 * 60)),
            TestFixtures.makeArticle(id: "past", publishedDate: Date().addingTimeInterval(-3600)),
        ], for: feed)
        try service.save()

        let result = try service.articles(for: feed, offset: 0, limit: 10, ascending: false)
        #expect(result.count == 2)
        // Newest-first: future (clamped to ~now) comes before past (-1h).
        #expect(result[0].articleID == "future")
        #expect(result[1].articleID == "past")
        // The future article must be sorted by clamped sortDate, not raw publishedDate.
        #expect(result[0].sortDate < result[0].publishedDate!)
    }

    @Test("unreadArticles(for:offset:limit:ascending:false) clamps future-dated article")
    @MainActor
    func perFeedUnreadDescendingClampsFutureDatedArticle() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feed = TestFixtures.makePersistentFeed()
        try service.addFeed(feed)
        try service.upsertArticles([
            TestFixtures.makeArticle(id: "future-unread", publishedDate: Date().addingTimeInterval(4 * 60 * 60)),
            TestFixtures.makeArticle(id: "past-unread", publishedDate: Date().addingTimeInterval(-3600)),
        ], for: feed)
        try service.save()

        let result = try service.unreadArticles(for: feed, offset: 0, limit: 10, ascending: false)
        #expect(result.count == 2)
        #expect(result[0].articleID == "future-unread")
        #expect(result[1].articleID == "past-unread")
        #expect(result[0].sortDate < result[0].publishedDate!)
    }

    @Test("allUnreadArticles() (no pagination) clamps future-dated article")
    @MainActor
    func crossFeedUnreadNoPaginationClampsFutureDatedArticle() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feed = TestFixtures.makePersistentFeed()
        try service.addFeed(feed)
        try service.upsertArticles([
            TestFixtures.makeArticle(id: "future-unread", publishedDate: Date().addingTimeInterval(4 * 60 * 60)),
            TestFixtures.makeArticle(id: "past-unread", publishedDate: Date().addingTimeInterval(-3600)),
        ], for: feed)
        try service.save()

        let result = try service.allUnreadArticles()
        #expect(result.count == 2)
        #expect(result[0].articleID == "future-unread")
        #expect(result[1].articleID == "past-unread")
        #expect(result[0].sortDate < result[0].publishedDate!)
    }

    @Test("allUnreadArticles(offset:limit:ascending:true) sorts oldest-first by sortDate")
    @MainActor
    func crossFeedUnreadAscendingClampsFutureDatedArticle() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feed = TestFixtures.makePersistentFeed()
        try service.addFeed(feed)
        try service.upsertArticles([
            TestFixtures.makeArticle(id: "future-unread", publishedDate: Date().addingTimeInterval(4 * 60 * 60)),
            TestFixtures.makeArticle(id: "past-unread", publishedDate: Date().addingTimeInterval(-3600)),
        ], for: feed)
        try service.save()

        let result = try service.allUnreadArticles(offset: 0, limit: 10, ascending: true)
        #expect(result.count == 2)
        // Oldest-first: past (-1h) comes before future (clamped to ~now).
        #expect(result[0].articleID == "past-unread")
        #expect(result[1].articleID == "future-unread")
        // The future article must be sorted by clamped sortDate, not raw publishedDate.
        #expect(result[1].sortDate < result[1].publishedDate!)
    }

    // The two tests below pin the secondary sort tie-breaker (`articleID` ascending)
    // that all article SortDescriptors carry. The tie-breaker is necessary because
    // `sortDate` clamping makes collisions common: every future-dated and every
    // nil-pubDate article in a refresh batch lands at ≈ now. Without a deterministic
    // secondary key, SwiftData / SQLite returns identical-key rows in storage-engine
    // order, which is unstable across queries — breaking pagination (an item could
    // shift between pages or be skipped entirely between page 1 and page 2 fetches).

    @Test("Sort order is stable when multiple articles share the same sortDate")
    @MainActor
    func sortOrderIsStableForIdenticalSortDates() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feed = TestFixtures.makePersistentFeed()
        try service.addFeed(feed)

        // Three articles whose publishedDate (and therefore sortDate) is identical.
        // Inserted in non-alphabetical order so a missing tie-breaker would let the
        // storage engine return them in insertion order rather than articleID order.
        let sharedDate = Date(timeIntervalSince1970: 1_700_000_000)
        try service.upsertArticles([
            TestFixtures.makeArticle(id: "c-third", publishedDate: sharedDate),
            TestFixtures.makeArticle(id: "a-first", publishedDate: sharedDate),
            TestFixtures.makeArticle(id: "b-second", publishedDate: sharedDate),
        ], for: feed)
        try service.save()

        let firstFetch = try service.allArticles()
        let secondFetch = try service.allArticles()

        // Same query run twice must return the same order.
        #expect(firstFetch.map(\.articleID) == secondFetch.map(\.articleID))

        // The order is determined by the articleID secondary sort (forward), so
        // the result is alphabetical: a, b, c — regardless of insertion order.
        #expect(firstFetch.map(\.articleID) == ["a-first", "b-second", "c-third"])
    }

    @Test("Pagination is stable across pages when sortDates collide")
    @MainActor
    func paginationIsStableForIdenticalSortDates() throws {
        let (service, container) = try makeService()
        withExtendedLifetime(container) { }
        let feed = TestFixtures.makePersistentFeed()
        try service.addFeed(feed)

        // Five articles with identical sortDates. A missing tie-breaker would let
        // page 1 (offset=0, limit=2) and page 2 (offset=2, limit=2) overlap or skip
        // items, depending on storage-engine ordering.
        let sharedDate = Date(timeIntervalSince1970: 1_700_000_000)
        try service.upsertArticles([
            TestFixtures.makeArticle(id: "e", publishedDate: sharedDate),
            TestFixtures.makeArticle(id: "b", publishedDate: sharedDate),
            TestFixtures.makeArticle(id: "d", publishedDate: sharedDate),
            TestFixtures.makeArticle(id: "a", publishedDate: sharedDate),
            TestFixtures.makeArticle(id: "c", publishedDate: sharedDate),
        ], for: feed)
        try service.save()

        let page1 = try service.allArticles(offset: 0, limit: 2, ascending: false)
        let page2 = try service.allArticles(offset: 2, limit: 2, ascending: false)
        let page3 = try service.allArticles(offset: 4, limit: 2, ascending: false)

        // No overlap between pages
        let allReturnedIDs = page1.map(\.articleID) + page2.map(\.articleID) + page3.map(\.articleID)
        #expect(Set(allReturnedIDs).count == allReturnedIDs.count, "pages must not overlap")
        // All 5 articles accounted for across the three pages
        #expect(Set(allReturnedIDs) == Set(["a", "b", "c", "d", "e"]))
        // The articleID secondary sort is .forward, and the primary sort is .reverse
        // by sortDate. With all sortDates identical, only the secondary applies, so
        // the order is alphabetical ascending (a, b, c, d, e) regardless of which
        // direction the primary key claims.
        #expect(page1.map(\.articleID) == ["a", "b"])
        #expect(page2.map(\.articleID) == ["c", "d"])
        #expect(page3.map(\.articleID) == ["e"])
    }
}
