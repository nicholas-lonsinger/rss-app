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
        let node = DOMNodeFactory.makeParagraph("content")
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
        let node = DOMNodeFactory.makeTextNode("Hello, world!")
        #expect(node.textContent == "Hello, world!")
    }

    @Test func textContentFromElement() {
        let node = DOMNodeFactory.makeParagraph("Hello, world!")
        #expect(node.textContent == "Hello, world!")
    }

    @Test func textContentRecursive() {
        // <div><p>Hello, </p><p>world!</p></div>
        let div = DOMNode(
            t: "div", id: nil, cls: nil, role: nil, href: nil, src: nil, alt: nil, txt: nil, vis: nil,
            c: [
                DOMNodeFactory.makeParagraph("Hello, "),
                DOMNodeFactory.makeParagraph("world!"),
            ]
        )
        #expect(div.textContent == "Hello, world!")
    }

    @Test func textContentFromEmptyNode() {
        let node = DOMNode(t: "div", id: nil, cls: nil, role: nil, href: nil, src: nil, alt: nil, txt: nil, vis: nil, c: nil)
        #expect(node.textContent == "")
    }

    @Test func textLength() {
        let node = DOMNodeFactory.makeParagraph("12345")
        #expect(node.textLength == 5)
    }

    // MARK: - Link Density

    @Test func linkDensityWithNoLinks() {
        let node = DOMNodeFactory.makeParagraph("No links here at all.")
        #expect(node.linkDensity == 0)
    }

    @Test func linkDensityWithAllLinks() {
        // <p><a>all link text</a></p>
        let link = DOMNodeFactory.makeLink("all link text")
        let p = DOMNode(t: "p", id: nil, cls: nil, role: nil, href: nil, src: nil, alt: nil, txt: nil, vis: nil, c: [link])
        #expect(p.linkDensity == 1.0)
    }

    @Test func linkDensityPartial() {
        // <p>Normal text <a>link</a></p> => link is 4 chars out of 16
        let textNode = DOMNodeFactory.makeTextNode("Normal text ")
        let link = DOMNodeFactory.makeLink("link")
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
        let node = DOMNodeFactory.makeParagraph("First, second, and third, too.")
        #expect(node.commaCount == 3)
    }

    @Test func commaCountZero() {
        let node = DOMNodeFactory.makeParagraph("No commas here")
        #expect(node.commaCount == 0)
    }

    @Test func commaCountRecursive() {
        // <div><p>one, two</p><p>three, four, five</p></div>
        let div = DOMNode(
            t: "div", id: nil, cls: nil, role: nil, href: nil, src: nil, alt: nil, txt: nil, vis: nil,
            c: [
                DOMNodeFactory.makeParagraph("one, two"),
                DOMNodeFactory.makeParagraph("three, four, five"),
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
                c: [DOMNodeFactory.makeParagraph("Hello")]
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

    // MARK: - findFirst

    @Test func findFirstReturnsSelfWhenMatching() {
        let node = DOMNodeFactory.makeParagraph("hello")
        #expect(node.findFirst(where: { $0.tagName == "p" })?.tagName == "p")
    }

    @Test func findFirstFindsNestedNode() {
        let inner = DOMNodeFactory.makeParagraph("deep")
        let wrapper = DOMNode(
            t: "div", id: nil, cls: nil, role: nil, href: nil, src: nil, alt: nil, txt: nil, vis: nil,
            c: [DOMNode(t: "section", id: nil, cls: nil, role: nil, href: nil, src: nil, alt: nil, txt: nil, vis: nil, c: [inner])]
        )
        let found = wrapper.findFirst(where: { $0.tagName == "p" })
        #expect(found != nil)
        #expect(found?.textContent == "deep")
    }

    @Test func findFirstReturnsNilWhenNoMatch() {
        let node = DOMNodeFactory.makeParagraph("text")
        #expect(node.findFirst(where: { $0.tagName == "article" }) == nil)
    }

    @Test func findFirstReturnsDFSOrder() {
        // Two paragraphs — should find the first one
        let body = DOMNodeFactory.makeBody([
            DOMNodeFactory.makeParagraph("first"),
            DOMNodeFactory.makeParagraph("second"),
        ])
        let found = body.findFirst(where: { $0.tagName == "p" })
        #expect(found?.textContent == "first")
    }

    // MARK: - rssFallback

    @Test func rssFallbackPreservesHTMLAndStripsText() {
        let html = "<p>Some <b>bold</b> text</p>"
        let content = ArticleContent.rssFallback(html: html)
        #expect(content.title == "")
        #expect(content.byline == nil)
        #expect(content.htmlContent == html)
        #expect(content.textContent == "Some bold text")
    }

}
