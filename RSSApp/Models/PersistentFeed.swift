import Foundation
import SwiftData

@Model
final class PersistentFeed {

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

    // MARK: - Icon

    var iconURL: URL?

    // MARK: - Error state

    var lastFetchError: String?
    var lastFetchErrorDate: Date?

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
        addedDate: Date = Date(),
        sortOrder: Int = 0,
        lastRefreshDate: Date? = nil,
        etag: String? = nil,
        lastModifiedHeader: String? = nil,
        iconURL: URL? = nil,
        lastFetchError: String? = nil,
        lastFetchErrorDate: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.feedURL = feedURL
        self.feedDescription = feedDescription
        self.addedDate = addedDate
        self.sortOrder = sortOrder
        self.lastRefreshDate = lastRefreshDate
        self.etag = etag
        self.lastModifiedHeader = lastModifiedHeader
        self.iconURL = iconURL
        self.lastFetchError = lastFetchError
        self.lastFetchErrorDate = lastFetchErrorDate
        self.articles = []
        self.groupMemberships = []
    }
}
