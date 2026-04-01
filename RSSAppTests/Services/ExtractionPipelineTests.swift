import Testing
import WebKit

@testable import RSSApp

@Suite("Extraction Pipeline Tests")
@MainActor
struct ExtractionPipelineTests {

    /// Full end-to-end test: load fixture HTML → serialize via WKWebView → extract in Swift.
    @Test func fullPipelineWithSimpleBlogFixture() async throws {
        let dom = try await loadAndSerializeFixture()

        let extractor = ContentExtractor()
        let content = extractor.extract(from: dom)

        #expect(content != nil)
        #expect(content?.title == "Understanding Swift Concurrency")
        #expect(content?.byline == "Jane Smith")
        #expect(content?.textContent.contains("async/await") == true)
        #expect(content?.textContent.contains("actors") == true)
        #expect(content?.textContent.contains("structured concurrency") == true)
        #expect(content?.textContent.contains("Privacy Policy") != true)
        #expect(content?.textContent.contains("Related Posts") != true)
        #expect(content?.htmlContent.contains("<p>") == true)
    }

    @Test func serializerProducesValidJSON() async throws {
        let dom = try await loadAndSerializeFixture()

        #expect(dom.title == "Understanding Swift Concurrency - Tech Blog")
        #expect(dom.lang == "en")
        #expect(dom.body.tagName == "body")
        #expect(!dom.body.children.isEmpty)
    }

    @Test func serializerCapturesMetaTags() async throws {
        let dom = try await loadAndSerializeFixture()

        #expect(dom.meta?["og:title"] == "Understanding Swift Concurrency")
        #expect(dom.meta?["article:author"] == "Jane Smith")
        #expect(dom.meta?["author"] == "Jane Smith")
    }

    // MARK: - Helpers

    private func loadAndSerializeFixture() async throws -> SerializedDOM {
        let html = try loadFixtureHTML()
        let script = try loadSerializerScript()
        return try await serializeInWebView(html: html, script: script)
    }
}
