import Testing
import WebKit

@testable import RSSApp

@Suite("DOM Serializer Tests")
@MainActor
struct DOMSerializerTests {

    private func serialize(html: String) async throws -> SerializedDOM {
        let script = try loadSerializerScript()
        return try await serializeInWebView(html: html, script: script)
    }

    // MARK: - Tests

    @Test func serializesSimpleBlogFixture() async throws {
        let html = try loadFixtureHTML()
        let dom = try await serialize(html: html)

        #expect(dom.title == "Understanding Swift Concurrency - Tech Blog")
        #expect(dom.lang == "en")
    }

    @Test func extractsMetaTags() async throws {
        let html = try loadFixtureHTML()
        let dom = try await serialize(html: html)

        #expect(dom.meta?["og:title"] == "Understanding Swift Concurrency")
        #expect(dom.meta?["article:author"] == "Jane Smith")
        #expect(dom.meta?["author"] == "Jane Smith")
    }

    @Test func bodyHasChildren() async throws {
        let html = try loadFixtureHTML()
        let dom = try await serialize(html: html)

        #expect(dom.body.tagName == "body")
        #expect(!dom.body.children.isEmpty)
    }

    @Test func skipsScriptAndStyleTags() async throws {
        let html = """
        <html><head><title>Test</title></head>
        <body>
            <script>var x = 1;</script>
            <style>.foo { color: red; }</style>
            <p>Visible content</p>
        </body></html>
        """
        let dom = try await serialize(html: html)

        #expect(dom.body.findFirst(where: { $0.tagName == "script" }) == nil)
        #expect(dom.body.findFirst(where: { $0.tagName == "style" }) == nil)
    }

    @Test func capturesTextNodes() async throws {
        let html = """
        <html><head><title>Test</title></head>
        <body><p>Hello world</p></body></html>
        """
        let dom = try await serialize(html: html)

        let paragraph = dom.body.findFirst(where: { $0.tagName == "p" })
        #expect(paragraph != nil)
        #expect(paragraph?.textContent.contains("Hello world") == true)
    }

    @Test func capturesLinkHref() async throws {
        let html = """
        <html><head><title>Test</title></head>
        <body><a href="https://example.com/page">Click me</a></body></html>
        """
        let dom = try await serialize(html: html)

        let link = dom.body.findFirst(where: { $0.tagName == "a" })
        #expect(link?.href == "https://example.com/page")
        #expect(link?.textContent.contains("Click me") == true)
    }

    @Test func capturesImageAttributes() async throws {
        let html = """
        <html><head><title>Test</title></head>
        <body><img src="photo.jpg" alt="A photo"></body></html>
        """
        let dom = try await serialize(html: html)

        let img = dom.body.findFirst(where: { $0.tagName == "img" })
        #expect(img?.src == "photo.jpg")
        #expect(img?.alt == "A photo")
    }

    @Test func flagsHiddenElements() async throws {
        let html = """
        <html><head><title>Test</title></head>
        <body>
            <div style="display:none" id="hidden-div"><p>Hidden</p></div>
            <p>Visible</p>
        </body></html>
        """
        let dom = try await serialize(html: html)

        let hiddenDiv = dom.body.findFirst(where: { $0.identifier == "hidden-div" })
        #expect(hiddenDiv?.isVisible == false)
    }

    @Test func capturesIdAndClassName() async throws {
        let html = """
        <html><head><title>Test</title></head>
        <body><div id="main" class="container wide">Content</div></body></html>
        """
        let dom = try await serialize(html: html)

        let div = dom.body.findFirst(where: { $0.identifier == "main" })
        #expect(div?.className == "container wide")
    }

    @Test func capturesAriaRole() async throws {
        let html = """
        <html><head><title>Test</title></head>
        <body><nav role="navigation"><a href="/">Home</a></nav></body></html>
        """
        let dom = try await serialize(html: html)

        let nav = dom.body.findFirst(where: { $0.role == "navigation" })
        #expect(nav != nil)
        #expect(nav?.tagName == "nav")
    }
}
