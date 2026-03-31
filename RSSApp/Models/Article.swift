import Foundation

struct Article: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let link: URL?
    let articleDescription: String
    let snippet: String
    let publishedDate: Date?
    let thumbnailURL: URL?
}
