import Foundation

struct SubscribedFeed: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let title: String
    let url: URL
    let feedDescription: String
    let addedDate: Date
    let lastFetchError: String?
    let lastFetchErrorDate: Date?

    init(
        id: UUID,
        title: String,
        url: URL,
        feedDescription: String,
        addedDate: Date,
        lastFetchError: String? = nil,
        lastFetchErrorDate: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.url = url
        self.feedDescription = feedDescription
        self.addedDate = addedDate
        self.lastFetchError = lastFetchError
        self.lastFetchErrorDate = lastFetchErrorDate
    }

    func updatingMetadata(title: String, feedDescription: String) -> SubscribedFeed {
        SubscribedFeed(
            id: id, title: title, url: url,
            feedDescription: feedDescription, addedDate: addedDate
        )
    }

    func updatingError(_ message: String) -> SubscribedFeed {
        SubscribedFeed(
            id: id, title: title, url: url,
            feedDescription: feedDescription, addedDate: addedDate,
            lastFetchError: message, lastFetchErrorDate: Date()
        )
    }

    func updatingURL(_ newURL: URL) -> SubscribedFeed {
        SubscribedFeed(
            id: id, title: title, url: newURL,
            feedDescription: feedDescription, addedDate: addedDate
        )
    }
}
