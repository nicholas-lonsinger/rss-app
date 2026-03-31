import Testing
@testable import RSSApp

@Suite("ArticleSummaryViewModel — pre-extracted content")
@MainActor
struct ArticleSummaryPreExtractionTests {

    private static let sampleContent = ArticleContent(
        title: "Test",
        byline: "Author",
        htmlContent: "<p>Body</p>",
        textContent: "Body"
    )

    @Test("skips extraction when pre-extracted content is provided")
    func skipsExtraction() {
        let mock = MockArticleExtractionService()
        let article = TestFixtures.makeArticle()
        let vm = ArticleSummaryViewModel(
            article: article,
            preExtractedContent: Self.sampleContent,
            extractor: mock
        )

        #expect(vm.extractedContent != nil)
        #expect(vm.extractedContent?.title == "Test")
    }

    @Test("extractedContent is nil when no pre-extracted content provided")
    func noPreExtractedContent() {
        let article = TestFixtures.makeArticle()
        let vm = ArticleSummaryViewModel(article: article, extractor: MockArticleExtractionService())

        #expect(vm.extractedContent == nil)
    }

    @Test("extractedContent set from pre-extraction is available for discussion")
    func preExtractedAvailableForDiscussion() {
        let article = TestFixtures.makeArticle()
        let vm = ArticleSummaryViewModel(
            article: article,
            preExtractedContent: Self.sampleContent,
            extractor: MockArticleExtractionService()
        )

        #expect(vm.extractedContent?.textContent == "Body")
        #expect(vm.extractedContent?.byline == "Author")
    }
}
