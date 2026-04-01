import Foundation

struct ArticleContent: Sendable {
    let title: String
    let byline: String?
    /// Cleaned HTML from the article content extractor — for display in the reader web view.
    let htmlContent: String
    /// Plain-text version from the article content extractor — for AI discussion context.
    let textContent: String
}
