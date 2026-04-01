import Foundation

struct ArticleContent: Sendable {
    let title: String
    let byline: String?
    /// Cleaned HTML from the article content extractor — for display in the reader web view.
    let htmlContent: String
    /// Plain-text version from the article content extractor — for AI discussion context.
    let textContent: String

    /// Creates fallback content from raw RSS description HTML when extraction fails.
    static func rssFallback(html: String) -> ArticleContent {
        ArticleContent(
            title: "",
            byline: nil,
            htmlContent: html,
            textContent: HTMLUtilities.stripHTML(html)
        )
    }
}
