import Testing
import WebKit

@testable import RSSApp

@Suite("DOM Serializer Tests")
@MainActor
struct DOMSerializerTests {

    /// Loads the domSerializer.js source from the app bundle.
    private func loadSerializerScript() throws -> String {
        let bundlePath = Bundle(for: BundleToken.self).path(
            forResource: "domSerializer", ofType: "js"
        )
        guard let path = bundlePath else {
            // Fall back to the main bundle in case resources are merged there.
            guard let url = Bundle.main.url(forResource: "domSerializer", withExtension: "js") else {
                throw SerializerTestError.scriptNotFound
            }
            return try String(contentsOf: url, encoding: .utf8)
        }
        return try String(contentsOfFile: path, encoding: .utf8)
    }

    /// Loads the simple-blog.html fixture from the test bundle.
    private func loadFixtureHTML() throws -> String {
        let bundle = Bundle(for: BundleToken.self)
        guard let url = bundle.url(forResource: "simple-blog", withExtension: "html") else {
            throw SerializerTestError.fixtureNotFound
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// Runs the serializer on the given HTML and returns the decoded SerializedDOM.
    private func serialize(html: String) async throws -> SerializedDOM {
        let script = try loadSerializerScript()

        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 375, height: 812), configuration: config)

        // Load HTML and wait for completion via continuation.
        let delegate = NavigationDelegate()
        webView.navigationDelegate = delegate

        webView.loadHTMLString(html, baseURL: URL(string: "https://example.com"))
        try await delegate.waitForLoad()

        // Run the serializer script.
        guard let jsonString = try await webView.evaluateJavaScript(script) as? String else {
            throw SerializerTestError.noResult
        }

        return try JSONDecoder().decode(SerializedDOM.self, from: Data(jsonString.utf8))
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

        // Walk all nodes — none should be script or style
        func hasTag(_ node: DOMNode, _ tag: String) -> Bool {
            if node.tagName == tag { return true }
            return node.children.contains { hasTag($0, tag) }
        }
        #expect(!hasTag(dom.body, "script"))
        #expect(!hasTag(dom.body, "style"))
    }

    @Test func capturesTextNodes() async throws {
        let html = """
        <html><head><title>Test</title></head>
        <body><p>Hello world</p></body></html>
        """
        let dom = try await serialize(html: html)

        // Find the paragraph
        let paragraph = findFirst(in: dom.body) { $0.tagName == "p" }
        #expect(paragraph != nil)
        #expect(paragraph?.textContent.contains("Hello world") == true)
    }

    @Test func capturesLinkHref() async throws {
        let html = """
        <html><head><title>Test</title></head>
        <body><a href="https://example.com/page">Click me</a></body></html>
        """
        let dom = try await serialize(html: html)

        let link = findFirst(in: dom.body) { $0.tagName == "a" }
        #expect(link?.href == "https://example.com/page")
        #expect(link?.textContent.contains("Click me") == true)
    }

    @Test func capturesImageAttributes() async throws {
        let html = """
        <html><head><title>Test</title></head>
        <body><img src="photo.jpg" alt="A photo"></body></html>
        """
        let dom = try await serialize(html: html)

        let img = findFirst(in: dom.body) { $0.tagName == "img" }
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

        let hiddenDiv = findFirst(in: dom.body) { $0.identifier == "hidden-div" }
        #expect(hiddenDiv?.isVisible == false)
    }

    @Test func capturesIdAndClassName() async throws {
        let html = """
        <html><head><title>Test</title></head>
        <body><div id="main" class="container wide">Content</div></body></html>
        """
        let dom = try await serialize(html: html)

        let div = findFirst(in: dom.body) { $0.identifier == "main" }
        #expect(div?.className == "container wide")
    }

    @Test func capturesAriaRole() async throws {
        let html = """
        <html><head><title>Test</title></head>
        <body><nav role="navigation"><a href="/">Home</a></nav></body></html>
        """
        let dom = try await serialize(html: html)

        let nav = findFirst(in: dom.body) { $0.role == "navigation" }
        #expect(nav != nil)
        #expect(nav?.tagName == "nav")
    }

    // MARK: - Tree Helpers

    /// Depth-first search for the first node matching a predicate.
    private func findFirst(in node: DOMNode, where predicate: (DOMNode) -> Bool) -> DOMNode? {
        if predicate(node) { return node }
        for child in node.children {
            if let found = findFirst(in: child, where: predicate) { return found }
        }
        return nil
    }
}

// MARK: - Test Infrastructure

/// Anchor class for `Bundle(for:)` to locate test resources.
private final class BundleToken {}

private enum SerializerTestError: Error {
    case scriptNotFound
    case fixtureNotFound
    case noResult
}

/// Simple navigation delegate that exposes a continuation-based `waitForLoad()`.
@MainActor
private final class NavigationDelegate: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Error>?

    func waitForLoad() async throws {
        try await withCheckedThrowingContinuation { cont in
            self.continuation = cont
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        continuation?.resume()
        continuation = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }

    func webView(
        _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error
    ) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}
