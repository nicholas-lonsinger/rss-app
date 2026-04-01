import Testing

@testable import RSSApp

@Suite("MetadataExtractor Tests")
struct MetadataExtractorTests {

    // MARK: - Title Extraction

    @Test func extractsTitleFromOGMeta() {
        let dom = makeDOM(
            meta: ["og:title": "OG Title"],
            bodyChildren: [DOMNodeFactory.makeH1("DOM Title")]
        )
        let metadata = MetadataExtractor.extract(from: dom)
        #expect(metadata.title == "OG Title")
    }

    @Test func extractsTitleFromTwitterMeta() {
        let dom = makeDOM(
            meta: ["twitter:title": "Twitter Title"],
            bodyChildren: [DOMNodeFactory.makeH1("DOM Title")]
        )
        let metadata = MetadataExtractor.extract(from: dom)
        #expect(metadata.title == "Twitter Title")
    }

    @Test func extractsTitleFromH1InArticle() {
        let article = DOMNode(
            t: "article", id: nil, cls: nil, role: nil, href: nil, src: nil, alt: nil, txt: nil, vis: nil,
            c: [DOMNodeFactory.makeH1("Article Heading")]
        )
        let dom = makeDOM(meta: nil, bodyChildren: [article])
        let metadata = MetadataExtractor.extract(from: dom)
        #expect(metadata.title == "Article Heading")
    }

    @Test func extractsTitleFromFirstH1WhenNoArticleTag() {
        let dom = makeDOM(meta: nil, bodyChildren: [DOMNodeFactory.makeH1("Page Heading")])
        let metadata = MetadataExtractor.extract(from: dom)
        #expect(metadata.title == "Page Heading")
    }

    @Test func extractsTitleFromDocumentTitleAsFallback() {
        let dom = SerializedDOM(
            title: "My Article - Blog Name",
            url: "https://example.com",
            lang: nil,
            meta: nil,
            body: DOMNode(t: "body", id: nil, cls: nil, role: nil, href: nil, src: nil, alt: nil, txt: nil, vis: nil, c: nil)
        )
        let metadata = MetadataExtractor.extract(from: dom)
        #expect(metadata.title == "My Article")
    }

    @Test func cleansDocumentTitleWithPipeSeparator() {
        let dom = SerializedDOM(
            title: "Understanding Swift | Tech Blog",
            url: "https://example.com",
            lang: nil,
            meta: nil,
            body: DOMNode(t: "body", id: nil, cls: nil, role: nil, href: nil, src: nil, alt: nil, txt: nil, vis: nil, c: nil)
        )
        let metadata = MetadataExtractor.extract(from: dom)
        #expect(metadata.title == "Understanding Swift")
    }

    @Test func returnsEmptyTitleWhenNoneFound() {
        let dom = SerializedDOM(
            title: "",
            url: "https://example.com",
            lang: nil,
            meta: nil,
            body: DOMNode(t: "body", id: nil, cls: nil, role: nil, href: nil, src: nil, alt: nil, txt: nil, vis: nil, c: nil)
        )
        let metadata = MetadataExtractor.extract(from: dom)
        #expect(metadata.title == "")
    }

    // MARK: - Byline Extraction

    @Test func extractsBylineFromArticleAuthorMeta() {
        let dom = makeDOM(meta: ["article:author": "Jane Smith"], bodyChildren: [])
        let metadata = MetadataExtractor.extract(from: dom)
        #expect(metadata.byline == "Jane Smith")
    }

    @Test func extractsBylineFromAuthorMeta() {
        let dom = makeDOM(meta: ["author": "John Doe"], bodyChildren: [])
        let metadata = MetadataExtractor.extract(from: dom)
        #expect(metadata.byline == "John Doe")
    }

    @Test func extractsBylineFromDOMBylineClass() {
        let bylineDiv = DOMNode(
            t: "div", id: nil, cls: "byline", role: nil, href: nil, src: nil, alt: nil, txt: nil, vis: nil,
            c: [DOMNodeFactory.makeTextNode("By Alice Johnson")]
        )
        let dom = makeDOM(meta: nil, bodyChildren: [bylineDiv])
        let metadata = MetadataExtractor.extract(from: dom)
        #expect(metadata.byline == "Alice Johnson")
    }

    @Test func extractsBylineFromDOMAuthorClass() {
        let authorSpan = DOMNode(
            t: "span", id: nil, cls: "author", role: nil, href: nil, src: nil, alt: nil, txt: nil, vis: nil,
            c: [DOMNodeFactory.makeTextNode("Written by Bob Lee")]
        )
        let dom = makeDOM(meta: nil, bodyChildren: [authorSpan])
        let metadata = MetadataExtractor.extract(from: dom)
        #expect(metadata.byline == "Bob Lee")
    }

    @Test func returnsNilBylineWhenNoneFound() {
        let dom = makeDOM(meta: nil, bodyChildren: [DOMNodeFactory.makeParagraph("Just content.")])
        let metadata = MetadataExtractor.extract(from: dom)
        #expect(metadata.byline == nil)
    }

    @Test func prefersMetaBylineOverDOM() {
        let bylineDiv = DOMNode(
            t: "div", id: nil, cls: "byline", role: nil, href: nil, src: nil, alt: nil, txt: nil, vis: nil,
            c: [DOMNodeFactory.makeTextNode("DOM Author")]
        )
        let dom = makeDOM(meta: ["article:author": "Meta Author"], bodyChildren: [bylineDiv])
        let metadata = MetadataExtractor.extract(from: dom)
        #expect(metadata.byline == "Meta Author")
    }

    // MARK: - Helpers

    private func makeDOM(meta: [String: String]?, bodyChildren: [DOMNode]) -> SerializedDOM {
        SerializedDOM(
            title: "Test Page",
            url: "https://example.com",
            lang: "en",
            meta: meta,
            body: DOMNode(
                t: "body", id: nil, cls: nil, role: nil, href: nil, src: nil, alt: nil, txt: nil, vis: nil,
                c: bodyChildren.isEmpty ? nil : bodyChildren
            )
        )
    }

}
