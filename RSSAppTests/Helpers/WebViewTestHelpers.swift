import Foundation
import WebKit

@testable import RSSApp

/// Anchor class for `Bundle(for:)` to locate test resources.
final class TestBundleToken {}

enum WebViewTestError: Error {
    case scriptNotFound
    case fixtureNotFound
    case noResult
}

/// Loads the domSerializer.js source from the test or main bundle.
func loadSerializerScript() throws -> String {
    let bundle = Bundle(for: TestBundleToken.self)
    if let path = bundle.path(forResource: "domSerializer", ofType: "js") {
        return try String(contentsOfFile: path, encoding: .utf8)
    }
    guard let url = Bundle.main.url(forResource: "domSerializer", withExtension: "js") else {
        throw WebViewTestError.scriptNotFound
    }
    return try String(contentsOf: url, encoding: .utf8)
}

/// Loads the simple-blog.html fixture from the test bundle.
func loadFixtureHTML(name: String = "simple-blog") throws -> String {
    let bundle = Bundle(for: TestBundleToken.self)
    guard let url = bundle.url(forResource: name, withExtension: "html") else {
        throw WebViewTestError.fixtureNotFound
    }
    return try String(contentsOf: url, encoding: .utf8)
}

/// Serializes HTML in a WKWebView using the domSerializer.js script.
@MainActor
func serializeInWebView(html: String, script: String) async throws -> SerializedDOM {
    let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 375, height: 812))
    let delegate = TestNavigationDelegate()
    webView.navigationDelegate = delegate

    webView.loadHTMLString(html, baseURL: URL(string: "https://example.com"))
    try await delegate.waitForLoad()

    guard let jsonString = try await webView.evaluateJavaScript(script) as? String else {
        throw WebViewTestError.noResult
    }

    return try JSONDecoder().decode(SerializedDOM.self, from: Data(jsonString.utf8))
}

/// Simple navigation delegate that exposes a continuation-based `waitForLoad()`.
@MainActor
final class TestNavigationDelegate: NSObject, WKNavigationDelegate {
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
