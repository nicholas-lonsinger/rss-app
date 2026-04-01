import Testing

@testable import RSSApp

@Suite("ContentExtractor Tests")
struct ContentExtractorTests {

    private let extractor = ContentExtractor()

    // MARK: - Basic Extraction

    @Test func extractsContentFromSimpleArticlePage() {
        let dom = makeSimpleBlogDOM()
        let content = extractor.extract(from: dom)

        #expect(content != nil)
        #expect(content?.title == "Understanding Swift Concurrency")
        #expect(content?.byline == "Jane Smith")
        #expect(content?.textContent.contains("async/await") == true)
        #expect(content?.textContent.contains("actors") == true)
    }

    @Test func returnsNilForEmptyDOM() {
        let dom = SerializedDOM(
            title: "",
            url: "https://example.com",
            lang: nil,
            meta: nil,
            body: DOMNode(t: "body", id: nil, cls: nil, role: nil, href: nil, src: nil, alt: nil, txt: nil, vis: nil, c: nil)
        )
        let content = extractor.extract(from: dom)
        #expect(content == nil)
    }

    @Test func htmlContentContainsTags() {
        let dom = makeSimpleBlogDOM()
        let content = extractor.extract(from: dom)

        #expect(content?.htmlContent.contains("<p>") == true)
        #expect(content?.htmlContent.contains("</p>") == true)
    }

    // MARK: - Site-Specific Extractors

    @Test func siteSpecificExtractorTakesPriority() {
        let mockContent = ArticleContent(
            title: "Custom Title",
            byline: "Custom Author",
            htmlContent: "<p>Custom content</p>",
            textContent: "Custom content"
        )
        let siteExtractor = StubSiteExtractor(hostname: "example.com", content: mockContent)
        let extractorWithSite = ContentExtractor(siteExtractors: [siteExtractor])

        let dom = makeSimpleBlogDOM()
        let content = extractorWithSite.extract(from: dom)

        #expect(content?.title == "Custom Title")
        #expect(content?.textContent == "Custom content")
    }

    @Test func fallsBackToGenericWhenSiteExtractorReturnsNil() {
        let siteExtractor = StubSiteExtractor(hostname: "other-site.com", content: nil)
        let extractorWithSite = ContentExtractor(siteExtractors: [siteExtractor])

        let dom = makeSimpleBlogDOM()
        let content = extractorWithSite.extract(from: dom)

        // Should fall back to generic extraction
        #expect(content != nil)
        #expect(content?.title == "Understanding Swift Concurrency")
    }

    // MARK: - Boilerplate Stripping

    @Test func excludesNavigationContent() throws {
        let dom = makeSimpleBlogDOM()
        let content = try #require(extractor.extract(from: dom))

        #expect(!content.textContent.contains("Home"))
        #expect(!content.textContent.contains("Archive"))
    }

    @Test func excludesFooterContent() throws {
        let dom = makeSimpleBlogDOM()
        let content = try #require(extractor.extract(from: dom))

        #expect(!content.textContent.contains("All rights reserved"))
        #expect(!content.textContent.contains("Privacy Policy"))
    }

    @Test func excludesSidebarContent() throws {
        let dom = makeSimpleBlogDOM()
        let content = try #require(extractor.extract(from: dom))

        #expect(!content.textContent.contains("Related Posts"))
    }

    // MARK: - Helpers

    /// Builds a SerializedDOM matching the simple-blog.html fixture structure.
    private func makeSimpleBlogDOM() -> SerializedDOM {
        let longText = "Swift concurrency represents a fundamental shift in how we write asynchronous code on Apple platforms. With the introduction of async/await, actors, and structured concurrency, developers now have powerful tools to write safe, efficient concurrent code."

        let nav = DOMNode(
            t: "nav", id: nil, cls: nil, role: "navigation", href: nil, src: nil, alt: nil, txt: nil, vis: nil,
            c: [DOMNodeFactory.makeLink("Home"), DOMNodeFactory.makeLink("About"), DOMNodeFactory.makeLink("Archive")]
        )
        let header = DOMNode(
            t: "header", id: nil, cls: nil, role: nil, href: nil, src: nil, alt: nil, txt: nil, vis: nil,
            c: [nav]
        )

        let byline = DOMNode(
            t: "div", id: nil, cls: "byline", role: nil, href: nil, src: nil, alt: nil, txt: nil, vis: nil,
            c: [
                DOMNode(t: "span", id: nil, cls: "author", role: nil, href: nil, src: nil, alt: nil, txt: nil, vis: nil,
                        c: [DOMNodeFactory.makeTextNode("By Jane Smith")]),
            ]
        )

        let article = DOMNode(
            t: "article", id: nil, cls: nil, role: nil, href: nil, src: nil, alt: nil, txt: nil, vis: nil,
            c: [
                DOMNodeFactory.makeH1("Understanding Swift Concurrency"),
                byline,
                DOMNodeFactory.makeParagraph(longText),
                DOMNodeFactory.makeParagraph("Before Swift concurrency, developers relied heavily on completion handlers, delegate patterns, and Grand Central Dispatch. While these tools were powerful, they often led to complex, hard-to-read code with subtle bugs."),
                DOMNode(t: "h2", id: nil, cls: nil, role: nil, href: nil, src: nil, alt: nil, txt: nil, vis: nil,
                        c: [DOMNodeFactory.makeTextNode("Async/Await")]),
                DOMNodeFactory.makeParagraph("The async/await pattern is the foundation of Swift concurrency. An async function can suspend its execution at an await point, allowing the system to use that thread for other work."),
                DOMNodeFactory.makeParagraph("Consider a typical network request. With completion handlers, you might write nested callbacks that are difficult to follow. With async/await, the same code reads linearly."),
                DOMNode(t: "h2", id: nil, cls: nil, role: nil, href: nil, src: nil, alt: nil, txt: nil, vis: nil,
                        c: [DOMNodeFactory.makeTextNode("Actors")]),
                DOMNodeFactory.makeParagraph("Actors provide a way to protect mutable state from data races. An actor ensures that only one task can access its mutable state at a time, eliminating a whole class of concurrency bugs."),
            ]
        )

        let sidebar = DOMNode(
            t: "aside", id: nil, cls: "sidebar", role: nil, href: nil, src: nil, alt: nil, txt: nil, vis: nil,
            c: [
                DOMNode(t: "h3", id: nil, cls: nil, role: nil, href: nil, src: nil, alt: nil, txt: nil, vis: nil,
                        c: [DOMNodeFactory.makeTextNode("Related Posts")]),
                DOMNode(t: "ul", id: nil, cls: nil, role: nil, href: nil, src: nil, alt: nil, txt: nil, vis: nil,
                        c: [
                            DOMNode(t: "li", id: nil, cls: nil, role: nil, href: nil, src: nil, alt: nil, txt: nil, vis: nil,
                                    c: [DOMNodeFactory.makeLink("10 SwiftUI Tips")]),
                        ]),
            ]
        )

        let footer = DOMNode(
            t: "footer", id: nil, cls: "footer", role: nil, href: nil, src: nil, alt: nil, txt: nil, vis: nil,
            c: [
                DOMNodeFactory.makeParagraph("© 2025 Tech Blog. All rights reserved."),
                DOMNode(t: "nav", id: nil, cls: nil, role: nil, href: nil, src: nil, alt: nil, txt: nil, vis: nil,
                        c: [DOMNodeFactory.makeLink("Privacy Policy"), DOMNodeFactory.makeLink("Terms of Service")]),
            ]
        )

        return SerializedDOM(
            title: "Understanding Swift Concurrency - Tech Blog",
            url: "https://example.com/understanding-swift-concurrency",
            lang: "en",
            meta: [
                "og:title": "Understanding Swift Concurrency",
                "article:author": "Jane Smith",
            ],
            body: DOMNode(
                t: "body", id: nil, cls: nil, role: nil, href: nil, src: nil, alt: nil, txt: nil, vis: nil,
                c: [header, article, sidebar, footer]
            )
        )
    }

}

// MARK: - Stub Site Extractor

private struct StubSiteExtractor: SiteSpecificExtracting {
    let hostname: String
    let content: ArticleContent?

    func canHandle(hostname: String) -> Bool {
        self.hostname == hostname
    }

    func extract(from dom: SerializedDOM) -> ArticleContent? {
        content
    }
}
