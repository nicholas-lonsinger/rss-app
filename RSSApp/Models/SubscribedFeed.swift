import Foundation

struct SubscribedFeed: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let title: String
    let url: URL
    let feedDescription: String
    let addedDate: Date
}
