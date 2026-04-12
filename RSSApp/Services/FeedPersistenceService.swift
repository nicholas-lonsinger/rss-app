import Foundation
import SwiftData
import os

// MARK: - Article Pagination Cursor

/// Cursor for group-scoped article pagination. Encapsulates the `sortDate`
/// and `articleID` of the last article in the previous page, enabling
/// predicate-based pagination that fetches only `limit` articles per feed
/// regardless of scroll depth — O(feeds * limit) instead of the
/// O(feeds * (offset + limit)) cost of offset-based pagination.
///
/// The `articleID` component breaks ties when multiple articles share
/// the same `sortDate`, ensuring deterministic page boundaries.
struct ArticlePaginationCursor: Sendable, Equatable {
    let sortDate: Date
    let articleID: String

    /// Convenience initializer that captures the cursor position from an article.
    init(after article: PersistentArticle) {
        self.sortDate = article.sortDate
        self.articleID = article.articleID
    }

    init(sortDate: Date, articleID: String) {
        self.sortDate = sortDate
        self.articleID = articleID
    }
}

// MARK: - Protocol

@MainActor
protocol FeedPersisting: Sendable {

    // MARK: Feed operations

    func allFeeds() throws -> [PersistentFeed]
    func addFeed(_ feed: PersistentFeed) throws
    func deleteFeed(_ feed: PersistentFeed) throws
    func updateFeedMetadata(_ feed: PersistentFeed, title: String, description: String) throws
    func updateFeedError(_ feed: PersistentFeed, error: String?) throws
    func updateFeedURL(_ feed: PersistentFeed, newURL: URL) throws
    func updateFeedCacheHeaders(_ feed: PersistentFeed, etag: String?, lastModified: String?) throws
    /// Persists the feed's cached icon URL and the luminance-based
    /// background-style classification produced by `FeedIconService`.
    /// Passing `nil` for `backgroundStyle` clears the classification (used
    /// when the icon is cleared).
    func updateFeedIcon(_ feed: PersistentFeed, iconURL: URL?, backgroundStyle: FeedIconBackgroundStyle?) throws
    func feedExists(url: URL) throws -> Bool

    // MARK: Article operations

    /// Returns all articles for a feed, sorted by `sortDate` descending (newest first).
    /// `sortDate` is the publisher-supplied `publishedDate` clamped to ingestion time at insert
    /// — see `PersistentArticle.sortDate` for the rationale.
    func articles(for feed: PersistentFeed) throws -> [PersistentArticle]
    /// Returns a page of articles for a feed, sorted by `sortDate`.
    /// - Parameters:
    ///   - offset: Number of articles to skip from the beginning of the sorted result set.
    ///   - limit: Maximum number of articles to return.
    ///   - ascending: When `true`, sorts oldest first; when `false` (default), sorts newest first.
    func articles(for feed: PersistentFeed, offset: Int, limit: Int, ascending: Bool) throws -> [PersistentArticle]
    /// Returns a page of unread articles for a feed, sorted by `sortDate`.
    /// - Parameters:
    ///   - offset: Number of articles to skip from the beginning of the sorted result set.
    ///   - limit: Maximum number of articles to return.
    ///   - ascending: When `true`, sorts oldest first; when `false` (default), sorts newest first.
    func unreadArticles(for feed: PersistentFeed, offset: Int, limit: Int, ascending: Bool) throws -> [PersistentArticle]
    /// Returns all articles across all feeds, sorted by `sortDate` descending (newest first).
    func allArticles() throws -> [PersistentArticle]
    /// Returns a page of all articles across all feeds, sorted by `sortDate`.
    /// - Parameters:
    ///   - offset: Number of articles to skip from the beginning of the sorted result set.
    ///   - limit: Maximum number of articles to return.
    ///   - ascending: When `true`, sorts oldest first; when `false` (default), sorts newest first.
    func allArticles(offset: Int, limit: Int, ascending: Bool) throws -> [PersistentArticle]
    /// Returns all unread articles across all feeds, sorted by `sortDate` descending (newest first).
    func allUnreadArticles() throws -> [PersistentArticle]
    /// Returns a page of unread articles across all feeds, sorted by `sortDate`.
    /// - Parameters:
    ///   - offset: Number of articles to skip from the beginning of the sorted result set.
    ///   - limit: Maximum number of articles to return.
    ///   - ascending: When `true`, sorts oldest first; when `false` (default), sorts newest first.
    func allUnreadArticles(offset: Int, limit: Int, ascending: Bool) throws -> [PersistentArticle]
    func upsertArticles(_ articles: [Article], for feed: PersistentFeed) throws
    func markArticleRead(_ article: PersistentArticle, isRead: Bool) throws
    /// Marks all articles in a specific feed as read.
    func markAllArticlesRead(for feed: PersistentFeed) throws
    /// Marks all articles across all feeds as read.
    func markAllArticlesRead() throws
    func unreadCount(for feed: PersistentFeed) throws -> Int
    /// Returns the total number of unread articles across all feeds.
    func totalUnreadCount() throws -> Int

    // MARK: Saved article operations

    /// Toggles the saved state of an article. Sets `isSaved` and updates `savedDate`.
    func toggleArticleSaved(_ article: PersistentArticle) throws
    /// Marks only articles with `isSaved == true` as read. Used by the Saved
    /// Articles list's "Mark All as Read" action so it scopes to the list
    /// the user is looking at rather than sweeping every article in the app.
    func markAllSavedArticlesRead() throws
    /// Returns a page of saved articles across all feeds, sorted by
    /// `sortDate` with direction controlled by `ascending`. Uses the same
    /// global sort order as `allArticles(offset:limit:ascending:)` and
    /// `allUnreadArticles(offset:limit:ascending:)` so the three cross-feed
    /// lists feel consistent — the Saved list honors the user's current
    /// newest-first / oldest-first preference rather than hardcoding a
    /// savedDate-descending order.
    func allSavedArticles(offset: Int, limit: Int, ascending: Bool) throws -> [PersistentArticle]
    // MARK: Content cache

    func cachedContent(for article: PersistentArticle) throws -> PersistentArticleContent?
    func cacheContent(_ content: ArticleContent, for article: PersistentArticle) throws

    // MARK: Thumbnail tracking

    /// Returns articles that need thumbnail downloads: not yet cached and under the retry cap.
    func articlesNeedingThumbnails(maxRetryCount: Int) throws -> [PersistentArticle]

    /// Marks an article's thumbnail as successfully cached.
    func markThumbnailCached(_ article: PersistentArticle) throws

    /// Increments the thumbnail retry count for an article after a failed download attempt.
    func incrementThumbnailRetryCount(_ article: PersistentArticle) throws

    // MARK: Article cleanup

    /// Returns the total number of articles across all feeds.
    func totalArticleCount() throws -> Int

    /// Returns the article IDs of the oldest unsaved articles exceeding the given limit,
    /// sorted by `sortDate` ascending (oldest first). Saved articles are exempt from
    /// retention cleanup and are excluded from the returned results. Sorting by `sortDate`
    /// rather than `publishedDate` prevents future-dated scheduled posts (e.g., the
    /// Cloudflare blog's upcoming-content feed) from being deleted prematurely.
    /// - Parameter limit: The maximum number of articles to retain.
    /// - Returns: Article IDs that should be deleted, along with their `isThumbnailCached` flag.
    func oldestArticleIDsExceedingLimit(_ limit: Int) throws -> [(articleID: String, isThumbnailCached: Bool)]

    /// Deletes articles by their article IDs.
    /// - Parameter articleIDs: The set of article IDs to delete.
    func deleteArticles(withIDs articleIDs: Set<String>) throws

    // MARK: Feed reordering

    /// Persists the display order of feeds by writing each feed's array index
    /// into its `sortOrder` field and saving.
    func updateFeedOrder(_ feeds: [PersistentFeed]) throws

    // MARK: Group operations

    /// Returns all feed groups, sorted by `sortOrder` then `createdDate`.
    func allGroups() throws -> [PersistentFeedGroup]
    func addGroup(_ group: PersistentFeedGroup) throws
    func deleteGroup(_ group: PersistentFeedGroup) throws
    func renameGroup(_ group: PersistentFeedGroup, to name: String) throws
    /// Persists the display order of groups by writing each group's array index
    /// into its `sortOrder` field and saving.
    func updateGroupOrder(_ groups: [PersistentFeedGroup]) throws

    /// Adds a feed to a group. No-op if the membership already exists.
    func addFeed(_ feed: PersistentFeed, to group: PersistentFeedGroup) throws
    func removeFeed(_ feed: PersistentFeed, from group: PersistentFeedGroup) throws
    func feeds(in group: PersistentFeedGroup) throws -> [PersistentFeed]
    func groups(for feed: PersistentFeed) throws -> [PersistentFeedGroup]

    /// Returns a page of articles from all feeds in the group, sorted by `sortDate`,
    /// using cursor-based pagination. Fetches only `limit` articles per feed regardless
    /// of scroll depth — O(feeds * limit) — by filtering with a predicate on `sortDate`
    /// rather than skipping `offset` rows per feed.
    ///
    /// - Parameters:
    ///   - group: The feed group whose member feeds' articles are queried.
    ///   - cursor: The last article's `sortDate` and `articleID` from the previous page.
    ///     Pass `nil` for the first page.
    ///   - limit: Maximum number of articles to return.
    ///   - ascending: When `true`, sorts oldest first; when `false`, sorts newest first.
    func articles(in group: PersistentFeedGroup, cursor: ArticlePaginationCursor?, limit: Int, ascending: Bool) throws -> [PersistentArticle]

    /// Returns the total number of unread articles across all feeds in the group.
    func unreadCount(in group: PersistentFeedGroup) throws -> Int
    /// Marks all articles in all feeds belonging to the group as read.
    func markAllArticlesRead(in group: PersistentFeedGroup) throws

    // MARK: Persistence

    func save() throws
}

// MARK: - SwiftData Implementation

@MainActor
final class SwiftDataFeedPersistenceService: FeedPersisting {

    private static let logger = Logger(category: "FeedPersistenceService")

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Feed Operations

    func allFeeds() throws -> [PersistentFeed] {
        let descriptor = FetchDescriptor<PersistentFeed>(
            sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.addedDate)]
        )
        let feeds = try modelContext.fetch(descriptor)
        Self.logger.debug("Fetched \(feeds.count, privacy: .public) feeds")
        return feeds
    }

    func addFeed(_ feed: PersistentFeed) throws {
        modelContext.insert(feed)
        try modelContext.save()
        Self.logger.notice("Added feed '\(feed.title, privacy: .public)'")
    }

    func deleteFeed(_ feed: PersistentFeed) throws {
        let title = feed.title
        modelContext.delete(feed)
        try modelContext.save()
        Self.logger.notice("Deleted feed '\(title, privacy: .public)'")
    }

    func updateFeedMetadata(_ feed: PersistentFeed, title: String, description: String) throws {
        feed.title = title
        feed.feedDescription = description
        feed.lastRefreshDate = Date()
        feed.lastFetchError = nil
        feed.lastFetchErrorDate = nil
        feed.firstFetchErrorDate = nil
        Self.logger.debug("Updated metadata for '\(title, privacy: .public)'")
    }

    func updateFeedError(_ feed: PersistentFeed, error: String?) throws {
        if error == nil {
            // Clearing error state on success — reset both error fields and
            // the streak-start so the next failure restarts the streak clock.
            feed.lastFetchError = nil
            feed.lastFetchErrorDate = nil
            feed.firstFetchErrorDate = nil
        } else {
            // Record the streak-start only on the nil → error transition.
            // If firstFetchErrorDate is already set, the feed is still in an
            // ongoing streak — preserve the original start date so callers
            // can compute how long the feed has been broken.
            if feed.firstFetchErrorDate == nil {
                feed.firstFetchErrorDate = Date()
            }
            feed.lastFetchError = error
            feed.lastFetchErrorDate = Date()
        }
        Self.logger.debug("Updated error state for '\(feed.title, privacy: .public)'")
    }

    func updateFeedURL(_ feed: PersistentFeed, newURL: URL) throws {
        feed.feedURL = newURL
        feed.lastFetchError = nil
        feed.lastFetchErrorDate = nil
        feed.firstFetchErrorDate = nil
        try modelContext.save()
        Self.logger.debug("Updated URL for '\(feed.title, privacy: .public)'")
    }

    func updateFeedCacheHeaders(_ feed: PersistentFeed, etag: String?, lastModified: String?) throws {
        feed.etag = etag
        feed.lastModifiedHeader = lastModified
        Self.logger.debug("Updated cache headers for '\(feed.title, privacy: .public)'")
    }

    func updateFeedIcon(_ feed: PersistentFeed, iconURL: URL?, backgroundStyle: FeedIconBackgroundStyle?) throws {
        feed.iconURL = iconURL
        feed.iconBackgroundStyle = backgroundStyle
        Self.logger.debug("Updated icon for '\(feed.title, privacy: .public)' (background=\(backgroundStyle?.rawValue ?? "nil", privacy: .public))")
    }

    func feedExists(url: URL) throws -> Bool {
        let feedURL = url
        var descriptor = FetchDescriptor<PersistentFeed>(
            predicate: #Predicate { $0.feedURL == feedURL }
        )
        descriptor.fetchLimit = 1
        let count = try modelContext.fetchCount(descriptor)
        return count > 0
    }

    // MARK: - Article Operations

    func articles(for feed: PersistentFeed) throws -> [PersistentArticle] {
        let feedID = feed.persistentModelID
        let descriptor = FetchDescriptor<PersistentArticle>(
            predicate: #Predicate { $0.feed?.persistentModelID == feedID },
            sortBy: [
                SortDescriptor(\.sortDate, order: .reverse),
                SortDescriptor(\.articleID, order: .forward)
            ]
        )
        return try modelContext.fetch(descriptor)
    }

    func articles(for feed: PersistentFeed, offset: Int, limit: Int, ascending: Bool = false) throws -> [PersistentArticle] {
        let feedID = feed.persistentModelID
        let sortOrder: SortOrder = ascending ? .forward : .reverse
        var descriptor = FetchDescriptor<PersistentArticle>(
            predicate: #Predicate { $0.feed?.persistentModelID == feedID },
            sortBy: [
                SortDescriptor(\.sortDate, order: sortOrder),
                SortDescriptor(\.articleID, order: .forward)
            ]
        )
        descriptor.fetchOffset = offset
        descriptor.fetchLimit = limit
        let articles = try modelContext.fetch(descriptor)
        Self.logger.debug("Fetched \(articles.count, privacy: .public) articles for feed (offset: \(offset, privacy: .public), limit: \(limit, privacy: .public), ascending: \(ascending, privacy: .public))")
        return articles
    }

    func unreadArticles(for feed: PersistentFeed, offset: Int, limit: Int, ascending: Bool = false) throws -> [PersistentArticle] {
        let feedID = feed.persistentModelID
        let sortOrder: SortOrder = ascending ? .forward : .reverse
        var descriptor = FetchDescriptor<PersistentArticle>(
            predicate: #Predicate { $0.feed?.persistentModelID == feedID && !$0.isRead },
            sortBy: [
                SortDescriptor(\.sortDate, order: sortOrder),
                SortDescriptor(\.articleID, order: .forward)
            ]
        )
        descriptor.fetchOffset = offset
        descriptor.fetchLimit = limit
        let articles = try modelContext.fetch(descriptor)
        Self.logger.debug("Fetched \(articles.count, privacy: .public) unread articles for feed (offset: \(offset, privacy: .public), limit: \(limit, privacy: .public), ascending: \(ascending, privacy: .public))")
        return articles
    }

    func allArticles() throws -> [PersistentArticle] {
        let descriptor = FetchDescriptor<PersistentArticle>(
            sortBy: [
                SortDescriptor(\.sortDate, order: .reverse),
                SortDescriptor(\.articleID, order: .forward)
            ]
        )
        let articles = try modelContext.fetch(descriptor)
        Self.logger.debug("Fetched \(articles.count, privacy: .public) total articles")
        return articles
    }

    func allArticles(offset: Int, limit: Int, ascending: Bool = false) throws -> [PersistentArticle] {
        let sortOrder: SortOrder = ascending ? .forward : .reverse
        var descriptor = FetchDescriptor<PersistentArticle>(
            sortBy: [
                SortDescriptor(\.sortDate, order: sortOrder),
                SortDescriptor(\.articleID, order: .forward)
            ]
        )
        descriptor.fetchOffset = offset
        descriptor.fetchLimit = limit
        let articles = try modelContext.fetch(descriptor)
        Self.logger.debug("Fetched \(articles.count, privacy: .public) total articles (offset: \(offset, privacy: .public), limit: \(limit, privacy: .public), ascending: \(ascending, privacy: .public))")
        return articles
    }

    func allUnreadArticles() throws -> [PersistentArticle] {
        let descriptor = FetchDescriptor<PersistentArticle>(
            predicate: #Predicate { !$0.isRead },
            sortBy: [
                SortDescriptor(\.sortDate, order: .reverse),
                SortDescriptor(\.articleID, order: .forward)
            ]
        )
        let articles = try modelContext.fetch(descriptor)
        Self.logger.debug("Fetched \(articles.count, privacy: .public) unread articles")
        return articles
    }

    func allUnreadArticles(offset: Int, limit: Int, ascending: Bool = false) throws -> [PersistentArticle] {
        let sortOrder: SortOrder = ascending ? .forward : .reverse
        var descriptor = FetchDescriptor<PersistentArticle>(
            predicate: #Predicate { !$0.isRead },
            sortBy: [
                SortDescriptor(\.sortDate, order: sortOrder),
                SortDescriptor(\.articleID, order: .forward)
            ]
        )
        descriptor.fetchOffset = offset
        descriptor.fetchLimit = limit
        let articles = try modelContext.fetch(descriptor)
        Self.logger.debug("Fetched \(articles.count, privacy: .public) unread articles (offset: \(offset, privacy: .public), limit: \(limit, privacy: .public), ascending: \(ascending, privacy: .public))")
        return articles
    }

    // RATIONALE: Existing rows are mutated only when the feed XML carries a strictly newer
    // Atom <updated> timestamp than what we already stored (issue #74). The detection
    // compares against `(existing.updatedDate ?? existing.publishedDate)` so articles
    // persisted before the `updatedDate` column existed still participate via their
    // `publishedDate`. When BOTH baselines are nil (the parser previously rejected every
    // date format on the row), detection is skipped — see the explicit guard in the
    // function body for the policy and rationale.
    //
    // **Field-mutation policy on detection** — exhaustive list of how each persisted
    // property is treated when the update path fires:
    //
    //   Mutated (publisher-visible body content):
    //     • `updatedDate`           ← incoming
    //     • `articleDescription`    ← incoming
    //     • `snippet`               ← incoming
    //     • `wasUpdated`            ← `true`
    //     • `sortDate`              ← `clampedSortDate(publishedDate: now, now: now)`
    //                                 (the single sanctioned post-insert mutation; see
    //                                 the stability rule on `PersistentArticle.sortDate`)
    //     • `content`               ← `nil` (the PersistentArticleContent row is
    //                                 explicitly deleted from the store, not just
    //                                 nilled — see the explicit `modelContext.delete`
    //                                 call below)
    //
    //   Reset (so the article re-surfaces as unread for the user):
    //     • `isRead`                ← `false`
    //     • `readDate`              ← `nil`
    //
    //   Preserved (user-generated state and identity that the publisher does not own):
    //     • `title`                 — publisher revisions to the title are intentionally
    //                                 dropped. Re-fetching titles would require a UX
    //                                 surface for "title has changed" that isn't scoped
    //                                 for this PR. Revisit if users report stale titles.
    //     • `link`, `author`, `categories`, `thumbnailURL` — same rationale as `title`
    //     • `publishedDate`         — verbatim publisher value, never mutated post-insert
    //     • `fetchedDate`           — load-bearing for `displayedPublishedDate`'s clamp
    //                                 ceiling; see the RATIONALE on `fetchedDate`
    //     • `isSaved`, `savedDate`  — user-generated state
    //     • `isThumbnailCached`, `thumbnailRetryCount` — system-managed cache state;
    //                                 the cached JPEG file is unaffected by a body
    //                                 revision unless the publisher also re-points
    //                                 `thumbnailURL`, which we don't currently detect.
    //
    // The original read timestamp (the moment the user first read the article) is NOT
    // preserved across detection. If a future feature needs "read-before-update"
    // history, this decision must be revisited. See the companion doc comment on
    // `markArticleRead` for the first-read-timestamp contract (issue #271) that
    // governs every non-upsert transition of `readDate`.
    func upsertArticles(_ articles: [Article], for feed: PersistentFeed) throws {
        // Fetch existing rows by ID. We need the full objects (not just the IDs) so we
        // can compare timestamps and mutate in place when an update bump is detected —
        // the existing query already loaded these, so reusing the objects in a lookup
        // dictionary adds no extra fetch (just an in-memory hash table allocation).
        let feedID = feed.persistentModelID
        let incomingIDs = articles.map(\.id)
        let descriptor = FetchDescriptor<PersistentArticle>(
            predicate: #Predicate { article in
                article.feed?.persistentModelID == feedID
                    && incomingIDs.contains(article.articleID)
            }
        )
        let existingArticles = try modelContext.fetch(descriptor)

        // Build the lookup defensively. `Dictionary(uniqueKeysWithValues:)` would TRAP
        // on duplicate `articleID`s, and the schema does not enforce per-feed `articleID`
        // uniqueness at the SwiftData level (no `@Attribute(.unique)` on
        // `PersistentArticle.articleID`). Real-world feeds can produce duplicate IDs via
        // the parser's `guid → link → hash(title+description)` derivation chain when
        // guids are missing or shared across items, so a duplicate row in the store is
        // plausible (legacy data, malformed feeds, future migration glitches). Crashing
        // the entire refresh path is the wrong failure mode — keep the first row, log a
        // `.warning` so the data inconsistency is discoverable in post-mortem, and
        // proceed.
        var existingByID: [String: PersistentArticle] = [:]
        existingByID.reserveCapacity(existingArticles.count)
        for row in existingArticles {
            if existingByID[row.articleID] != nil {
                Self.logger.warning(
                    "Duplicate PersistentArticle rows for articleID '\(row.articleID, privacy: .public)' in feed '\(feed.title, privacy: .public)' — using the first encountered; investigate the data inconsistency"
                )
                continue
            }
            existingByID[row.articleID] = row
        }

        var insertedCount = 0
        var updatedCount = 0
        let now = Date()

        for article in articles {
            if let existing = existingByID[article.id] {
                // Update detection: only act when the incoming feed actually carries an
                // updatedDate AND it's strictly newer than our baseline. If the incoming
                // article has no updatedDate, OR the incoming value isn't newer, skip —
                // preserving the historical insert-only semantics for feeds that don't
                // expose <updated> at all.
                guard let incomingUpdated = article.updatedDate else { continue }
                let baseline = existing.updatedDate ?? existing.publishedDate
                guard let baseline else {
                    // The existing row has neither `updatedDate` nor `publishedDate`,
                    // which only happens when the parser rejected every date format on
                    // the original ingest. We cannot establish "strictly newer" against
                    // an unknown baseline, and firing detection unconditionally on every
                    // refresh would oscillate this article between read and unread
                    // forever (the user could never make it stop). Skip and log once so
                    // the condition is discoverable in post-mortem.
                    Self.logger.warning(
                        "Skipping update detection for '\(existing.title, privacy: .public)' (id \(existing.articleID, privacy: .public)) in feed '\(feed.title, privacy: .public)': existing row has no baseline date — detection requires a non-nil publishedDate or updatedDate"
                    )
                    continue
                }
                guard incomingUpdated > baseline else { continue }

                // Capture pre-mutation state for the per-article audit log below. The
                // `previousReadDate != nil` case is the user-visible "this article I
                // already read came back" event and deserves a `.notice` so post-mortem
                // analysis can answer "which article? when was it originally read? what
                // was the baseline-vs-incoming delta?" without spelunking the DB.
                let previousReadDate = existing.readDate
                let previousSortDate = existing.sortDate

                // Mutate in place. The sortDate bump is the single justified mutation
                // permitted by the stability rule on `PersistentArticle.sortDate` —
                // re-read that comment for the rationale.
                existing.updatedDate = incomingUpdated
                existing.wasUpdated = true
                existing.isRead = false
                existing.readDate = nil
                existing.articleDescription = article.articleDescription
                existing.snippet = article.snippet
                existing.sortDate = PersistentArticle.clampedSortDate(publishedDate: now, now: now)
                // Drop the cached extracted content so ArticleSummaryViewModel.loadContent()
                // re-extracts on next visit. The `@Relationship(deleteRule: .cascade)` on
                // `PersistentArticle.content` cascades on parent-row delete, NOT on
                // relationship-nullify, so we delete the content row explicitly here to
                // guarantee the orphan is removed from the store regardless of how
                // SwiftData treats nullification across releases.
                if let staleContent = existing.content {
                    modelContext.delete(staleContent)
                }
                existing.content = nil

                if let previousReadDate {
                    Self.logger.notice(
                        "Resurfaced read article '\(existing.title, privacy: .public)' (id \(existing.articleID, privacy: .public)) in feed '\(feed.title, privacy: .public)': baseline \(baseline, privacy: .public), incoming updated \(incomingUpdated, privacy: .public), previously read at \(previousReadDate, privacy: .public), previous sortDate \(previousSortDate, privacy: .public)"
                    )
                } else {
                    Self.logger.debug(
                        "Updated unread article '\(existing.title, privacy: .public)' (id \(existing.articleID, privacy: .public)) in feed '\(feed.title, privacy: .public)': baseline \(baseline, privacy: .public), incoming updated \(incomingUpdated, privacy: .public)"
                    )
                }

                updatedCount += 1
            } else {
                let persistent = PersistentArticle(from: article)
                persistent.feed = feed
                modelContext.insert(persistent)
                insertedCount += 1
            }
        }

        let unchangedCount = articles.count - insertedCount - updatedCount
        // Split the summary log by outcome: routine no-op refreshes go to `.debug` (in
        // memory only) so they don't drown the persisted log buffer for power users
        // with many feeds. Refreshes that actually mutated the store go to `.notice`
        // for post-mortem analysis.
        if insertedCount > 0 || updatedCount > 0 {
            Self.logger.notice("Upserted articles for '\(feed.title, privacy: .public)': \(insertedCount, privacy: .public) new, \(updatedCount, privacy: .public) updated, \(unchangedCount, privacy: .public) unchanged")
        } else {
            Self.logger.debug("Upsert no-op for '\(feed.title, privacy: .public)': \(unchangedCount, privacy: .public) unchanged")
        }
    }

    /// Marks an article as read or unread.
    ///
    /// **`readDate` semantics (issue #271): `readDate` records the moment the user
    /// *first* read the article, not the most recent read action.** Calling this
    /// with `isRead: true` on an article that already has a non-nil `readDate` is
    /// a no-op for the timestamp — the existing value is preserved. Transitioning
    /// `isRead: false` clears `readDate` to `nil`; a subsequent `isRead: true`
    /// therefore stamps a *new* first-read time, because the previous read was
    /// explicitly undone by the user.
    ///
    /// **Destructive transitions for `readDate`** — the timestamp can be cleared
    /// by exactly two paths:
    /// 1. *User-initiated*: this method with `isRead: false` (the user explicitly
    ///    toggled the article back to unread).
    /// 2. *System-initiated*: `upsertArticles` resets `readDate = nil` when its
    ///    update-detection path fires (see the RATIONALE block above
    ///    `upsertArticles`, which calls out `readDate` under "Reset" so the row
    ///    resurfaces as unread after a publisher revision).
    ///
    /// Bulk paths (`markAllArticlesRead(for:)`, `markAllArticlesRead()`) are not
    /// destructive: their fetch predicates filter on `!$0.isRead` (and the
    /// write-side invariant — every path clearing `isRead` also clears `readDate`
    /// — means every fetched row arrives with `readDate == nil`), and their loop
    /// bodies also guard on `article.readDate == nil` before stamping — mirroring
    /// this method. Both layers together mean the first-read contract cannot be
    /// broken even if a future refactor loosens the predicate (issue #282).
    ///
    /// Also clears the issue #74 `wasUpdated` flag on the read transition. See the
    /// doc comment on `PersistentArticle.wasUpdated` for the asymmetric-clear
    /// rationale (manually marking unread does not re-set the flag).
    func markArticleRead(_ article: PersistentArticle, isRead: Bool) throws {
        let previousReadDate = article.readDate
        article.isRead = isRead
        if isRead {
            // Stamp only when `readDate` is currently nil — the actual gate used
            // here. This covers every case where no first-read timestamp exists:
            // a normal first read, a re-read after the user toggled `isRead: false`,
            // a re-read after `upsertArticles` cleared the row on update detection,
            // and any anomalous migrated row that arrived with `readDate == nil`
            // but `isRead == true`. See the doc comment above for the full contract.
            if article.readDate == nil {
                article.readDate = Date()
            }
            // Clear the issue #74 update flag on read transitions. See the doc
            // comment on `PersistentArticle.wasUpdated` for the asymmetric-clear
            // rationale (manually marking unread does not re-set the flag).
            article.wasUpdated = false
        } else {
            article.readDate = nil
        }
        try modelContext.save()
        // Branch the audit log by the `readDate` outcome so post-mortem analysis
        // can tell which of the three paths fired for a given call. Free at
        // `.debug` level (in-memory only per the CLAUDE.md logging table).
        if isRead {
            if let previousReadDate {
                Self.logger.debug("Marked article '\(article.title, privacy: .public)' as read (preserved existing first-read timestamp \(previousReadDate, privacy: .public))")
            } else {
                let stampedDate = article.readDate ?? Date()
                Self.logger.debug("Marked article '\(article.title, privacy: .public)' as read (first-read stamp \(stampedDate, privacy: .public))")
            }
        } else {
            if let previousReadDate {
                Self.logger.debug("Marked article '\(article.title, privacy: .public)' as unread (cleared readDate, was \(previousReadDate, privacy: .public))")
            } else {
                Self.logger.debug("Marked article '\(article.title, privacy: .public)' as unread (readDate was already nil)")
            }
        }
    }

    func markAllArticlesRead(for feed: PersistentFeed) throws {
        let feedID = feed.persistentModelID
        let descriptor = FetchDescriptor<PersistentArticle>(
            predicate: #Predicate { $0.feed?.persistentModelID == feedID && !$0.isRead }
        )
        let unreadArticles = try modelContext.fetch(descriptor)
        guard !unreadArticles.isEmpty else {
            Self.logger.debug("No unread articles to mark as read for feed '\(feed.title, privacy: .public)'")
            return
        }
        let now = Date()
        for article in unreadArticles {
            article.isRead = true
            // Belt-and-suspenders guard mirroring `markArticleRead`: stamp `readDate`
            // only when it is nil. The `!$0.isRead` predicate does not filter on
            // `readDate` directly, but the write-side invariant — every path that
            // clears `isRead` also clears `readDate` — means every row fetched here
            // has `readDate == nil` in practice. If a future write path breaks that
            // invariant, or if the predicate is loosened, this guard prevents
            // silently clobbering existing first-read timestamps (issue #282).
            if article.readDate == nil {
                article.readDate = now
            }
            // Match `markArticleRead`'s read-transition clear so the issue #74
            // "Updated" badge doesn't survive a bulk mark-as-read. Without this, the
            // documented "exactly one clearer" invariant on `wasUpdated` would be
            // false the moment a user invoked this API.
            article.wasUpdated = false
        }
        try modelContext.save()
        Self.logger.notice("Marked \(unreadArticles.count, privacy: .public) articles as read for feed '\(feed.title, privacy: .public)'")
    }

    func markAllArticlesRead() throws {
        let descriptor = FetchDescriptor<PersistentArticle>(
            predicate: #Predicate { !$0.isRead }
        )
        let unreadArticles = try modelContext.fetch(descriptor)
        guard !unreadArticles.isEmpty else {
            Self.logger.debug("No unread articles to mark as read across all feeds")
            return
        }
        let now = Date()
        for article in unreadArticles {
            article.isRead = true
            // Belt-and-suspenders guard mirroring `markArticleRead` and the per-feed
            // bulk path above: stamp `readDate` only when it is nil. The `!$0.isRead`
            // predicate does not filter on `readDate` directly, but the write-side
            // invariant — every path that clears `isRead` also clears `readDate` —
            // means every row fetched here has `readDate == nil` in practice. If a
            // future write path breaks that invariant, or if the predicate is
            // loosened, this guard prevents silently clobbering existing first-read
            // timestamps (issue #282).
            if article.readDate == nil {
                article.readDate = now
            }
            // Same read-transition clear as the per-feed bulk path above and the
            // single-article `markArticleRead` — keeps issue #74's `wasUpdated`
            // contract consistent across every read transition.
            article.wasUpdated = false
        }
        try modelContext.save()
        Self.logger.notice("Marked \(unreadArticles.count, privacy: .public) articles as read across all feeds")
    }

    // MARK: - Saved Article Operations

    func toggleArticleSaved(_ article: PersistentArticle) throws {
        let newSaved = !article.isSaved
        article.isSaved = newSaved
        article.savedDate = newSaved ? Date() : nil
        try modelContext.save()
        Self.logger.notice("Toggled saved state for '\(article.title, privacy: .public)' to \(newSaved ? "saved" : "unsaved", privacy: .public)")
    }

    func markAllSavedArticlesRead() throws {
        let now = Date()
        // Fetch only saved articles that are currently unread so we don't
        // touch rows that already satisfy both conditions (no-op churn) and
        // don't scan the full article table (cheaper for large DBs).
        let descriptor = FetchDescriptor<PersistentArticle>(
            predicate: #Predicate { $0.isSaved && !$0.isRead }
        )
        let toMark = try modelContext.fetch(descriptor)
        for article in toMark {
            article.isRead = true
            // Same belt-and-suspenders guard as the other bulk mark-read
            // paths (see `markAllArticlesRead()` above): stamp `readDate` only
            // when it is nil, so a future write path that breaks the "every
            // path that clears isRead also clears readDate" invariant cannot
            // silently clobber existing first-read timestamps (issue #282).
            if article.readDate == nil {
                article.readDate = now
            }
            // Matches the other bulk mark-read paths: clear `wasUpdated` on
            // every read transition so the issue #74 call-to-action badge
            // doesn't linger after the user has acknowledged the update.
            article.wasUpdated = false
        }
        try modelContext.save()
        Self.logger.notice("Marked \(toMark.count, privacy: .public) saved articles as read")
    }

    func allSavedArticles(offset: Int, limit: Int, ascending: Bool = false) throws -> [PersistentArticle] {
        let sortOrder: SortOrder = ascending ? .forward : .reverse
        var descriptor = FetchDescriptor<PersistentArticle>(
            predicate: #Predicate { $0.isSaved },
            sortBy: [
                SortDescriptor(\.sortDate, order: sortOrder),
                SortDescriptor(\.articleID, order: .forward)
            ]
        )
        descriptor.fetchOffset = offset
        descriptor.fetchLimit = limit
        let articles = try modelContext.fetch(descriptor)
        Self.logger.debug("Fetched \(articles.count, privacy: .public) saved articles (offset: \(offset, privacy: .public), limit: \(limit, privacy: .public), ascending: \(ascending, privacy: .public))")
        return articles
    }

    // MARK: - Thumbnail Tracking

    func articlesNeedingThumbnails(maxRetryCount: Int) throws -> [PersistentArticle] {
        let descriptor = FetchDescriptor<PersistentArticle>(
            predicate: #Predicate {
                !$0.isThumbnailCached && $0.thumbnailRetryCount < maxRetryCount
            },
            sortBy: [
                SortDescriptor(\.sortDate, order: .reverse),
                SortDescriptor(\.articleID, order: .forward)
            ]
        )
        let articles = try modelContext.fetch(descriptor)
        Self.logger.debug("Found \(articles.count, privacy: .public) articles needing thumbnails (max retries: \(maxRetryCount, privacy: .public))")
        return articles
    }

    func markThumbnailCached(_ article: PersistentArticle) throws {
        article.isThumbnailCached = true
        Self.logger.debug("Marked thumbnail cached for '\(article.title, privacy: .public)'")
    }

    func incrementThumbnailRetryCount(_ article: PersistentArticle) throws {
        article.thumbnailRetryCount += 1
        Self.logger.debug("Incremented thumbnail retry count to \(article.thumbnailRetryCount, privacy: .public) for '\(article.title, privacy: .public)'")
    }

    func save() throws {
        try modelContext.save()
    }

    func unreadCount(for feed: PersistentFeed) throws -> Int {
        let feedID = feed.persistentModelID
        let descriptor = FetchDescriptor<PersistentArticle>(
            predicate: #Predicate { $0.feed?.persistentModelID == feedID && !$0.isRead }
        )
        return try modelContext.fetchCount(descriptor)
    }

    func totalUnreadCount() throws -> Int {
        let descriptor = FetchDescriptor<PersistentArticle>(
            predicate: #Predicate { !$0.isRead }
        )
        return try modelContext.fetchCount(descriptor)
    }

    // MARK: - Content Cache

    func cachedContent(for article: PersistentArticle) throws -> PersistentArticleContent? {
        article.content
    }

    func cacheContent(_ content: ArticleContent, for article: PersistentArticle) throws {
        if let existing = article.content {
            existing.title = content.title
            existing.byline = content.byline
            existing.htmlContent = content.htmlContent
            existing.textContent = content.textContent
            existing.extractedDate = Date()
        } else {
            let persistent = PersistentArticleContent(from: content)
            persistent.article = article
            modelContext.insert(persistent)
        }
        try modelContext.save()
        Self.logger.debug("Cached content for '\(article.title, privacy: .public)'")
    }

    // MARK: - Article Cleanup

    func totalArticleCount() throws -> Int {
        let descriptor = FetchDescriptor<PersistentArticle>()
        return try modelContext.fetchCount(descriptor)
    }

    func oldestArticleIDsExceedingLimit(_ limit: Int) throws -> [(articleID: String, isThumbnailCached: Bool)] {
        let totalCount = try totalArticleCount()
        guard totalCount > limit else { return [] }

        let excess = totalCount - limit
        // Exclude saved articles from retention cleanup — they are exempt from the limit
        var descriptor = FetchDescriptor<PersistentArticle>(
            predicate: #Predicate { !$0.isSaved },
            sortBy: [
                SortDescriptor(\.sortDate, order: .forward),
                SortDescriptor(\.articleID, order: .forward)
            ]
        )
        descriptor.fetchLimit = excess
        let articles = try modelContext.fetch(descriptor)
        Self.logger.debug("Found \(articles.count, privacy: .public) unsaved articles exceeding limit of \(limit, privacy: .public)")
        return articles.map { (articleID: $0.articleID, isThumbnailCached: $0.isThumbnailCached) }
    }

    /// Batch size for article deletion. Kept below SQLite's default 999 variable limit
    /// to avoid parameter overflow, while being large enough for efficient throughput.
    private static let deletionBatchSize = 500

    func deleteArticles(withIDs articleIDs: Set<String>) throws {
        guard !articleIDs.isEmpty else { return }

        let allIDs = Array(articleIDs)
        var totalDeleted = 0

        for batchStart in stride(from: 0, to: allIDs.count, by: Self.deletionBatchSize) {
            let batchNumber = batchStart / Self.deletionBatchSize + 1
            let batchEnd = min(batchStart + Self.deletionBatchSize, allIDs.count)
            let batchIDs = Array(allIDs[batchStart..<batchEnd])

            do {
                let descriptor = FetchDescriptor<PersistentArticle>(
                    predicate: #Predicate { batchIDs.contains($0.articleID) }
                )
                let articles = try modelContext.fetch(descriptor)
                for article in articles {
                    modelContext.delete(article)
                }
                try modelContext.save()
                totalDeleted += articles.count
                Self.logger.debug("Deleted batch \(batchNumber, privacy: .public): \(articles.count, privacy: .public) articles")
            } catch {
                Self.logger.error("Batch \(batchNumber, privacy: .public) failed after \(totalDeleted, privacy: .public) of \(articleIDs.count, privacy: .public) articles already deleted: \(error, privacy: .public)")
                throw error
            }
        }

        if totalDeleted != articleIDs.count {
            Self.logger.warning("Requested deletion of \(articleIDs.count, privacy: .public) articles but deleted \(totalDeleted, privacy: .public)")
        } else {
            Self.logger.notice("Deleted \(totalDeleted, privacy: .public) articles during cleanup")
        }
    }

    // MARK: - Feed Reordering

    func updateFeedOrder(_ feeds: [PersistentFeed]) throws {
        for (index, feed) in feeds.enumerated() {
            feed.sortOrder = index
        }
        try modelContext.save()
        Self.logger.notice("Updated feed order for \(feeds.count, privacy: .public) feeds")
    }

    // MARK: - Group Operations

    func allGroups() throws -> [PersistentFeedGroup] {
        let descriptor = FetchDescriptor<PersistentFeedGroup>(
            sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.createdDate)]
        )
        let groups = try modelContext.fetch(descriptor)
        Self.logger.debug("Fetched \(groups.count, privacy: .public) groups")
        return groups
    }

    func addGroup(_ group: PersistentFeedGroup) throws {
        guard !group.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            Self.logger.warning("Attempted to add group with empty name — skipping")
            return
        }
        modelContext.insert(group)
        try modelContext.save()
        Self.logger.notice("Added group '\(group.name, privacy: .public)'")
    }

    func deleteGroup(_ group: PersistentFeedGroup) throws {
        let name = group.name
        modelContext.delete(group)
        try modelContext.save()
        Self.logger.notice("Deleted group '\(name, privacy: .public)'")
    }

    func renameGroup(_ group: PersistentFeedGroup, to name: String) throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            Self.logger.warning("Attempted to rename group '\(group.name, privacy: .public)' to empty name — skipping")
            return
        }
        let previousName = group.name
        group.name = name
        try modelContext.save()
        Self.logger.notice("Renamed group '\(previousName, privacy: .public)' to '\(name, privacy: .public)'")
    }

    func updateGroupOrder(_ groups: [PersistentFeedGroup]) throws {
        for (index, group) in groups.enumerated() {
            group.sortOrder = index
        }
        try modelContext.save()
        Self.logger.notice("Updated group order for \(groups.count, privacy: .public) groups")
    }

    func addFeed(_ feed: PersistentFeed, to group: PersistentFeedGroup) throws {
        // Application-layer unique constraint: skip if membership already exists.
        let feedID = feed.persistentModelID
        let groupID = group.persistentModelID
        let descriptor = FetchDescriptor<PersistentFeedGroupMembership>(
            predicate: #Predicate {
                $0.feed?.persistentModelID == feedID
                    && $0.group?.persistentModelID == groupID
            }
        )
        let existingCount = try modelContext.fetchCount(descriptor)
        guard existingCount == 0 else {
            Self.logger.debug("Feed '\(feed.title, privacy: .public)' already in group '\(group.name, privacy: .public)' — skipping")
            return
        }
        let membership = PersistentFeedGroupMembership(feed: feed, group: group)
        modelContext.insert(membership)
        try modelContext.save()
        Self.logger.notice("Added feed '\(feed.title, privacy: .public)' to group '\(group.name, privacy: .public)'")
    }

    func removeFeed(_ feed: PersistentFeed, from group: PersistentFeedGroup) throws {
        let feedID = feed.persistentModelID
        let groupID = group.persistentModelID
        let descriptor = FetchDescriptor<PersistentFeedGroupMembership>(
            predicate: #Predicate {
                $0.feed?.persistentModelID == feedID
                    && $0.group?.persistentModelID == groupID
            }
        )
        let memberships = try modelContext.fetch(descriptor)
        for membership in memberships {
            modelContext.delete(membership)
        }
        try modelContext.save()
        Self.logger.notice("Removed feed '\(feed.title, privacy: .public)' from group '\(group.name, privacy: .public)'")
    }

    func feeds(in group: PersistentFeedGroup) throws -> [PersistentFeed] {
        let feeds = feedsFromMemberships(group.memberships, context: "group '\(group.name)'")
            .sorted { $0.addedDate < $1.addedDate }
        Self.logger.debug("Group '\(group.name, privacy: .public)' contains \(feeds.count, privacy: .public) feeds")
        return feeds
    }

    func groups(for feed: PersistentFeed) throws -> [PersistentFeedGroup] {
        let groups = groupsFromMemberships(feed.groupMemberships, context: "feed '\(feed.title)'")
            .sorted { $0.sortOrder < $1.sortOrder }
        Self.logger.debug("Feed '\(feed.title, privacy: .public)' belongs to \(groups.count, privacy: .public) groups")
        return groups
    }

    // RATIONALE: SwiftData's #Predicate does not support `array.contains(keypath)` on
    // captured PersistentIdentifier arrays. Instead we fetch a bounded window per feed
    // and merge in-memory. For typical group sizes (2–20 feeds) this is efficient and
    // correct. Cursor-based pagination ensures each per-feed fetch is bounded by
    // `limit` regardless of scroll depth — O(feeds * limit) total rows fetched —
    // by filtering with a predicate on `sortDate` rather than skipping `offset` rows.
    func articles(in group: PersistentFeedGroup, cursor: ArticlePaginationCursor?, limit: Int, ascending: Bool = false) throws -> [PersistentArticle] {
        let feeds = feedsFromMemberships(group.memberships, context: "group '\(group.name)'")
        guard !feeds.isEmpty else { return [] }

        let sortOrder: SortOrder = ascending ? .forward : .reverse
        var merged: [PersistentArticle] = []
        merged.reserveCapacity(limit * feeds.count)

        for feed in feeds {
            let feedID = feed.persistentModelID
            let predicate: Predicate<PersistentArticle>

            if let cursor {
                let cursorDate = cursor.sortDate
                let cursorArticleID = cursor.articleID
                if ascending {
                    // Ascending: fetch articles strictly after the cursor.
                    // Same sortDate: only articles with articleID > cursorArticleID.
                    // Later sortDate: all articles.
                    predicate = #Predicate {
                        $0.feed?.persistentModelID == feedID && (
                            $0.sortDate > cursorDate ||
                            ($0.sortDate == cursorDate && $0.articleID > cursorArticleID)
                        )
                    }
                } else {
                    // Descending: fetch the next page in sort order (earlier dates,
                    // or same date with later articleID per the always-ascending
                    // articleID tie-breaker).
                    predicate = #Predicate {
                        $0.feed?.persistentModelID == feedID && (
                            $0.sortDate < cursorDate ||
                            ($0.sortDate == cursorDate && $0.articleID > cursorArticleID)
                        )
                    }
                }
            } else {
                predicate = #Predicate { $0.feed?.persistentModelID == feedID }
            }

            var descriptor = FetchDescriptor<PersistentArticle>(
                predicate: predicate,
                sortBy: [
                    SortDescriptor(\.sortDate, order: sortOrder),
                    SortDescriptor(\.articleID, order: .forward)
                ]
            )
            descriptor.fetchLimit = limit
            let feedArticles = try modelContext.fetch(descriptor)
            merged.append(contentsOf: feedArticles)
        }

        // Re-sort the merged set to interleave articles from different feeds correctly.
        // articleID tie-breaker is always ascending to match the FetchDescriptor and
        // ensure stable pagination when multiple articles share the same sortDate.
        merged.sort {
            if $0.sortDate != $1.sortDate {
                return ascending ? $0.sortDate < $1.sortDate : $0.sortDate > $1.sortDate
            }
            return $0.articleID < $1.articleID
        }

        // Take only `limit` from the merged set — we fetched up to `limit` per feed,
        // so the merged array may contain up to `feeds.count * limit` articles.
        let page = Array(merged.prefix(limit))
        Self.logger.debug("Fetched \(page.count, privacy: .public) articles in group '\(group.name, privacy: .public)' (cursor: \(cursor?.articleID ?? "nil", privacy: .public), limit: \(limit, privacy: .public), ascending: \(ascending, privacy: .public))")
        return page
    }

    func unreadCount(in group: PersistentFeedGroup) throws -> Int {
        let feeds = feedsFromMemberships(group.memberships, context: "group '\(group.name)'")
        var total = 0
        for feed in feeds {
            total += try unreadCount(for: feed)
        }
        return total
    }

    func markAllArticlesRead(in group: PersistentFeedGroup) throws {
        let feeds = feedsFromMemberships(group.memberships, context: "group '\(group.name)'")
        for feed in feeds {
            try markAllArticlesRead(for: feed)
        }
        Self.logger.notice("Marked all articles as read in group '\(group.name, privacy: .public)' (\(feeds.count, privacy: .public) feeds)")
    }

    // MARK: - Group Membership Helpers

    /// Extracts feeds from memberships, logging a `.warning` for any orphaned
    /// membership where the feed relationship is nil (data corruption indicator).
    private func feedsFromMemberships(
        _ memberships: [PersistentFeedGroupMembership],
        context: String
    ) -> [PersistentFeed] {
        memberships.compactMap { membership in
            guard let feed = membership.feed else {
                Self.logger.warning("Orphaned membership \(membership.id, privacy: .public) in \(context, privacy: .public) has nil feed")
                return nil
            }
            return feed
        }
    }

    /// Extracts groups from memberships, logging a `.warning` for any orphaned
    /// membership where the group relationship is nil (data corruption indicator).
    private func groupsFromMemberships(
        _ memberships: [PersistentFeedGroupMembership],
        context: String
    ) -> [PersistentFeedGroup] {
        memberships.compactMap { membership in
            guard let group = membership.group else {
                Self.logger.warning("Orphaned membership \(membership.id, privacy: .public) in \(context, privacy: .public) has nil group")
                return nil
            }
            return group
        }
    }
}
