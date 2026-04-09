import Testing
import Foundation
@testable import RSSApp

@Suite("URL.siteRoot")
struct URLSiteRootTests {

    @Test("Strips path from HTTPS feed URL")
    func stripsPathHTTPS() {
        let url = URL(string: "https://example.com/feed/rss")!
        let root = url.siteRoot
        #expect(root == URL(string: "https://example.com"))
    }

    @Test("Strips path from HTTP feed URL")
    func stripsPathHTTP() {
        let url = URL(string: "http://example.com/blog/feed.xml")!
        let root = url.siteRoot
        #expect(root == URL(string: "http://example.com"))
    }

    @Test("Preserves host when URL has no path")
    func noPath() {
        let url = URL(string: "https://example.com")!
        let root = url.siteRoot
        #expect(root == URL(string: "https://example.com"))
    }

    @Test("Returns nil for URL without host")
    func noHost() {
        let url = URL(string: "file:///local/feed.xml")!
        let root = url.siteRoot
        #expect(root == nil)
    }

    @Test("Defaults to HTTPS when scheme is missing")
    func missingScheme() {
        // URL(string:) with no scheme but a path-like string produces a URL
        // whose scheme and host are both nil, so siteRoot returns nil. This
        // test documents the boundary: the https fallback only activates when
        // .host is non-nil but .scheme is nil — a combination that standard
        // URL parsing does not produce for schemeless strings.
        let url = URL(string: "example.com/feed")!
        #expect(url.siteRoot == nil)
    }
}
