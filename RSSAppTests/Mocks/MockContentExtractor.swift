@testable import RSSApp

final class MockContentExtractor: ContentExtracting, @unchecked Sendable {
    // RATIONALE: @unchecked Sendable is safe because mock is only used in
    // single-threaded test contexts and never escapes its creation scope.
    var resultToReturn: ArticleContent?

    init(result: ArticleContent? = nil) {
        self.resultToReturn = result
    }

    func extract(from dom: SerializedDOM) -> ArticleContent? {
        resultToReturn
    }
}
