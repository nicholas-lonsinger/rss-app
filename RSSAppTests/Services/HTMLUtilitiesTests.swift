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

    // MARK: - decodeHTMLEntities

    @Test("Decodes decimal numeric character references")
    func decodeDecimalNumericEntities() {
        #expect(HTMLUtilities.decodeHTMLEntities("Wak&#8217;a") == "Wak\u{2019}a")
    }

    @Test("Decodes hexadecimal numeric character references")
    func decodeHexNumericEntities() {
        #expect(HTMLUtilities.decodeHTMLEntities("&#x201C;hello&#x201D;") == "\u{201C}hello\u{201D}")
    }

    @Test("Decodes mixed numeric and named entities")
    func decodeMixedEntities() {
        #expect(HTMLUtilities.decodeHTMLEntities("Tom &amp; Jerry&#8217;s") == "Tom & Jerry\u{2019}s")
    }

    @Test("Returns string unchanged when no entities present")
    func decodeNoEntities() {
        #expect(HTMLUtilities.decodeHTMLEntities("plain text") == "plain text")
    }

    @Test("Handles invalid numeric entity gracefully")
    func decodeInvalidNumericEntity() {
        // Invalid Unicode scalar (surrogate) — should pass through unchanged
        #expect(HTMLUtilities.decodeHTMLEntities("&#xD800;") == "&#xD800;")
    }

    @Test("Does not double-decode entities containing ampersand")
    func doesNotDoubleDecode() {
        // &amp;#8217; should become &#8217; (not a right single quote)
        #expect(HTMLUtilities.decodeHTMLEntities("&amp;#8217;") == "&#8217;")
        #expect(HTMLUtilities.decodeHTMLEntities("&amp;lt;") == "&lt;")
    }

    @Test("stripHTML decodes numeric entities in descriptions")
    func stripHTMLDecodesNumericEntities() {
        let html = "<p>Los Thuthanaka&#8217;s Wak&#8217;a</p>"
        #expect(HTMLUtilities.stripHTML(html) == "Los Thuthanaka\u{2019}s Wak\u{2019}a")
    }

    // MARK: - escapeHTML

    @Test("Escapes ampersand in HTML text")
    func escapeHTMLAmpersand() {
        #expect(HTMLUtilities.escapeHTML("Tom & Jerry") == "Tom &amp; Jerry")
    }

    @Test("Escapes angle brackets in HTML text")
    func escapeHTMLAngleBrackets() {
        #expect(HTMLUtilities.escapeHTML("a < b > c") == "a &lt; b &gt; c")
    }

    @Test("Passes through plain text in escapeHTML")
    func escapeHTMLPlainText() {
        #expect(HTMLUtilities.escapeHTML("hello world") == "hello world")
    }

    // MARK: - escapeAttribute

    @Test("Escapes ampersand in attribute value")
    func escapeAmpersand() {
        #expect(HTMLUtilities.escapeAttribute("a&b") == "a&amp;b")
    }

    @Test("Escapes double quote in attribute value")
    func escapeDoubleQuote() {
        #expect(HTMLUtilities.escapeAttribute("say \"hello\"") == "say &quot;hello&quot;")
    }

    @Test("Escapes angle brackets in attribute value")
    func escapeAngleBrackets() {
        #expect(HTMLUtilities.escapeAttribute("<tag>") == "&lt;tag&gt;")
    }

    @Test("Passes through string with no special characters")
    func escapeNoSpecialChars() {
        #expect(HTMLUtilities.escapeAttribute("hello world") == "hello world")
    }

    @Test("Escapes multiple special characters in one string")
    func escapeMultipleSpecialChars() {
        #expect(HTMLUtilities.escapeAttribute("a&b<c>d\"e") == "a&amp;b&lt;c&gt;d&quot;e")
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

    // MARK: - extractOGImageURL

    @Test("Extracts og:image URL from meta tag")
    func extractOGImageBasic() {
        let html = """
            <html><head>
            <meta property="og:image" content="https://example.com/photo.jpg">
            </head></html>
            """
        let url = HTMLUtilities.extractOGImageURL(from: html)
        #expect(url?.absoluteString == "https://example.com/photo.jpg")
    }

    @Test("Extracts og:image with content before property attribute")
    func extractOGImageReversedAttributes() {
        let html = """
            <html><head>
            <meta content="https://example.com/photo.jpg" property="og:image">
            </head></html>
            """
        let url = HTMLUtilities.extractOGImageURL(from: html)
        #expect(url?.absoluteString == "https://example.com/photo.jpg")
    }

    @Test("Returns nil when no og:image meta tag present")
    func extractOGImageMissing() {
        let html = """
            <html><head>
            <meta property="og:title" content="My Title">
            </head></html>
            """
        #expect(HTMLUtilities.extractOGImageURL(from: html) == nil)
    }

    @Test("Case-insensitive matching for og:image property")
    func extractOGImageCaseInsensitive() {
        let html = """
            <html><head>
            <meta Property="OG:IMAGE" Content="https://example.com/img.png">
            </head></html>
            """
        let url = HTMLUtilities.extractOGImageURL(from: html)
        #expect(url?.absoluteString == "https://example.com/img.png")
    }

    @Test("Returns nil for empty HTML")
    func extractOGImageEmptyHTML() {
        #expect(HTMLUtilities.extractOGImageURL(from: "") == nil)
    }

    @Test("Extracts og:image with CDN URL from platform-hosted blog")
    func extractOGImageCDNURL() {
        // Simulates platform-hosted blogs (Medium, Substack) that use CDN URLs for og:image
        let html = """
            <html><head>
            <meta property="og:image" content="https://cdn-images.example.com/max/1200/1*abc123.jpeg">
            <meta property="og:site_name" content="My Blog">
            </head></html>
            """
        let url = HTMLUtilities.extractOGImageURL(from: html)
        #expect(url?.absoluteString == "https://cdn-images.example.com/max/1200/1*abc123.jpeg")
    }
}
