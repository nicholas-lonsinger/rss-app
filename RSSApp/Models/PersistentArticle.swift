import Foundation
import SwiftData

@Model
final class PersistentArticle {

    // MARK: - Identity

    var articleID: String

    // MARK: - Content

    var title: String
    var link: URL?
    var articleDescription: String
    var snippet: String
    var publishedDate: Date?
    /// Atom `<updated>` (or namespaced equivalent) parsed from the feed XML. Distinct from
    /// `publishedDate` so the persistence layer can detect publisher revisions across
    /// refreshes by comparing this value against the incoming feed. `nil` for feeds that
    /// don't expose any update timestamp, and `nil` for articles persisted before this
    /// field existed (SwiftData lightweight migration leaves the new column null).
    var updatedDate: Date?
    /// Set to `true` when `FeedPersistenceService.upsertArticles` detects an update bump
    /// against this row. Cleared when the user opens the article (the read transition).
    /// Distinguishes "newly resurfaced because content changed" from "brand new unread"
    /// in the article list UI.
    var wasUpdated: Bool
    var thumbnailURL: URL?
    var author: String?
    var categories: [String]

    // MARK: - Read status

    var isRead: Bool
    var readDate: Date?

    // MARK: - Saved status

    var isSaved: Bool
    var savedDate: Date?

    // MARK: - Thumbnail caching

    // RATIONALE: Thumbnail state is stored directly on PersistentArticle rather than in a
    // separate model because SwiftData @Model classes cannot use enums with associated values
    // as persisted properties, and a separate one-to-one model would add join overhead for
    // every article query. Two scalar fields are the simplest SwiftData-compatible approach.
    var isThumbnailCached: Bool
    var thumbnailRetryCount: Int

    // MARK: - Caching

    var fetchedDate: Date

    // MARK: - Sort Key

    // RATIONALE: `sortDate` is a separate persisted field — distinct from `publishedDate`
    // — because real-world feeds publish scheduled posts whose `pubDate` lies hours in
    // the future relative to fetch time (e.g., the Cloudflare blog announces upcoming
    // content). Sorting by raw `publishedDate` would pin those future-dated articles to
    // the top of newest-first lists and let them shield genuinely-old articles from
    // retention. `sortDate` is computed at insert via `clampedSortDate(publishedDate:)`,
    // clamping any future date to ingestion time, while `publishedDate` is preserved
    // verbatim for a planned content-update detection feature that compares pubDate
    // values across refreshes.
    //
    // **Stability invariant: do not mutate `sortDate` after insert.** The "computed
    // once" property is enforced *behaviorally* by `FeedPersistenceService.upsertArticles`,
    // which skips existing rows on re-fetch — so `sortDate` is set exactly once per row
    // in production. Any future code path that touches `sortDate` on an already-persisted
    // article (most likely candidate: the planned content-update detection feature, when
    // it starts mutating articles in place rather than skipping them) must justify the
    // drift, because reshuffling articles after the user has seen them is a UX regression
    // and breaks the "fresh from when we ingested it" guarantee. SwiftData requires
    // `var` here, so this invariant cannot be enforced at the type level.
    var sortDate: Date

    // MARK: - Relationships

    var feed: PersistentFeed?

    @Relationship(deleteRule: .cascade, inverse: \PersistentArticleContent.article)
    var content: PersistentArticleContent?

    init(
        articleID: String,
        title: String,
        link: URL? = nil,
        articleDescription: String = "",
        snippet: String = "",
        publishedDate: Date? = nil,
        updatedDate: Date? = nil,
        wasUpdated: Bool = false,
        thumbnailURL: URL? = nil,
        author: String? = nil,
        categories: [String] = [],
        isRead: Bool = false,
        readDate: Date? = nil,
        isSaved: Bool = false,
        savedDate: Date? = nil,
        isThumbnailCached: Bool = false,
        thumbnailRetryCount: Int = 0,
        fetchedDate: Date = Date(),
        sortDate: Date? = nil
    ) {
        self.articleID = articleID
        self.title = title
        self.link = link
        self.articleDescription = articleDescription
        self.snippet = snippet
        self.publishedDate = publishedDate
        self.updatedDate = updatedDate
        self.wasUpdated = wasUpdated
        self.thumbnailURL = thumbnailURL
        self.author = author
        self.categories = categories
        self.isRead = isRead
        self.readDate = readDate
        self.isSaved = isSaved
        self.savedDate = savedDate
        self.isThumbnailCached = isThumbnailCached
        self.thumbnailRetryCount = thumbnailRetryCount
        self.fetchedDate = fetchedDate
        // When the caller doesn't supply an explicit `sortDate` (the common case via the
        // `init(from: Article)` convenience init), compute it from `publishedDate` here so
        // every construction path goes through the same clamping rule. Tests that need to
        // pin a specific value can still override.
        self.sortDate = sortDate ?? Self.clampedSortDate(publishedDate: publishedDate)
    }

    // MARK: - Display Helpers

    /// Stable display value for the article's original publication time, suitable for
    /// "Published [N] days ago" labels in list rows.
    ///
    /// Distinct from `sortDate` because PR 2 of issue #74 will start bumping `sortDate`
    /// to the current time when content-update detection fires, so the row view can
    /// keep showing the *original* publication time alongside a separate "Updated [N]
    /// minutes ago" label. Computed inline as `min(publishedDate ?? fetchedDate, fetchedDate)`:
    ///
    /// - `fetchedDate` is the clamp ceiling. It's set once at insert and never mutated by
    ///   `upsertArticles`, so it preserves the same "no future-dated articles displayed"
    ///   guarantee that `clampedSortDate(publishedDate:)` enforces at insert time.
    /// - When `publishedDate` is `nil` (parser rejected an implausible date or the feed
    ///   omitted it), the fallback to `fetchedDate` keeps the row showing *some* stable
    ///   moment instead of an empty cell.
    ///
    /// This is a non-persisted computed property — SwiftData ignores it because it's not
    /// declared as a stored `var`.
    var displayedPublishedDate: Date {
        min(publishedDate ?? fetchedDate, fetchedDate)
    }

    /// Computes the clamped `sortDate` for an article with the given `publishedDate`.
    ///
    /// Returns `min(publishedDate ?? now, now)`:
    /// - **Past `publishedDate`**: returned unchanged (the common case).
    /// - **Future `publishedDate`** (e.g., Cloudflare scheduled posts): clamped to `now`
    ///   so the article sorts as freshly-ingested instead of by an inflated future
    ///   timestamp that would pin it to the top of newest-first lists.
    /// - **Nil `publishedDate`** (parser rejected an implausible date, or the feed
    ///   omitted it): falls back to `now` so the article still has a stable, non-optional
    ///   sort key.
    ///
    /// Centralized as a `static` so production (`init(from:)`) and test fixtures
    /// (`TestFixtures.makePersistentArticle`) cannot drift apart on the formula.
    /// `now` is exposed as a parameter so tests can pin a deterministic value.
    static func clampedSortDate(publishedDate: Date?, now: Date = Date()) -> Date {
        min(publishedDate ?? now, now)
    }
}
