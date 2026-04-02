import Testing
import Foundation
@testable import RSSApp

@Suite("FeedIconService Tests")
struct FeedIconServiceTests {

    let service = FeedIconService()

    // MARK: - resolveIconURL

    @Test("Returns feedImageURL when provided")
    func resolveWithFeedImageURL() async {
        let imageURL = URL(string: "https://example.com/logo.png")!
        let result = await service.resolveIconURL(feedSiteURL: nil, feedImageURL: imageURL)

        #expect(result == imageURL)
    }

    @Test("Returns nil when no URLs provided")
    func resolveWithNoURLs() async {
        let result = await service.resolveIconURL(feedSiteURL: nil, feedImageURL: nil)

        #expect(result == nil)
    }

    @Test("Ignores feedImageURL with non-HTTP scheme")
    func resolveIgnoresDataScheme() async {
        let dataURL = URL(string: "data:image/png;base64,abc")!
        let result = await service.resolveIconURL(feedSiteURL: nil, feedImageURL: dataURL)

        #expect(result == nil)
    }

    // MARK: - cachedIconFileURL

    @Test("Returns nil for uncached feed ID")
    func cachedIconFileURLReturnsNilForMissing() {
        let result = service.cachedIconFileURL(for: UUID())

        #expect(result == nil)
    }

    // MARK: - deleteCachedIcon

    @Test("Does not throw for non-existent feed ID")
    func deleteCachedIconNoThrow() {
        service.deleteCachedIcon(for: UUID())
    }
}

// MARK: - HTMLUtilities Icon Extraction Tests

@Suite("HTMLUtilities extractIconURLs Tests")
struct HTMLUtilitiesIconExtractionTests {

    let baseURL = URL(string: "https://example.com")!

    @Test("Extracts apple-touch-icon href")
    func extractsAppleTouchIcon() {
        let html = """
            <html><head>
            <link rel="apple-touch-icon" href="/apple-icon-180.png">
            </head></html>
            """
        let urls = HTMLUtilities.extractIconURLs(from: html, baseURL: baseURL)

        #expect(urls.count == 1)
        #expect(urls[0].absoluteString == "https://example.com/apple-icon-180.png")
    }

    @Test("Extracts link rel=icon href")
    func extractsLinkIcon() {
        let html = """
            <html><head>
            <link rel="icon" href="/favicon.png" type="image/png">
            </head></html>
            """
        let urls = HTMLUtilities.extractIconURLs(from: html, baseURL: baseURL)

        #expect(urls.count == 1)
        #expect(urls[0].absoluteString == "https://example.com/favicon.png")
    }

    @Test("Extracts link rel='shortcut icon' href")
    func extractsShortcutIcon() {
        let html = """
            <html><head>
            <link rel="shortcut icon" href="/favicon.ico">
            </head></html>
            """
        let urls = HTMLUtilities.extractIconURLs(from: html, baseURL: baseURL)

        #expect(urls.count == 1)
        #expect(urls[0].absoluteString == "https://example.com/favicon.ico")
    }

    @Test("Apple-touch-icon has priority over link icon")
    func priorityOrder() {
        let html = """
            <html><head>
            <link rel="icon" href="/favicon.png">
            <link rel="apple-touch-icon" href="/apple-icon.png">
            </head></html>
            """
        let urls = HTMLUtilities.extractIconURLs(from: html, baseURL: baseURL)

        #expect(urls.count == 2)
        #expect(urls[0].absoluteString == "https://example.com/apple-icon.png")
        #expect(urls[1].absoluteString == "https://example.com/favicon.png")
    }

    @Test("Resolves protocol-relative URL")
    func resolvesProtocolRelativeURL() {
        let html = """
            <html><head>
            <link rel="icon" href="//cdn.example.com/icon.png">
            </head></html>
            """
        let urls = HTMLUtilities.extractIconURLs(from: html, baseURL: baseURL)

        #expect(urls.count == 1)
        #expect(urls[0].absoluteString == "https://cdn.example.com/icon.png")
    }

    @Test("Resolves absolute URL unchanged")
    func absoluteURLUnchanged() {
        let html = """
            <html><head>
            <link rel="icon" href="https://other.com/icon.png">
            </head></html>
            """
        let urls = HTMLUtilities.extractIconURLs(from: html, baseURL: baseURL)

        #expect(urls.count == 1)
        #expect(urls[0].absoluteString == "https://other.com/icon.png")
    }

    @Test("Returns empty array for HTML with no icon tags")
    func noIconTags() {
        let html = """
            <html><head>
            <title>No Icons</title>
            <link rel="stylesheet" href="/style.css">
            </head></html>
            """
        let urls = HTMLUtilities.extractIconURLs(from: html, baseURL: baseURL)

        #expect(urls.isEmpty)
    }

    @Test("Handles href before rel attribute order")
    func hrefBeforeRel() {
        let html = """
            <html><head>
            <link href="/icon.png" rel="icon">
            </head></html>
            """
        let urls = HTMLUtilities.extractIconURLs(from: html, baseURL: baseURL)

        #expect(urls.count == 1)
        #expect(urls[0].absoluteString == "https://example.com/icon.png")
    }

    @Test("Case-insensitive matching for rel values")
    func caseInsensitive() {
        let html = """
            <html><head>
            <link rel="Icon" href="/icon.png">
            <link rel="Apple-Touch-Icon" href="/apple.png">
            </head></html>
            """
        let urls = HTMLUtilities.extractIconURLs(from: html, baseURL: baseURL)

        #expect(urls.count == 2)
    }
}
