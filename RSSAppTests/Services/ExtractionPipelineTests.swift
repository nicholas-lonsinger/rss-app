import Testing
import WebKit

@testable import RSSApp

@Suite("Extraction Pipeline Tests")
@MainActor
struct ExtractionPipelineTests {

    /// Full end-to-end test: load fixture HTML → serialize via WKWebView → extract in Swift.
    @Test func fullPipelineWithSimpleBlogFixture() async throws {
        let html = try loadFixtureHTML()
        let script = try loadSerializerScript()
        let dom = try await serializeInWebView(html: html, script: script)

        let extractor = ContentExtractor()
        let content = extractor.extract(from: dom)

        #expect(content != nil)

        // Title should come from og:title meta tag
        #expect(content?.title == "Understanding Swift Concurrency")

        // Byline from article:author meta tag
        #expect(content?.byline == "Jane Smith")

        // Article text should be present
        #expect(content?.textContent.contains("async/await") == true)
        #expect(content?.textContent.contains("actors") == true)
        #expect(content?.textContent.contains("structured concurrency") == true)

        // Boilerplate should be excluded
        #expect(content?.textContent.contains("Privacy Policy") != true)
        #expect(content?.textContent.contains("Related Posts") != true)

        // HTML should contain semantic tags
        #expect(content?.htmlContent.contains("<p>") == true)
    }

    @Test func serializerProducesValidJSON() async throws {
        let html = try loadFixtureHTML()
        let script = try loadSerializerScript()
        let dom = try await serializeInWebView(html: html, script: script)

        #expect(dom.title == "Understanding Swift Concurrency - Tech Blog")
        #expect(dom.lang == "en")
        #expect(dom.body.tagName == "body")
        #expect(!dom.body.children.isEmpty)
    }

    @Test func serializerCapturesMetaTags() async throws {
        let html = try loadFixtureHTML()
        let script = try loadSerializerScript()
        let dom = try await serializeInWebView(html: html, script: script)

        #expect(dom.meta?["og:title"] == "Understanding Swift Concurrency")
        #expect(dom.meta?["article:author"] == "Jane Smith")
        #expect(dom.meta?["author"] == "Jane Smith")
    }

    // MARK: - Infrastructure

    private func loadFixtureHTML() throws -> String {
        let bundle = Bundle(for: BundleToken.self)
        guard let url = bundle.url(forResource: "simple-blog", withExtension: "html") else {
            throw PipelineTestError.fixtureNotFound
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func loadSerializerScript() throws -> String {
        let bundle = Bundle(for: BundleToken.self)
        if let path = bundle.path(forResource: "domSerializer", ofType: "js") {
            return try String(contentsOfFile: path, encoding: .utf8)
        }
        guard let url = Bundle.main.url(forResource: "domSerializer", withExtension: "js") else {
            throw PipelineTestError.scriptNotFound
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func serializeInWebView(html: String, script: String) async throws -> SerializedDOM {
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 375, height: 812))
        let delegate = NavigationDelegate()
        webView.navigationDelegate = delegate

        webView.loadHTMLString(html, baseURL: URL(string: "https://example.com"))
        try await delegate.waitForLoad()

        guard let jsonString = try await webView.evaluateJavaScript(script) as? String else {
            throw PipelineTestError.noResult
        }

        return try JSONDecoder().decode(SerializedDOM.self, from: Data(jsonString.utf8))
    }
}

// MARK: - Test Infrastructure

private final class BundleToken {}

private enum PipelineTestError: Error {
    case fixtureNotFound
    case scriptNotFound
    case noResult
}

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
