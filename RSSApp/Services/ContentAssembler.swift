import Foundation
import os

/// Reconstructs clean HTML and plain text from a winning DOM subtree.
///
/// The assembler walks the candidate node's tree and produces:
/// - `htmlContent`: semantic HTML preserving structure (`<p>`, `<h2>`, `<blockquote>`,
///   `<img>`, `<a>`, etc.) but stripping non-content attributes
/// - `textContent`: plain text with paragraph breaks preserved and whitespace normalized
enum ContentAssembler {

    private static let logger = Logger(category: "ContentAssembler")

    /// Tags to preserve in the output HTML (content-carrying elements).
    private static let preservedTags: Set<String> = [
        "p", "h1", "h2", "h3", "h4", "h5", "h6",
        "blockquote", "pre", "code",
        "ul", "ol", "li",
        "a", "strong", "em", "b", "i", "br", "hr",
        "figure", "figcaption", "img",
        "table", "thead", "tbody", "tr", "th", "td",
        "article", "section", "div",
    ]

    /// Assembles clean content from a DOM subtree.
    ///
    /// - Parameters:
    ///   - node: The winning candidate node from scoring.
    /// - Returns: A tuple of (htmlContent, textContent).
    static func assemble(from node: DOMNode) -> (html: String, text: String) {
        var html = ""
        var text = ""
        assembleNode(node, html: &html, text: &text)

        let trimmedText = collapseWhitespace(text)
        logger.debug("Assembled \(html.count, privacy: .public) HTML chars, \(trimmedText.count, privacy: .public) text chars")
        return (html, trimmedText)
    }

    // MARK: - Recursive Assembly

    private static func assembleNode(_ node: DOMNode, html: inout String, text: inout String) {
        if node.isText {
            let content = node.txt ?? ""
            html.append(HTMLUtilities.escapeHTML(content))
            text.append(content)
            return
        }

        guard node.isVisible else { return }

        let tag = node.tagName

        if tag == "br" {
            html.append("<br>")
            text.append("\n")
            return
        }
        if tag == "hr" {
            html.append("<hr>")
            text.append("\n\n")
            return
        }
        if tag == "img" {
            assembleImage(node, html: &html)
            return
        }

        let preserve = preservedTags.contains(tag)

        if preserve {
            html.append("<\(tag)")
            appendAttributes(for: node, tag: tag, html: &html)
            html.append(">")
        }

        let isBlock = isBlockElement(tag)
        if isBlock {
            text.append("\n\n")
        }

        for child in node.children {
            assembleNode(child, html: &html, text: &text)
        }

        if preserve {
            html.append("</\(tag)>")
        }

        if isBlock {
            text.append("\n\n")
        }
    }

    // MARK: - Attributes

    /// Appends only content-relevant attributes for the given tag.
    private static func appendAttributes(for node: DOMNode, tag: String, html: inout String) {
        if tag == "a", let href = node.href {
            html.append(" href=\"\(HTMLUtilities.escapeAttribute(href))\"")
        }
    }

    /// Assembles an `<img>` tag with src and alt attributes.
    private static func assembleImage(_ node: DOMNode, html: inout String) {
        guard let src = node.src else { return }
        html.append("<img src=\"\(HTMLUtilities.escapeAttribute(src))\"")
        if let alt = node.alt {
            html.append(" alt=\"\(HTMLUtilities.escapeAttribute(alt))\"")
        }
        html.append(">")
    }

    // MARK: - Helpers

    private static let blockElements: Set<String> = [
        "p", "h1", "h2", "h3", "h4", "h5", "h6",
        "blockquote", "pre", "ul", "ol", "li",
        "figure", "figcaption", "hr",
        "table", "thead", "tbody", "tr",
        "article", "section", "div",
    ]

    private static func isBlockElement(_ tag: String) -> Bool {
        blockElements.contains(tag)
    }

    /// Normalizes whitespace while preserving paragraph structure.
    /// Collapses horizontal whitespace to single spaces and limits consecutive
    /// newlines to double (paragraph breaks), keeping text readable for AI context.
    private static func collapseWhitespace(_ text: String) -> String {
        text.replacing(/[ \t]+/, with: " ")
            .replacing(/\n{3,}/, with: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
