import Foundation
import os

/// Extracts article metadata (title, byline) from a serialized DOM.
///
/// Sources checked in priority order:
/// 1. OpenGraph / article meta tags (`og:title`, `article:author`)
/// 2. DOM elements (`<h1>`, byline class patterns)
enum MetadataExtractor {

    private static let logger = Logger(
        subsystem: "com.nicholas-lonsinger.rss-app",
        category: "MetadataExtractor"
    )

    struct Metadata: Sendable {
        let title: String
        let byline: String?
    }

    /// Extracts the best title and byline from the serialized DOM.
    static func extract(from dom: SerializedDOM) -> Metadata {
        let title = extractTitle(from: dom)
        let byline = extractByline(from: dom)
        logger.debug("Extracted title='\(title, privacy: .public)', byline='\(byline ?? "nil", privacy: .public)'")
        return Metadata(title: title, byline: byline)
    }

    // MARK: - Title

    private static func extractTitle(from dom: SerializedDOM) -> String {
        // 1. OpenGraph title
        if let ogTitle = dom.meta?["og:title"], !ogTitle.isEmpty {
            return ogTitle
        }

        // 2. Twitter title
        if let twitterTitle = dom.meta?["twitter:title"], !twitterTitle.isEmpty {
            return twitterTitle
        }

        // 3. First <h1> inside <article> (or first <h1> in the page)
        if let articleNode = findFirst(in: dom.body, where: { $0.tagName == "article" }),
           let h1 = findFirst(in: articleNode, where: { $0.tagName == "h1" }) {
            let text = h1.textContent.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { return text }
        }

        if let h1 = findFirst(in: dom.body, where: { $0.tagName == "h1" }) {
            let text = h1.textContent.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { return text }
        }

        // 4. Document title (may include site name suffix)
        if !dom.title.isEmpty {
            return cleanDocumentTitle(dom.title)
        }

        return ""
    }

    /// Strips common site name suffixes from `document.title`.
    ///
    /// Many sites format titles as "Article Title - Site Name" or "Article Title | Site Name".
    private static func cleanDocumentTitle(_ title: String) -> String {
        let separators: [Character] = ["|", "-", "–", "—", ":", "·"]
        for sep in separators {
            let parts = title.split(separator: sep, maxSplits: 1)
            if parts.count == 2 {
                let first = parts[0].trimmingCharacters(in: .whitespaces)
                let second = parts[1].trimmingCharacters(in: .whitespaces)
                // The longer part is likely the title; the shorter is the site name.
                if first.count >= second.count && first.count >= 10 {
                    return first
                }
                if second.count > first.count && second.count >= 10 {
                    return second
                }
            }
        }
        return title
    }

    // MARK: - Byline

    /// Patterns in class/id that indicate a byline element.
    private static let bylinePatterns = [
        "byline", "author", "writtenby", "written-by",
    ]

    private static func extractByline(from dom: SerializedDOM) -> String? {
        // 1. article:author meta tag
        if let author = dom.meta?["article:author"], !author.isEmpty {
            return author
        }

        // 2. author meta tag
        if let author = dom.meta?["author"], !author.isEmpty {
            return author
        }

        // 3. Search DOM for byline-patterned elements
        if let bylineNode = findByline(in: dom.body) {
            let text = bylineNode.textContent.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                return cleanByline(text)
            }
        }

        return nil
    }

    /// Searches for a DOM node whose class or id matches byline patterns.
    private static func findByline(in node: DOMNode) -> DOMNode? {
        let matchString = (node.className + " " + node.identifier).lowercased()
        for pattern in bylinePatterns {
            if matchString.contains(pattern) {
                return node
            }
        }
        for child in node.children {
            if let found = findByline(in: child) { return found }
        }
        return nil
    }

    /// Strips common prefixes like "By " from byline text.
    private static func cleanByline(_ text: String) -> String {
        var cleaned = text
        let prefixes = ["by ", "written by ", "author: ", "posted by "]
        let lower = cleaned.lowercased()
        for prefix in prefixes {
            if lower.hasPrefix(prefix) {
                cleaned = String(cleaned.dropFirst(prefix.count))
                break
            }
        }
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Tree Traversal

    private static func findFirst(in node: DOMNode, where predicate: (DOMNode) -> Bool) -> DOMNode? {
        if predicate(node) { return node }
        for child in node.children {
            if let found = findFirst(in: child, where: predicate) { return found }
        }
        return nil
    }
}
