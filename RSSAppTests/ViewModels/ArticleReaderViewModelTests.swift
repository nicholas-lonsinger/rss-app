import Testing
@testable import RSSApp

@Suite("ArticleReaderViewModel")
@MainActor
struct ArticleReaderViewModelTests {

    @Test("initial state is loading")
    func initialState() {
        let article = TestFixtures.makeArticle()
        let vm = ArticleReaderViewModel(article: article, extractor: MockArticleExtractionService())
        guard case .loading = vm.state else {
            Issue.record("Expected .loading, got \(vm.state)")
            return
        }
    }

    @Test("extractContent transitions to loaded on success")
    func extractSuccess() async throws {
        let content = ArticleContent(
            title: "Test",
            byline: "Author",
            htmlContent: "<p>Body</p>",
            textContent: "Body"
        )
        let mock = MockArticleExtractionService(result: content)
        let article = TestFixtures.makeArticle()
        let vm = ArticleReaderViewModel(article: article, extractor: mock)

        await vm.extractContent()

        guard case .loaded(let loaded) = vm.state else {
            Issue.record("Expected .loaded, got \(vm.state)")
            return
        }
        #expect(loaded.title == "Test")
    }

    @Test("extractContent transitions to failed on error")
    func extractFailure() async {
        let mock = MockArticleExtractionService(error: ArticleExtractionError.javascriptFailed)
        let article = TestFixtures.makeArticle()
        let vm = ArticleReaderViewModel(article: article, extractor: mock)

        await vm.extractContent()

        guard case .failed = vm.state else {
            Issue.record("Expected .failed, got \(vm.state)")
            return
        }
    }

    @Test("extractContent transitions to failed when article has no link")
    func extractNoLink() async {
        let article = TestFixtures.makeArticle(link: nil)
        let vm = ArticleReaderViewModel(article: article, extractor: MockArticleExtractionService())

        await vm.extractContent()

        guard case .failed = vm.state else {
            Issue.record("Expected .failed, got \(vm.state)")
            return
        }
    }
}
