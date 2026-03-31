import Testing
import Foundation
@testable import RSSApp

@Suite("HTMLUtilities Tests")
struct HTMLUtilitiesTests {

    // MARK: - stripHTML

    @Test("Strips HTML tags correctly")
    func stripHTMLTags() {
        let html = "<p>Hello <b>world</b></p>"
        #expect(HTMLUtilities.stripHTML(html) == "Hello world")
    }

    @Test("Decodes common HTML entities")
    func decodeEntities() {
        let html = "Tom &amp; Jerry &lt;3 &gt; &quot;cats&quot; &#39;dogs&#39;"
        #expect(HTMLUtilities.stripHTML(html) == "Tom & Jerry <3 > \"cats\" 'dogs'")
    }

    @Test("Decodes &apos; entity")
    func decodeAposEntity() {
        let html = "it&apos;s"
        #expect(HTMLUtilities.stripHTML(html) == "it's")
    }

    @Test("Decodes &nbsp; to space")
    func decodeNbsp() {
        let html = "hello&nbsp;world"
        #expect(HTMLUtilities.stripHTML(html) == "hello world")
    }

    @Test("Plain text without tags returns unchanged")
    func plainTextPassthrough() {
        let text = "Just plain text"
        #expect(HTMLUtilities.stripHTML(text) == "Just plain text")
    }

    @Test("Empty string returns empty")
    func emptyString() {
        #expect(HTMLUtilities.stripHTML("") == "")
    }

    @Test("Collapses multiple whitespace into single space")
    func collapseWhitespace() {
        let html = "<p>Hello</p>   \n\n   <p>World</p>"
        #expect(HTMLUtilities.stripHTML(html) == "Hello World")
    }

    // MARK: - extractFirstImageURL

    @Test("Extracts img src with double quotes")
    func extractImageDoubleQuotes() {
        let html = """
            <p>Text</p><img src="https://example.com/image.jpg" alt="test"><p>More</p>
            """
        let url = HTMLUtilities.extractFirstImageURL(from: html)
        #expect(url?.absoluteString == "https://example.com/image.jpg")
    }

    @Test("Extracts img src with single quotes")
    func extractImageSingleQuotes() {
        let html = "<img src='https://example.com/image.png'>"
        let url = HTMLUtilities.extractFirstImageURL(from: html)
        #expect(url?.absoluteString == "https://example.com/image.png")
    }

    @Test("Returns nil when no img tag present")
    func noImageReturnsNil() {
        let html = "<p>No images here</p>"
        #expect(HTMLUtilities.extractFirstImageURL(from: html) == nil)
    }

    @Test("Returns first image when multiple present")
    func returnsFirstImage() {
        let html = """
            <img src="https://example.com/first.jpg"><img src="https://example.com/second.jpg">
            """
        let url = HTMLUtilities.extractFirstImageURL(from: html)
        #expect(url?.absoluteString == "https://example.com/first.jpg")
    }

    @Test("Returns nil for empty string")
    func emptyStringNoImage() {
        #expect(HTMLUtilities.extractFirstImageURL(from: "") == nil)
    }
}
