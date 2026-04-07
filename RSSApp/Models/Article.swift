import Foundation

struct Article: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let link: URL?
    let articleDescription: String
    let snippet: String
    let publishedDate: Date?
    /// Atom `<updated>` (or equivalent namespaced element such as `dc:modified`,
    /// `dcterms:modified`, or `atom:updated`) parsed as a first-class signal so the
    /// persistence layer can detect when a publisher has revised an existing article.
    /// `nil` for feeds that don't expose any update timestamp.
    let updatedDate: Date?
    let thumbnailURL: URL?
    let author: String?
    let categories: [String]
}
