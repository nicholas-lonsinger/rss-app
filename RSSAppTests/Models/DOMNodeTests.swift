import Foundation
import Testing

@testable import RSSApp

@Suite("DOMNode Model Tests")
struct DOMNodeTests {

    // MARK: - Convenience Accessors

    @Test func textNodeIsText() {
        let node = DOMNode(t: "#text", id: nil, cls: nil, role: nil, href: nil, src: nil, alt: nil, txt: "hello", vis: nil, c: nil)
        #expect(node.isText)
        #expect(node.tagName == "#text")
    }

    @Test func elementNodeIsNotText() {
        let node = makeParagraph("content")
        #expect(!node.isText)
        #expect(node.tagName == "p")
    }

    @Test func visibilityDefaultsToTrue() {
        let visible = DOMNode(t: "div", id: nil, cls: nil, role: nil, href: nil, src: nil, alt: nil, txt: nil, vis: nil, c: nil)
        #expect(visible.isVisible)

        let hidden = DOMNode(t: "div", id: nil, cls: nil, role: nil, href: nil, src: nil, alt: nil, txt: nil, vis: false, c: nil)
        #expect(!hidden.isVisible)
    }

    @Test func childrenDefaultsToEmptyArray() {
        let node = DOMNode(t: "div", id: nil, cls: nil, role: nil, href: nil, src: nil, alt: nil, txt: nil, vis: nil, c: nil)
        #expect(node.children.isEmpty)
    }

    @Test func classNameAndIdentifierDefaults() {
        let node = DOMNode(t: "div", id: nil, cls: nil, role: nil, href: nil, src: nil, alt: nil, txt: nil, vis: nil, c: nil)
        #expect(node.className == "")
        #expect(node.identifier == "")

        let withValues = DOMNode(t: "div", id: "main", cls: "container wide", role: nil, href: nil, src: nil, alt: nil, txt: nil, vis: nil, c: nil)
        #expect(withValues.className == "container wide")
        #expect(withValues.identifier == "main")
    }

    // MARK: - Text Content

    @Test func textContentFromTextNode() {
        let node = makeTextNode("Hello, world!")
        #expect(node.textContent == "Hello, world!")
    }

    @Test func textContentFromElement() {
        let node = makeParagraph("Hello, world!")
        #expect(node.textContent == "Hello, world!")
    }

    @Test func textContentRecursive() {
        // <div><p>Hello, </p><p>world!</p></div>
        let div = DOMNode(
            t: "div", id: nil, cls: nil, role: nil, href: nil, src: nil, alt: nil, txt: nil, vis: nil,
            c: [
                makeParagraph("Hello, "),
                makeParagraph("world!"),
            ]
        )
        #expect(div.textContent == "Hello, world!")
    }

    @Test func textContentFromEmptyNode() {
        let node = DOMNode(t: "div", id: nil, cls: nil, role: nil, href: nil, src: nil, alt: nil, txt: nil, vis: nil, c: nil)
        #expect(node.textContent == "")
    }

    @Test func textLength() {
        let node = makeParagraph("12345")
        #expect(node.textLength == 5)
    }

    // MARK: - Link Density

    @Test func linkDensityWithNoLinks() {
        let node = makeParagraph("No links here at all.")
        #expect(node.linkDensity == 0)
    }

    @Test func linkDensityWithAllLinks() {
        // <p><a>all link text</a></p>
        let link = makeLink("all link text")
        let p = DOMNode(t: "p", id: nil, cls: nil, role: nil, href: nil, src: nil, alt: nil, txt: nil, vis: nil, c: [link])
        #expect(p.linkDensity == 1.0)
    }

    @Test func linkDensityPartial() {
        // <p>Normal text <a>link</a></p> => link is 4 chars out of 16
        let textNode = makeTextNode("Normal text ")
        let link = makeLink("link")
        let p = DOMNode(t: "p", id: nil, cls: nil, role: nil, href: nil, src: nil, alt: nil, txt: nil, vis: nil, c: [textNode, link])
        let expected = 4.0 / 16.0
        #expect(abs(p.linkDensity - expected) < 0.001)
    }

    @Test func linkDensityEmptyNode() {
        let node = DOMNode(t: "div", id: nil, cls: nil, role: nil, href: nil, src: nil, alt: nil, txt: nil, vis: nil, c: nil)
        #expect(node.linkDensity == 0)
    }

    // MARK: - Comma Count

    @Test func commaCountInProse() {
        let node = makeParagraph("First, second, and third, too.")
        #expect(node.commaCount == 3)
    }

    @Test func commaCountZero() {
        let node = makeParagraph("No commas here")
        #expect(node.commaCount == 0)
    }

    @Test func commaCountRecursive() {
        // <div><p>one, two</p><p>three, four, five</p></div>
        let div = DOMNode(
            t: "div", id: nil, cls: nil, role: nil, href: nil, src: nil, alt: nil, txt: nil, vis: nil,
            c: [
                makeParagraph("one, two"),
                makeParagraph("three, four, five"),
            ]
        )
        #expect(div.commaCount == 3)
    }

    // MARK: - Codable Round-Trip

    @Test func codableRoundTrip() throws {
        let original = SerializedDOM(
            title: "Test Page",
            url: "https://example.com",
            lang: "en",
            meta: ["og:title": "Test"],
            body: DOMNode(
                t: "body", id: nil, cls: nil, role: nil, href: nil, src: nil, alt: nil, txt: nil, vis: nil,
                c: [makeParagraph("Hello")]
            )
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SerializedDOM.self, from: data)

        #expect(decoded.title == "Test Page")
        #expect(decoded.url == "https://example.com")
        #expect(decoded.lang == "en")
        #expect(decoded.meta?["og:title"] == "Test")
        #expect(decoded.body.children.count == 1)
        #expect(decoded.body.children[0].textContent == "Hello")
    }

    @Test func decodesMinimalJSON() throws {
        // Simulates the compact JSON from domSerializer.js with omitted fields
        let json = """
        {"t":"div","c":[{"t":"#text","txt":"content"}]}
        """
        let node = try JSONDecoder().decode(DOMNode.self, from: Data(json.utf8))
        #expect(node.tagName == "div")
        #expect(node.id == nil)
        #expect(node.cls == nil)
        #expect(node.children.count == 1)
        #expect(node.textContent == "content")
    }

    // MARK: - Helpers

    private func makeTextNode(_ text: String) -> DOMNode {
        DOMNode(t: "#text", id: nil, cls: nil, role: nil, href: nil, src: nil, alt: nil, txt: text, vis: nil, c: nil)
    }

    private func makeParagraph(_ text: String) -> DOMNode {
        DOMNode(
            t: "p", id: nil, cls: nil, role: nil, href: nil, src: nil, alt: nil, txt: nil, vis: nil,
            c: [makeTextNode(text)]
        )
    }

    private func makeLink(_ text: String) -> DOMNode {
        DOMNode(
            t: "a", id: nil, cls: nil, role: nil, href: "https://example.com", src: nil, alt: nil, txt: nil, vis: nil,
            c: [makeTextNode(text)]
        )
    }
}
