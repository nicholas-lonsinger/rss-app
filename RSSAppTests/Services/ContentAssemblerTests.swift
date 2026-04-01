import Testing

@testable import RSSApp

@Suite("ContentAssembler Tests")
struct ContentAssemblerTests {

    // MARK: - Text Output

    @Test func assemblesPlainTextFromParagraphs() {
        let node = DOMNodeFactory.makeBody([
            DOMNodeFactory.makeParagraph("First paragraph."),
            DOMNodeFactory.makeParagraph("Second paragraph."),
        ])
        let (_, text) = ContentAssembler.assemble(from: node)
        #expect(text.contains("First paragraph."))
        #expect(text.contains("Second paragraph."))
    }

    @Test func preservesParagraphBreaks() {
        let node = DOMNodeFactory.makeBody([
            DOMNodeFactory.makeParagraph("Hello"),
            DOMNodeFactory.makeParagraph("World"),
        ])
        let (_, text) = ContentAssembler.assemble(from: node)
        // Block elements inject paragraph breaks that are preserved
        #expect(text.contains("Hello"))
        #expect(text.contains("World"))
        // But excessive newlines are collapsed to double
        #expect(!text.contains("\n\n\n"))
    }

    // MARK: - HTML Escaping

    @Test func escapesHTMLEntitiesInText() {
        let textNode = DOMNodeFactory.makeTextNode("1 < 2 & 3 > 0")
        let wrapper = DOMNodeFactory.makeBody([
            DOMNode(t: "p", id: nil, cls: nil, role: nil, href: nil, src: nil, alt: nil, txt: nil, vis: nil,
                    c: [textNode])
        ])
        let (html, _) = ContentAssembler.assemble(from: wrapper)
        #expect(html.contains("1 &lt; 2 &amp; 3 &gt; 0"))
    }

    // MARK: - Link Attributes

    @Test func preservesHrefOnLinks() {
        let link = DOMNode(
            t: "a", id: nil, cls: nil, role: nil, href: "https://example.com/page", src: nil, alt: nil, txt: nil, vis: nil,
            c: [DOMNodeFactory.makeTextNode("Click")]
        )
        let wrapper = DOMNodeFactory.makeBody([
            DOMNode(t: "p", id: nil, cls: nil, role: nil, href: nil, src: nil, alt: nil, txt: nil, vis: nil, c: [link])
        ])
        let (html, _) = ContentAssembler.assemble(from: wrapper)
        #expect(html.contains("<a href=\"https://example.com/page\">"))
        #expect(html.contains("Click"))
    }

    @Test func escapesAttributeValues() {
        let link = DOMNode(
            t: "a", id: nil, cls: nil, role: nil, href: "https://example.com/?a=1&b=\"2\"", src: nil, alt: nil, txt: nil, vis: nil,
            c: [DOMNodeFactory.makeTextNode("Link")]
        )
        let wrapper = DOMNodeFactory.makeBody([
            DOMNode(t: "p", id: nil, cls: nil, role: nil, href: nil, src: nil, alt: nil, txt: nil, vis: nil, c: [link])
        ])
        let (html, _) = ContentAssembler.assemble(from: wrapper)
        #expect(html.contains("&amp;"))
        #expect(html.contains("&quot;"))
    }

    // MARK: - Image Assembly

    @Test func assemblesImageWithSrcAndAlt() {
        let img = DOMNode(
            t: "img", id: nil, cls: nil, role: nil, href: nil, src: "photo.jpg", alt: "A photo", txt: nil, vis: nil, c: nil
        )
        let wrapper = DOMNodeFactory.makeBody([img])
        let (html, _) = ContentAssembler.assemble(from: wrapper)
        #expect(html.contains("<img src=\"photo.jpg\" alt=\"A photo\">"))
    }

    @Test func skipsImageWithoutSrc() {
        let img = DOMNode(
            t: "img", id: nil, cls: nil, role: nil, href: nil, src: nil, alt: "No src", txt: nil, vis: nil, c: nil
        )
        let wrapper = DOMNodeFactory.makeBody([img])
        let (html, _) = ContentAssembler.assemble(from: wrapper)
        #expect(!html.contains("<img"))
    }

    // MARK: - Hidden Elements

    @Test func skipsHiddenNodes() {
        let hidden = DOMNode(
            t: "div", id: nil, cls: nil, role: nil, href: nil, src: nil, alt: nil, txt: nil, vis: false,
            c: [DOMNodeFactory.makeParagraph("Hidden content")]
        )
        let visible = DOMNodeFactory.makeParagraph("Visible content")
        let wrapper = DOMNodeFactory.makeBody([hidden, visible])
        let (html, text) = ContentAssembler.assemble(from: wrapper)
        #expect(!html.contains("Hidden content"))
        #expect(!text.contains("Hidden content"))
        #expect(text.contains("Visible content"))
    }

    // MARK: - Self-Closing Tags

    @Test func emitsBrTag() {
        let br = DOMNode(t: "br", id: nil, cls: nil, role: nil, href: nil, src: nil, alt: nil, txt: nil, vis: nil, c: nil)
        let wrapper = DOMNodeFactory.makeBody([br])
        let (html, _) = ContentAssembler.assemble(from: wrapper)
        #expect(html.contains("<br>"))
    }

    @Test func emitsHrTag() {
        let hr = DOMNode(t: "hr", id: nil, cls: nil, role: nil, href: nil, src: nil, alt: nil, txt: nil, vis: nil, c: nil)
        let wrapper = DOMNodeFactory.makeBody([hr])
        let (html, _) = ContentAssembler.assemble(from: wrapper)
        #expect(html.contains("<hr>"))
    }

    // MARK: - Tag Preservation

    @Test func stripsNonPreservedTags() {
        // <span> is not in preservedTags — text passes through but no <span> tag in output
        let span = DOMNode(
            t: "span", id: nil, cls: nil, role: nil, href: nil, src: nil, alt: nil, txt: nil, vis: nil,
            c: [DOMNodeFactory.makeTextNode("Inside span")]
        )
        let wrapper = DOMNodeFactory.makeBody([span])
        let (html, text) = ContentAssembler.assemble(from: wrapper)
        #expect(!html.contains("<span>"))
        #expect(text.contains("Inside span"))
    }
}
