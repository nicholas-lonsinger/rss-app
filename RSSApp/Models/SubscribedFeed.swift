import Foundation

struct SubscribedFeed: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let title: String
    let url: URL
    let feedDescription: String
    let addedDate: Date

    func updatingMetadata(title: String, feedDescription: String) -> SubscribedFeed {
        SubscribedFeed(id: id, title: title, url: url, feedDescription: feedDescription, addedDate: addedDate)
    }
}
