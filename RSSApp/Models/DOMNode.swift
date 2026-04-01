import Foundation

// MARK: - Serialized DOM

/// Top-level representation of a serialized web page DOM, produced by domSerializer.js.
struct SerializedDOM: Codable, Sendable {
    /// `document.title`
    let title: String
    /// `window.location.href`
    let url: String
    /// `<html lang="...">`
    let lang: String?
    /// Key OpenGraph/article meta tags (e.g., `og:title`, `article:author`).
    let meta: [String: String]?
    /// Serialized `<body>` element tree.
    let body: DOMNode
}

// MARK: - DOM Node

/// A single node in the serialized DOM tree.
///
/// Property names are intentionally short (`t`, `cls`, `c`, `txt`) to minimize
/// JSON payload size when serializing large DOM trees.
struct DOMNode: Codable, Sendable {
    /// Tag name (lowercase) for elements, or `"#text"` for text nodes.
    let t: String
    /// Element `id` attribute. `nil` when absent or empty.
    let id: String?
    /// Element `className` string. `nil` when absent or empty.
    let cls: String?
    /// ARIA `role` attribute. `nil` when absent.
    let role: String?
    /// `href` attribute (captured on `<a>` elements only).
    let href: String?
    /// `src` attribute (captured on `<img>` elements only).
    let src: String?
    /// `alt` attribute (captured on `<img>` elements only).
    let alt: String?
    /// Direct text content. For `#text` nodes this is the text value;
    /// for elements it is `nil` (text lives in child `#text` nodes).
    let txt: String?
    /// `false` when the element is hidden (`display:none`, `visibility:hidden`,
    /// or `aria-hidden="true"`). `nil` (omitted in JSON) means visible.
    let vis: Bool?
    /// Child nodes. `nil` (omitted in JSON) means no children.
    let c: [DOMNode]?
}

// MARK: - Convenience Accessors

extension DOMNode {
    /// The tag name of this node (e.g., `"div"`, `"p"`, `"#text"`).
    var tagName: String { t }

    /// Whether this is a text node (`#text`).
    var isText: Bool { t == "#text" }

    /// Whether this node is visible. Hidden nodes have `vis == false`.
    var isVisible: Bool { vis ?? true }

    /// Child nodes, defaulting to an empty array.
    var children: [DOMNode] { c ?? [] }

    /// The `className` string, defaulting to empty.
    var className: String { cls ?? "" }

    /// The `id` attribute, defaulting to empty.
    var identifier: String { id ?? "" }
}

// MARK: - Computed Text Properties

extension DOMNode {
    /// Recursively collects all text content from this node and its descendants.
    var textContent: String {
        if isText {
            return txt ?? ""
        }
        return children.map(\.textContent).joined()
    }

    /// Total character count of the recursive text content.
    /// Counts directly without building the full string.
    var textLength: Int {
        if isText { return (txt ?? "").count }
        return children.reduce(0) { $0 + $1.textLength }
    }

    /// Ratio of text inside `<a>` descendants to total text.
    ///
    /// A high link density (close to 1.0) indicates the node is primarily
    /// navigation or link-heavy boilerplate rather than article content.
    var linkDensity: Double {
        let total = Double(textLength)
        guard total > 0 else { return 0 }
        let linkText = Double(linkTextLength)
        return linkText / total
    }

    /// Number of commas in the recursive text content.
    /// Counts directly without building the full string.
    var commaCount: Int {
        if isText { return (txt ?? "").filter { $0 == "," }.count }
        return children.reduce(0) { $0 + $1.commaCount }
    }

    /// Depth-first search for the first descendant node matching a predicate.
    func findFirst(where predicate: (DOMNode) -> Bool) -> DOMNode? {
        if predicate(self) { return self }
        for child in children {
            if let found = child.findFirst(where: predicate) { return found }
        }
        return nil
    }

    /// Total character count of text inside `<a>` descendant nodes.
    private var linkTextLength: Int {
        if isText {
            return 0
        }
        if tagName == "a" {
            return textLength
        }
        return children.reduce(0) { $0 + $1.linkTextLength }
    }
}
