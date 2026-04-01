@testable import RSSApp

/// Shared factory functions for creating DOMNode test fixtures.
enum DOMNodeFactory {

    static func makeTextNode(_ text: String) -> DOMNode {
        DOMNode(t: "#text", id: nil, cls: nil, role: nil, href: nil, src: nil, alt: nil, txt: text, vis: nil, c: nil)
    }

    static func makeParagraph(_ text: String) -> DOMNode {
        DOMNode(
            t: "p", id: nil, cls: nil, role: nil, href: nil, src: nil, alt: nil, txt: nil, vis: nil,
            c: [makeTextNode(text)]
        )
    }

    static func makeLink(_ text: String, href: String = "https://example.com") -> DOMNode {
        DOMNode(
            t: "a", id: nil, cls: nil, role: nil, href: href, src: nil, alt: nil, txt: nil, vis: nil,
            c: [makeTextNode(text)]
        )
    }

    static func makeH1(_ text: String) -> DOMNode {
        DOMNode(
            t: "h1", id: nil, cls: nil, role: nil, href: nil, src: nil, alt: nil, txt: nil, vis: nil,
            c: [makeTextNode(text)]
        )
    }

    static func makeBody(_ children: [DOMNode]) -> DOMNode {
        DOMNode(t: "body", id: nil, cls: nil, role: nil, href: nil, src: nil, alt: nil, txt: nil, vis: nil, c: children)
    }
}
