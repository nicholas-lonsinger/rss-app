import Foundation

struct ArticleContent: Sendable {
    let title: String
    let byline: String?
    /// Cleaned HTML extracted by Readability — for display in the reader web view.
    let htmlContent: String
    /// Plain-text version extracted by Readability — for AI discussion context.
    let textContent: String
}
