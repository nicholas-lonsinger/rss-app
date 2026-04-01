import Testing

@testable import RSSApp

@Suite("CandidateScorer Tests")
struct CandidateScorerTests {

    // MARK: - Basic Scoring

    @Test func findsArticleContentInSimplePage() {
        // <body>
        //   <nav><a>Home</a><a>About</a></nav>
        //   <article><p>Long article text...</p></article>
        //   <footer><p>Copyright</p></footer>
        // </body>
        let body = makeBody([
            makeNav(),
            makeArticle(paragraphs: [longParagraph, longParagraph, longParagraph]),
            makeFooter(),
        ])

        let candidate = CandidateScorer.findTopCandidate(in: body)
        #expect(candidate != nil)
        #expect(candidate?.node.tagName == "article")
    }

    @Test func prefersContentDivOverNavAndSidebar() {
        let body = makeBody([
            makeNav(),
            DOMNode(
                t: "div", id: "content", cls: "main-content", role: nil, href: nil, src: nil, alt: nil, txt: nil, vis: nil,
                c: [makeParagraph(longParagraph), makeParagraph(longParagraph)]
            ),
            DOMNode(
                t: "aside", id: nil, cls: "sidebar", role: nil, href: nil, src: nil, alt: nil, txt: nil, vis: nil,
                c: [makeParagraph("Short sidebar text.")]
            ),
        ])

        let candidate = CandidateScorer.findTopCandidate(in: body)
        #expect(candidate != nil)
        #expect(candidate?.node.identifier == "content")
    }

    @Test func returnsNilForEmptyBody() {
        let body = DOMNode(t: "body", id: nil, cls: nil, role: nil, href: nil, src: nil, alt: nil, txt: nil, vis: nil, c: nil)
        let candidate = CandidateScorer.findTopCandidate(in: body)
        #expect(candidate == nil)
    }

    @Test func returnsNilWhenNoScorableContent() {
        // Only short text — below the 25-char threshold
        let body = makeBody([makeParagraph("Short.")])
        let candidate = CandidateScorer.findTopCandidate(in: body)
        #expect(candidate == nil)
    }

    // MARK: - Pruning

    @Test func prunesHiddenElements() {
        let hiddenDiv = DOMNode(
            t: "div", id: nil, cls: nil, role: nil, href: nil, src: nil, alt: nil, txt: nil, vis: false,
            c: [makeParagraph(longParagraph)]
        )
        let visibleArticle = makeArticle(paragraphs: [longParagraph, longParagraph])

        let body = makeBody([hiddenDiv, visibleArticle])
        let candidate = CandidateScorer.findTopCandidate(in: body)

        #expect(candidate != nil)
        #expect(candidate?.node.tagName == "article")
    }

    @Test func prunesNavigationRole() {
        let navRole = DOMNode(
            t: "div", id: nil, cls: nil, role: "navigation", href: nil, src: nil, alt: nil, txt: nil, vis: nil,
            c: [makeParagraph(longParagraph)]
        )
        let article = makeArticle(paragraphs: [longParagraph, longParagraph])

        let body = makeBody([navRole, article])
        let candidate = CandidateScorer.findTopCandidate(in: body)

        #expect(candidate?.node.tagName == "article")
    }

    @Test func prunesSidebarClass() {
        let sidebar = DOMNode(
            t: "div", id: nil, cls: "sidebar", role: nil, href: nil, src: nil, alt: nil, txt: nil, vis: nil,
            c: [makeParagraph(longParagraph)]
        )
        let article = makeArticle(paragraphs: [longParagraph, longParagraph])

        let body = makeBody([sidebar, article])
        let candidate = CandidateScorer.findTopCandidate(in: body)

        #expect(candidate?.node.tagName == "article")
    }

    // MARK: - Link Density

    @Test func penalizesHighLinkDensity() {
        // A div full of links should score lower than a div with prose.
        let linkHeavyDiv = DOMNode(
            t: "div", id: nil, cls: "entry-content", role: nil, href: nil, src: nil, alt: nil, txt: nil, vis: nil,
            c: [
                makeLink("Link one text here is long enough"),
                makeLink("Link two text here is long enough"),
                makeLink("Link three text here is long enough"),
            ]
        )
        let proseDiv = DOMNode(
            t: "div", id: nil, cls: "post-content", role: nil, href: nil, src: nil, alt: nil, txt: nil, vis: nil,
            c: [makeParagraph(longParagraph), makeParagraph(longParagraph)]
        )

        let body = makeBody([linkHeavyDiv, proseDiv])
        let candidate = CandidateScorer.findTopCandidate(in: body)

        #expect(candidate?.node.className == "post-content")
    }

    // MARK: - Class/ID Weighting

    @Test func boostsPositiveClassNames() {
        let genericDiv = DOMNode(
            t: "div", id: nil, cls: nil, role: nil, href: nil, src: nil, alt: nil, txt: nil, vis: nil,
            c: [makeParagraph(longParagraph)]
        )
        let contentDiv = DOMNode(
            t: "div", id: nil, cls: "entry-content", role: nil, href: nil, src: nil, alt: nil, txt: nil, vis: nil,
            c: [makeParagraph(longParagraph)]
        )

        // Both have identical content, but entry-content gets a class bonus.
        let body = makeBody([genericDiv, contentDiv])
        let candidate = CandidateScorer.findTopCandidate(in: body)

        #expect(candidate?.node.className == "entry-content")
    }

    @Test func articleTagGetsHighBaseScore() {
        // <article> gets +10 tag weight vs <div> at +5
        let article = makeArticle(paragraphs: [longParagraph])
        let div = DOMNode(
            t: "div", id: nil, cls: nil, role: nil, href: nil, src: nil, alt: nil, txt: nil, vis: nil,
            c: [makeParagraph(longParagraph)]
        )

        let body = makeBody([article, div])
        let candidate = CandidateScorer.findTopCandidate(in: body)

        #expect(candidate?.node.tagName == "article")
    }

    // MARK: - Div-as-Paragraph

    @Test func treatsDivWithOnlyInlineContentAsParagraph() {
        // A div containing only text (no block children) should be treated as scorable.
        let inlineDiv = DOMNode(
            t: "div", id: nil, cls: "article-text", role: nil, href: nil, src: nil, alt: nil, txt: nil, vis: nil,
            c: [makeTextNode(longParagraph)]
        )
        let wrapper = DOMNode(
            t: "div", id: nil, cls: "content", role: nil, href: nil, src: nil, alt: nil, txt: nil, vis: nil,
            c: [inlineDiv]
        )

        let body = makeBody([wrapper])
        let candidate = CandidateScorer.findTopCandidate(in: body)

        #expect(candidate != nil)
    }

    // MARK: - Test Data & Helpers

    private let longParagraph = "Swift concurrency represents a fundamental shift in how we write asynchronous code on Apple platforms. With the introduction of async/await, actors, and structured concurrency, developers now have powerful tools to write safe, efficient concurrent code that is both readable and maintainable."

    private func makeBody(_ children: [DOMNode]) -> DOMNode {
        DOMNode(t: "body", id: nil, cls: nil, role: nil, href: nil, src: nil, alt: nil, txt: nil, vis: nil, c: children)
    }

    private func makeArticle(paragraphs: [String]) -> DOMNode {
        DOMNode(
            t: "article", id: nil, cls: nil, role: nil, href: nil, src: nil, alt: nil, txt: nil, vis: nil,
            c: paragraphs.map { makeParagraph($0) }
        )
    }

    private func makeNav() -> DOMNode {
        DOMNode(
            t: "nav", id: nil, cls: nil, role: "navigation", href: nil, src: nil, alt: nil, txt: nil, vis: nil,
            c: [makeLink("Home"), makeLink("About"), makeLink("Contact")]
        )
    }

    private func makeFooter() -> DOMNode {
        DOMNode(
            t: "footer", id: nil, cls: "footer", role: nil, href: nil, src: nil, alt: nil, txt: nil, vis: nil,
            c: [makeParagraph("Copyright 2025")]
        )
    }

    private func makeParagraph(_ text: String) -> DOMNode {
        DOMNode(
            t: "p", id: nil, cls: nil, role: nil, href: nil, src: nil, alt: nil, txt: nil, vis: nil,
            c: [makeTextNode(text)]
        )
    }

    private func makeLink(_ text: String) -> DOMNode {
        DOMNode(
            t: "a", id: nil, cls: nil, role: nil, href: "https://example.com", src: nil, alt: nil, txt: nil, vis: nil,
            c: [makeTextNode(text)]
        )
    }

    private func makeTextNode(_ text: String) -> DOMNode {
        DOMNode(t: "#text", id: nil, cls: nil, role: nil, href: nil, src: nil, alt: nil, txt: text, vis: nil, c: nil)
    }
}
