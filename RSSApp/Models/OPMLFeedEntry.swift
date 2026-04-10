import Foundation

struct OPMLFeedEntry: Sendable, Equatable {
    let title: String
    let feedURL: URL
    let siteURL: URL?
    let description: String

    /// The name of the OPML category (parent `<outline>` without `xmlUrl`) this
    /// feed was nested under, or `nil` if it appeared at the top level. A feed
    /// that appears under multiple categories in the OPML file produces multiple
    /// entries — one per category — so a many-to-many mapping is representable.
    let groupName: String?

    init(
        title: String,
        feedURL: URL,
        siteURL: URL?,
        description: String,
        groupName: String? = nil
    ) {
        self.title = title
        self.feedURL = feedURL
        self.siteURL = siteURL
        self.description = description
        self.groupName = groupName
    }
}
