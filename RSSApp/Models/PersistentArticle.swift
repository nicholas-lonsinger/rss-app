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
    /// Atom `<updated>` (or namespaced equivalent — `dc:modified`, `dcterms:modified`,
    /// `atom:updated`) parsed from the feed XML. Distinct from `publishedDate` so the
    /// persistence layer can compare this value across refreshes when detecting
    /// publisher revisions (issue #74). `nil` for feeds that don't expose any update
    /// timestamp, and `nil` for articles persisted before this field was added —
    /// SwiftData's implicit schema migration initializes the new optional column to
    /// `nil` for existing rows on the first launch after the schema bump.
    var updatedDate: Date?
    /// Set to `true` by `FeedPersistenceService.upsertArticles` when a re-fetch
    /// detects a strictly newer Atom `<updated>` (or namespaced equivalent) on an
    /// existing row, alongside the cache invalidation, `isRead` reset, and `sortDate`
    /// bump that mark the article as resurfaced (issue #74). Cleared on every read
    /// transition: `markArticleRead(_:isRead: true)`, `markAllArticlesRead(for:)`,
    /// and `markAllArticlesRead()` all set the flag back to `false` so the orange
    /// "Updated" badge in the row view disappears the moment the user opens the
    /// article (or bulk-marks it read).
    ///
    /// **Invariant:** when `true`, `updatedDate` is guaranteed non-nil. The
    /// mutation site in `upsertArticles` guards the incoming `article.updatedDate`
    /// against nil and assigns it to `existing.updatedDate` immediately before
    /// flipping the flag, so the post-state always satisfies
    /// `wasUpdated == true → updatedDate != nil`.
    ///
    /// **Asymmetric clear:** `markArticleRead(_:isRead: false)` does NOT re-set
    /// `wasUpdated`. Manually marking unread should not lie about the article having
    /// been updated — the publisher revision is a fact about the content, not a
    /// function of the user's read toggle. The flag has exactly one writer
    /// (`upsertArticles`); the clear paths above all set it to `false` only on a
    /// read transition.
    ///
    /// **Destructive transition:** the update path resets `isRead = false` and
    /// `readDate = nil`. The original "first read" timestamp is NOT preserved across
    /// detection. If a future feature needs "read-before-update" history, this
    /// decision must be revisited.
    ///
    /// Existing rows persisted before this field was added deserialize as `false` via
    /// SwiftData's implicit schema migration, matching the default for fresh inserts.
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

    // RATIONALE: `fetchedDate` is set exactly once at insert (the designated init's
    // default is `Date()`) and is never mutated by `FeedPersistenceService.upsertArticles`
    // or anywhere else in production code. This post-insert immutability is load-bearing
    // for the `displayedPublishedDate` computed property below, which uses `fetchedDate`
    // as the clamp ceiling so the row view shows a stable original publication time
    // even though `upsertArticles` mutates `sortDate` on content-update detection
    // (issue #74). Any future code path that mutates `fetchedDate` on an already-
    // persisted article would silently retroactively change `displayedPublishedDate`
    // for every article inserted before that change. SwiftData requires `var` here, so
    // this invariant cannot be enforced at the type level.
    var fetchedDate: Date

    // MARK: - Sort Key

    // RATIONALE: `sortDate` is a separate persisted field — distinct from `publishedDate`
    // — because real-world feeds publish scheduled posts whose `pubDate` lies hours in
    // the future relative to fetch time (e.g., the Cloudflare blog announces upcoming
    // content). Sorting by raw `publishedDate` would pin those future-dated articles to
    // the top of newest-first lists and let them shield genuinely-old articles from
    // retention. `sortDate` is computed at insert via `clampedSortDate(publishedDate:)`,
    // clamping any future date to ingestion time, while `publishedDate` is preserved
    // verbatim for the content-update detection feature that compares dates across
    // refreshes (issue #74).
    //
    // **Stability rule: `sortDate` is set once per row at insert and only ever changes
    // when `FeedPersistenceService.upsertArticles` detects a strictly newer Atom
    // `<updated>` (or namespaced equivalent) on a re-fetch.** That is the single
    // justified mutation: a genuine publisher revision is meaningfully different from
    // a stale-but-untouched article, and the user has explicitly opted into surfacing
    // updated articles at the top of newest-first lists (issue #74) so they can find
    // the new content. The bump uses `clampedSortDate(publishedDate: now, now: now)`
    // — i.e., set to the current wall clock — and is paired with `wasUpdated = true`,
    // `isRead = false`, and a cache invalidation in the same transaction so the row
    // resurfaces as unread with fresh content. Any *other* code path that touches
    // `sortDate` on an already-persisted article (e.g., a tempting "fix" that resorts
    // by recomputing from a mutated `publishedDate`) must justify the drift in writing,
    // because reshuffling articles for non-update reasons is a UX regression and breaks
    // the "fresh from when we ingested it" guarantee. SwiftData requires `var` here,
    // so this rule cannot be enforced at the type level — `upsertArticles` is the only
    // production writer.
    var sortDate: Date

    // MARK: - Relationships

    var feed: PersistentFeed?

    // RATIONALE: `deleteRule: .cascade` is load-bearing for content-update detection in
    // `FeedPersistenceService.upsertArticles`, which drops `existing.content` on a
    // publisher revision (issue #74) so the next visit re-extracts. The upsert path
    // explicitly deletes the orphan via `modelContext.delete(staleContent)` before
    // nilling the relationship — see the comment in `upsertArticles` — but the cascade
    // rule remains the safety net for the more common case of deleting the parent row
    // (article retention cleanup, feed deletion). Changing this to `.nullify` would
    // orphan rows in both paths.
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

    /// Stable display value for the article's original publication time, consumed by
    /// `ArticleRowDateLine` (in `ArticleRowView.swift`, shared by both the per-feed
    /// `ArticleRowView` and `CrossFeedArticleRowView`).
    ///
    /// Distinct from `sortDate` because `FeedPersistenceService.upsertArticles`
    /// mutates `sortDate` to the current time when content-update detection fires on
    /// a re-fetch (issue #74; see the stability rule block on `sortDate` above for
    /// the single sanctioned mutation path and its constraints). `ArticleRowDateLine`
    /// uses this property to render the stable "original publication time" label
    /// alongside an "Updated [date]" suffix sourced from `updatedDate` — both labels
    /// stay accurate even after `sortDate` is bumped on update detection.
    ///
    /// Formula: `min(publishedDate ?? fetchedDate, fetchedDate)`.
    ///
    /// - For production-inserted rows, `fetchedDate` is the wall clock at insert time
    ///   (set once via the designated init's default; see the `RATIONALE:` block on
    ///   `fetchedDate` above for why it's never mutated). The result is therefore
    ///   guaranteed to be ≤ ingestion time, preserving the same "no future-dated
    ///   articles displayed" guarantee that `clampedSortDate(publishedDate:)` enforces
    ///   for `sortDate`.
    /// - When `publishedDate` is `nil` (parser rejected an implausible date or the feed
    ///   omitted it), the fallback to `fetchedDate` keeps the row showing *some* stable
    ///   moment instead of an empty cell.
    /// - Tests that pass a synthetic future `fetchedDate` will see that future value
    ///   pass through unclamped — the property does not re-clamp against `Date()` at
    ///   read time, since that would make the displayed value non-stable across calls
    ///   and cause SwiftUI diffing churn.
    ///
    /// This is a computed property (no backing storage), so SwiftData's `@Model` macro
    /// does not generate persistence code for it. SwiftData only persists stored
    /// properties — Swift requires `var` for any computed property regardless.
    var displayedPublishedDate: Date {
        min(publishedDate ?? fetchedDate, fetchedDate)
    }

    /// Whether row UI should display the "Updated [date]" suffix alongside the
    /// original publication time. True when the publisher has revised the article
    /// meaningfully — i.e., `updatedDate` exists and differs from
    /// `displayedPublishedDate` by strictly more than `Self.updateSuffixTolerance`
    /// seconds.
    ///
    /// The 1-second tolerance suppresses noise from feeds that fill `<updated>` with
    /// the same value as `<published>` on first publish (very common in WordPress
    /// and stock Atom generators) — without it, every fresh row would carry a
    /// "Updated [N]s ago" suffix that's identical to its "Published [N]s ago" line.
    /// Compares against `displayedPublishedDate` (not raw `publishedDate`) so the
    /// predicate stays consistent with what the row actually renders for the
    /// original-time label, including the future-date clamp behavior.
    ///
    /// Extracted as a computed property (rather than left inline in the row view)
    /// so the predicate is unit-testable without standing up SwiftUI machinery, and
    /// so a future refactor that accidentally compares against `publishedDate`
    /// instead of `displayedPublishedDate` can be caught by a regression test
    /// rather than slipping into a release.
    var shouldShowUpdatedSuffix: Bool {
        guard let updated = updatedDate else { return false }
        return abs(updated.timeIntervalSince(displayedPublishedDate)) > Self.updateSuffixTolerance
    }

    /// Tolerance window (seconds) used by `shouldShowUpdatedSuffix` to suppress
    /// no-op "Updated [date]" suffixes when the publisher emits identical
    /// `<published>` and `<updated>` timestamps on first publish.
    static let updateSuffixTolerance: TimeInterval = 1

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
