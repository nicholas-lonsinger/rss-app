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
    // retention. `sortDate` is computed at insert as `min(publishedDate ?? now, now)`,
    // clamping any future date to ingestion time, while `publishedDate` is preserved
    // verbatim for a planned content-update detection feature that compares pubDate
    // values across refreshes. `sortDate` is computed once and never updated, so an
    // article's sort position is stable over its lifetime — it does not drift even
    // after the publisher's claimed pubDate moment passes.
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
        sortDate: Date
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
        self.isSaved = isSaved
        self.savedDate = savedDate
        self.isThumbnailCached = isThumbnailCached
        self.thumbnailRetryCount = thumbnailRetryCount
        self.fetchedDate = fetchedDate
        self.sortDate = sortDate
    }
}
