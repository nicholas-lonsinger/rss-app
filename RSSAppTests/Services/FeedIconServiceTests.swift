import Testing
import Foundation
import UIKit
@testable import RSSApp

@Suite("FeedIconService Tests")
struct FeedIconServiceTests {

    let service = FeedIconService()

    // MARK: - resolveIconCandidates

    @Test("Returns empty when no URLs provided")
    func resolveWithNoURLs() async {
        let result = await service.resolveIconCandidates(feedSiteURL: nil, feedImageURL: nil)

        #expect(result.isEmpty)
    }

    @Test("Ignores feedImageURL with non-HTTP scheme")
    func resolveIgnoresDataScheme() async {
        let dataURL = URL(string: "data:image/png;base64,abc")!
        let result = await service.resolveIconCandidates(feedSiteURL: nil, feedImageURL: dataURL)

        #expect(result.isEmpty)
    }

    @Test("Includes feedImageURL as first candidate when HTTP")
    func resolveIncludesFeedImageURL() async {
        let imageURL = URL(string: "https://example.com/logo.png")!
        let result = await service.resolveIconCandidates(feedSiteURL: nil, feedImageURL: imageURL)

        #expect(result.first == imageURL)
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

    // MARK: - ICO Decoding

    @Test("Decodes ICO file with embedded PNG")
    @MainActor
    func decodeICOWithPNG() {
        // Create a 16x16 1x-scale PNG to avoid Retina scaling
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16), format: format)
        let pngData = renderer.pngData { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
        }

        // Wrap in ICO container: 6-byte header + 16-byte directory entry + PNG data
        var ico = Data()
        // Header: reserved=0, type=1 (icon), count=1
        ico.append(contentsOf: [0x00, 0x00, 0x01, 0x00, 0x01, 0x00])
        // Directory entry: width=16, height=16, colorCount=0, reserved=0
        ico.append(contentsOf: [16, 16, 0, 0])
        // planes=1, bitCount=32
        ico.append(contentsOf: [0x01, 0x00, 0x20, 0x00])
        // bytesInRes (little-endian)
        let size = UInt32(pngData.count)
        ico.append(contentsOf: withUnsafeBytes(of: size.littleEndian) { Array($0) })
        // imageOffset = 22 (6 header + 16 entry)
        let offset: UInt32 = 22
        ico.append(contentsOf: withUnsafeBytes(of: offset.littleEndian) { Array($0) })
        // PNG data
        ico.append(pngData)

        let image = FeedIconService.decodeICO(ico)
        #expect(image != nil)
        #expect(image!.size.width == 16)
        #expect(image!.size.height == 16)
    }

    @Test("Decodes real BMP-based ICO file (16x16 4-bit)")
    func decodeICORealBMP() {
        // Real favicon.ico from krebsonsecurity.com — 16x16, 4-bit BMP in ICO container
        let base64 = "AAABAAEAEBAQAAAAAAAoAQAAFgAAACgAAAAQAAAAIAAAAAEABAAAAAAAwAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA////AHh4eADIyMgAVVVVAMzMzAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABUJAQkMAAAAgBQUDACAAAgAAADAAAgAgAAAFAAAAIEAAAAAAAABAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAD//wAA//8AAP//AAD//wAA4A8AAMAHAACEQwAABMEAAARBAAD//wAA/H8AAP//AAD//wAA//8AAP//AAD//wAA"
        guard let data = Data(base64Encoded: base64) else {
            Issue.record("Failed to decode base64 test data")
            return
        }

        let image = FeedIconService.decodeICO(data)
        #expect(image != nil, "BMP-based ICO should decode successfully")
    }

    @Test("Returns nil for non-ICO data")
    func decodeICORejectsNonICO() {
        let garbage = Data("not an ico file".utf8)
        #expect(FeedIconService.decodeICO(garbage) == nil)
    }

    @Test("Returns nil for empty data")
    func decodeICORejectsEmpty() {
        #expect(FeedIconService.decodeICO(Data()) == nil)
    }

    @Test("Selects the largest image from multi-image ICO")
    @MainActor
    func decodeICOSelectsLargest() {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let small = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8), format: format)
            .pngData { ctx in UIColor.blue.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 8)) }
        let large = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 32), format: format)
            .pngData { ctx in UIColor.green.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 32, height: 32)) }

        var ico = Data()
        // Header: count=2
        ico.append(contentsOf: [0x00, 0x00, 0x01, 0x00, 0x02, 0x00])

        // Entry 1: 8x8
        let offset1: UInt32 = 6 + 16 + 16 // after header + 2 entries
        ico.append(contentsOf: [8, 8, 0, 0, 0x01, 0x00, 0x20, 0x00])
        let size1 = UInt32(small.count)
        ico.append(contentsOf: withUnsafeBytes(of: size1.littleEndian) { Array($0) })
        ico.append(contentsOf: withUnsafeBytes(of: offset1.littleEndian) { Array($0) })

        // Entry 2: 32x32
        let offset2 = offset1 + size1
        ico.append(contentsOf: [32, 32, 0, 0, 0x01, 0x00, 0x20, 0x00])
        let size2 = UInt32(large.count)
        ico.append(contentsOf: withUnsafeBytes(of: size2.littleEndian) { Array($0) })
        ico.append(contentsOf: withUnsafeBytes(of: offset2.littleEndian) { Array($0) })

        // Image data
        ico.append(small)
        ico.append(large)

        let image = FeedIconService.decodeICO(ico)
        #expect(image != nil)
        #expect(image!.size.width == 32)
        #expect(image!.size.height == 32)
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
