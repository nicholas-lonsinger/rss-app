import Testing
@testable import RSSApp

@Suite("LoadMoreResult Tests")
struct LoadMoreResultTests {

    @Test("loaded case is equatable")
    func loadedEquatable() {
        #expect(LoadMoreResult.loaded == LoadMoreResult.loaded)
    }

    @Test("exhausted case is equatable")
    func exhaustedEquatable() {
        #expect(LoadMoreResult.exhausted == LoadMoreResult.exhausted)
    }

    @Test("failed case compares by message")
    func failedEquatable() {
        #expect(LoadMoreResult.failed("error A") == LoadMoreResult.failed("error A"))
        #expect(LoadMoreResult.failed("error A") != LoadMoreResult.failed("error B"))
    }

    @Test("different cases are not equal")
    func differentCasesNotEqual() {
        #expect(LoadMoreResult.loaded != LoadMoreResult.exhausted)
        #expect(LoadMoreResult.loaded != LoadMoreResult.failed("error"))
        #expect(LoadMoreResult.exhausted != LoadMoreResult.failed("error"))
    }
}
