import Testing
import Foundation
@testable import RSSApp

@Suite("HTMLUtilities.extractAtomAlternateURL")
struct HTMLUtilitiesAtomAlternateTests {

    private let baseURL = URL(string: "https://example.com/")!

    @Test("Extracts Atom alternate link with rel before type before href")
    func extractsStandardOrder() {
        let html = """
            <html><head>
              <link rel="alternate" type="application/atom+xml" href="https://example.com/atom.xml" />
            </head></html>
            """
        let result = HTMLUtilities.extractAtomAlternateURL(from: html, baseURL: baseURL)
        #expect(result?.absoluteString == "https://example.com/atom.xml")
    }

    @Test("Extracts Atom alternate link with href before rel before type")
    func extractsReversedOrder() {
        let html = """
            <html><head>
              <link href="https://example.com/atom.xml" rel="alternate" type="application/atom+xml" />
            </head></html>
            """
        let result = HTMLUtilities.extractAtomAlternateURL(from: html, baseURL: baseURL)
        #expect(result?.absoluteString == "https://example.com/atom.xml")
    }

    @Test("Ignores RSS alternates (application/rss+xml)")
    func ignoresRSSAlternates() {
        let html = """
            <html><head>
              <link rel="alternate" type="application/rss+xml" href="https://example.com/rss.xml" />
            </head></html>
            """
        let result = HTMLUtilities.extractAtomAlternateURL(from: html, baseURL: baseURL)
        #expect(result == nil)
    }

    @Test("Ignores rel=alternate without Atom type")
    func ignoresAlternateWithoutAtomType() {
        let html = """
            <html><head>
              <link rel="alternate" type="text/html" href="https://example.com/page" />
            </head></html>
            """
        let result = HTMLUtilities.extractAtomAlternateURL(from: html, baseURL: baseURL)
        #expect(result == nil)
    }

    @Test("Ignores Atom type link when rel is not alternate")
    func ignoresNonAlternateAtomLink() {
        // <link rel="self" type="application/atom+xml"> describes the page's own
        // feed endpoint and should NOT be treated as an alternate offering.
        let html = """
            <html><head>
              <link rel="self" type="application/atom+xml" href="https://example.com/atom.xml" />
            </head></html>
            """
        let result = HTMLUtilities.extractAtomAlternateURL(from: html, baseURL: baseURL)
        #expect(result == nil)
    }

    @Test("Resolves relative hrefs against base URL")
    func resolvesRelativeHref() {
        let html = """
            <link rel="alternate" type="application/atom+xml" href="/blog/atom.xml" />
            """
        let base = URL(string: "https://example.com/some/path/")!
        let result = HTMLUtilities.extractAtomAlternateURL(from: html, baseURL: base)
        #expect(result?.absoluteString == "https://example.com/blog/atom.xml")
    }

    @Test("Returns first match when multiple Atom alternates exist")
    func returnsFirstMatch() {
        let html = """
            <html><head>
              <link rel="alternate" type="application/atom+xml" href="https://example.com/category/tech.atom" />
              <link rel="alternate" type="application/atom+xml" href="https://example.com/atom.xml" />
            </head></html>
            """
        let result = HTMLUtilities.extractAtomAlternateURL(from: html, baseURL: baseURL)
        #expect(result?.absoluteString == "https://example.com/category/tech.atom")
    }

    @Test("Handles compound rel values like 'alternate stylesheet'")
    func handlesCompoundRel() {
        let html = """
            <link rel="alternate stylesheet" type="application/atom+xml" href="https://example.com/atom.xml" />
            """
        let result = HTMLUtilities.extractAtomAlternateURL(from: html, baseURL: baseURL)
        // A rel token list that includes "alternate" qualifies, even if other
        // tokens are also present.
        #expect(result?.absoluteString == "https://example.com/atom.xml")
    }

    @Test("Returns nil when no <link> tags present")
    func returnsNilWhenNoLinks() {
        let html = "<html><head><title>No Links</title></head><body><p>Hello</p></body></html>"
        let result = HTMLUtilities.extractAtomAlternateURL(from: html, baseURL: baseURL)
        #expect(result == nil)
    }

    @Test("Matches mixed-case rel and type attributes")
    func matchesCaseInsensitively() {
        let html = """
            <LINK REL="Alternate" TYPE="Application/Atom+XML" HREF="https://example.com/atom.xml" />
            """
        let result = HTMLUtilities.extractAtomAlternateURL(from: html, baseURL: baseURL)
        #expect(result?.absoluteString == "https://example.com/atom.xml")
    }
}
