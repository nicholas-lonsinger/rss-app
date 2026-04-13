import Foundation
import os
import SwiftData

@Model
final class PersistentFeed {

    private static let logger = Logger(category: "PersistentFeed")


    // MARK: - Identity

    var id: UUID
    var feedURL: URL

    // MARK: - Metadata

    var title: String
    var feedDescription: String
    var addedDate: Date

    /// Position within the feeds list. Defaults to `0` — existing feeds that
    /// predate this field are assigned a deterministic order based on
    /// `addedDate` at query time (secondary sort descriptor). Users can
    /// customize the order via drag-to-reorder in the All Feeds list.
    var sortOrder: Int

    // MARK: - Caching

    var lastRefreshDate: Date?
    var etag: String?
    var lastModifiedHeader: String?

    // MARK: - Site URL

    /// The feed's user-facing website URL, sourced from the `htmlUrl` attribute in
    /// OPML files. Distinct from `feedURL` (the XML endpoint). `nil` for feeds added
    /// before this field was introduced — SwiftData's implicit schema migration
    /// initializes the new optional column to `nil` for existing rows on the first
    /// launch after the schema bump.
    var siteURL: URL?

    // MARK: - Icon

    /// The image URL declared in the feed's XML (`<image><url>` in RSS,
    /// `<logo>` / `<icon>` in Atom). Persisted so the on-view icon resolution
    /// path can use it as a candidate even when the background refresh path
    /// was skipped (e.g. WiFi-only download setting on cellular). `nil` for
    /// feeds that predate this field or whose XML declares no image.
    var feedImageURL: URL?

    /// The URL of the successfully resolved and cached icon. Set after
    /// `FeedIconService.resolveAndCacheIcon` finds and caches a suitable icon.
    /// Distinct from `feedImageURL` (the feed's declared source) — this is the
    /// winning candidate's URL after download, scoring, and caching.
    var iconURL: URL?

    /// Raw-value storage for `iconBackgroundStyle`. Access the enum via the
    /// computed property below — see `FeedIconBackgroundStyle` for semantics.
    var iconBackgroundStyleRaw: String?

    /// Typed accessor for the cached icon's background-style classification
    /// (issue #342). `nil` when the feed predates the classifier. Marked
    /// `@Transient` so SwiftData leaves this computed accessor alone and only
    /// persists `iconBackgroundStyleRaw`.
    @Transient
    var iconBackgroundStyle: FeedIconBackgroundStyle? {
        get {
            guard let raw = iconBackgroundStyleRaw else { return nil }
            if let style = FeedIconBackgroundStyle(rawValue: raw) { return style }
            Self.logger.fault("Invalid iconBackgroundStyleRaw '\(raw, privacy: .public)' on feed \(self.id.uuidString, privacy: .public)")
            assertionFailure("Invalid iconBackgroundStyleRaw: \(raw)")
            return nil
        }
        set { iconBackgroundStyleRaw = newValue?.rawValue }
    }

    // MARK: - Error state

    var lastFetchError: String?
    var lastFetchErrorDate: Date?

    /// The date when the current fetch-failure streak began (i.e., the first
    /// failure after the most recent success). Set on the nil → error
    /// transition; cleared on a successful fetch. Unlike `lastFetchErrorDate`,
    /// this field is NOT overwritten on every failure — it preserves the
    /// streak-start so callers can compute how long the feed has been broken.
    var firstFetchErrorDate: Date?

    // MARK: - Relationships

    @Relationship(deleteRule: .cascade, inverse: \PersistentArticle.feed)
    var articles: [PersistentArticle]

    @Relationship(deleteRule: .cascade, inverse: \PersistentFeedGroupMembership.feed)
    var groupMemberships: [PersistentFeedGroupMembership]

    init(
        id: UUID = UUID(),
        title: String,
        feedURL: URL,
        feedDescription: String = "",
        siteURL: URL? = nil,
        addedDate: Date = Date(),
        sortOrder: Int = 0,
        lastRefreshDate: Date? = nil,
        etag: String? = nil,
        lastModifiedHeader: String? = nil,
        feedImageURL: URL? = nil,
        iconURL: URL? = nil,
        iconBackgroundStyleRaw: String? = nil,
        lastFetchError: String? = nil,
        lastFetchErrorDate: Date? = nil,
        firstFetchErrorDate: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.feedURL = feedURL
        self.feedDescription = feedDescription
        self.siteURL = siteURL
        self.addedDate = addedDate
        self.sortOrder = sortOrder
        self.lastRefreshDate = lastRefreshDate
        self.etag = etag
        self.lastModifiedHeader = lastModifiedHeader
        self.feedImageURL = feedImageURL
        self.iconURL = iconURL
        self.iconBackgroundStyleRaw = iconBackgroundStyleRaw
        self.lastFetchError = lastFetchError
        self.lastFetchErrorDate = lastFetchErrorDate
        self.firstFetchErrorDate = firstFetchErrorDate
        self.articles = []
        self.groupMemberships = []
    }
}
