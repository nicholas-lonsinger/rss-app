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
    var thumbnailURL: URL?
    var author: String?
    var categories: [String]

    // MARK: - Read status

    var isRead: Bool
    var readDate: Date?

    // MARK: - Thumbnail caching

    var isThumbnailCached: Bool
    var thumbnailRetryCount: Int

    // MARK: - Caching

    var fetchedDate: Date

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
        thumbnailURL: URL? = nil,
        author: String? = nil,
        categories: [String] = [],
        isRead: Bool = false,
        readDate: Date? = nil,
        isThumbnailCached: Bool = false,
        thumbnailRetryCount: Int = 0,
        fetchedDate: Date = Date()
    ) {
        self.articleID = articleID
        self.title = title
        self.link = link
        self.articleDescription = articleDescription
        self.snippet = snippet
        self.publishedDate = publishedDate
        self.thumbnailURL = thumbnailURL
        self.author = author
        self.categories = categories
        self.isRead = isRead
        self.readDate = readDate
        self.isThumbnailCached = isThumbnailCached
        self.thumbnailRetryCount = thumbnailRetryCount
        self.fetchedDate = fetchedDate
    }
}
