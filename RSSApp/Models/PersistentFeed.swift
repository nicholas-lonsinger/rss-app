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
