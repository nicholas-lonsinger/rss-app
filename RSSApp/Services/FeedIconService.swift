import Foundation
import os
import UIKit

// MARK: - Result Types

/// The background tile color that best contrasts against a cached icon's opaque
/// pixels. Persisted per-feed on `PersistentFeed` (via `iconBackgroundStyleRaw`)
/// so `FeedIconView` can render the right tile without re-analyzing the image
/// on every display (issue #342).
///
/// - `light`: icon is predominantly dark — render a light (white) tile so the
///   icon's dark strokes stay visible where the PNG has transparency.
/// - `dark`: icon is predominantly light — render a dark (black) tile so
///   white-on-transparent icons (e.g. Apple Insider) stay visible.
enum FeedIconBackgroundStyle: String, Sendable, Equatable {
    case light
    case dark
}

// MARK: - Protocol

protocol FeedIconResolving: Sendable {

    /// Returns candidate icon URLs from multiple sources in priority order:
    /// feed XML image → og:image → site HTML link tags → original-host /favicon.ico →
    /// redirected-host /favicon.ico (when a cross-domain redirect occurred).
    /// Callers should try each URL until one successfully downloads.
    func resolveIconCandidates(feedSiteURL: URL?, feedImageURL: URL?) async -> [URL]

    /// Downloads the image at `remoteURL`, normalizes it to PNG, and caches it
    /// to disk under the feed's UUID. Returns the background-style
    /// classification on success, or `nil` on failure (download error, decode
    /// failure, or no visible content). When luminance analysis could not run
    /// (e.g. CGContext allocation failure) the image is still cached and a
    /// neutral default (`.dark` → black tile) is returned so callers don't
    /// drop an otherwise-valid icon.
    func cacheIcon(from remoteURL: URL, feedID: UUID) async -> FeedIconBackgroundStyle?

    /// Returns the local file URL for a cached icon, or `nil` if not cached.
    func cachedIconFileURL(for feedID: UUID) -> URL?

    /// Loads the cached icon for `feedID` off the main actor, decoding the PNG on disk,
    /// verifying it has visible content, and deleting the file (with a warning log)
    /// if it is unreadable or fully transparent. Returns `nil` when no cached icon
    /// exists, or when the cached file failed validation and was removed.
    ///
    /// This is the preferred entry point for UI layers that need to display a cached
    /// icon — it centralizes the decode + validity gate + delete-on-corrupt pipeline
    /// so the invariant is enforced once, at the service boundary.
    func loadValidatedIcon(for feedID: UUID) async -> UIImage?

    /// Resolves candidate icon URLs and caches the first one that downloads successfully.
    /// Returns the remote URL of the cached icon along with the luminance-based
    /// background-style classification, or `nil` when no candidate could be cached.
    func resolveAndCacheIcon(feedSiteURL: URL?, feedImageURL: URL?, feedID: UUID) async -> (url: URL, backgroundStyle: FeedIconBackgroundStyle)?

    /// Classifies the background style of an already-cached icon without
    /// touching the network. Used to back-fill `FeedIconBackgroundStyle` for
    /// feeds that were cached before the classifier existed (issue #342).
    /// Returns `nil` when no cached icon exists or the file cannot be decoded.
    func classifyCachedIconBackgroundStyle(for feedID: UUID) async -> FeedIconBackgroundStyle?

    /// Deletes the cached icon file for the given feed.
    func deleteCachedIcon(for feedID: UUID)
}

// MARK: - Implementation

struct FeedIconService: FeedIconResolving {

    private static let logger = Logger(category: "FeedIconService")

    private static let iconCacheDirectoryName = "feed-icons"
    private static let htmlFetchTimeout: TimeInterval = 10
    private static let iconFetchTimeout: TimeInterval = 15

    /// The icon-related meta tags are in the `<head>`, so we only need the first portion of the page.
    private static let htmlHeadMaxBytes = 51_200 // 50 KB
    private static let maxIconDimension: CGFloat = 128

    /// Optional override for the on-disk cache directory. When `nil`, the service writes to
    /// `<Caches>/feed-icons` (production default). Tests can pass a unique temporary directory
    /// to isolate cache files and avoid leaking fixture data into the real user caches directory
    /// on crash. See `FeedIconServiceTests` for the test-side helper.
    private let cacheDirectoryOverride: URL?

    init(cacheDirectoryOverride: URL? = nil) {
        self.cacheDirectoryOverride = cacheDirectoryOverride
    }

    // MARK: - FeedIconResolving

    func resolveIconCandidates(feedSiteURL: URL?, feedImageURL: URL?) async -> [URL] {
        Self.logger.debug("resolveIconCandidates() feedImageURL=\(feedImageURL?.absoluteString ?? "nil", privacy: .public) siteURL=\(feedSiteURL?.absoluteString ?? "nil", privacy: .public)")

        // Fetch site homepage HTML and extract icon sources
        var htmlResult: HTMLIconResult?
        if let siteURL = feedSiteURL {
            htmlResult = await resolveFromHTML(siteURL: siteURL)
        }

        let candidates = Self.assembleCandidates(
            feedSiteURL: feedSiteURL,
            feedImageURL: feedImageURL,
            htmlResult: htmlResult
        )

        Self.logger.debug("Found \(candidates.count, privacy: .public) icon candidates")
        return candidates
    }

    func cacheIcon(from remoteURL: URL, feedID: UUID) async -> FeedIconBackgroundStyle? {
        Self.logger.debug("cacheIcon() from \(remoteURL.absoluteString, privacy: .public) for feed \(feedID.uuidString, privacy: .public)")

        let pngData: Data
        let stats: IconPixelStats

        do {
            var request = URLRequest(url: remoteURL, timeoutInterval: Self.iconFetchTimeout)
            request.setBrowserUserAgent()
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                Self.logger.warning("Icon fetch returned HTTP \(code, privacy: .public) for \(remoteURL.absoluteString, privacy: .public)")
                return nil
            }

            guard let image = UIImage(data: data) ?? Self.decodeICO(data) else {
                let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "unknown"
                Self.logger.warning("Downloaded data is not a valid image (\(contentType, privacy: .public), \(data.count, privacy: .public) bytes) from \(remoteURL.absoluteString, privacy: .public)")
                return nil
            }

            // Normalize: resize if too large, convert to PNG
            let normalized = normalizeImage(image)

            // Single bitmap walk: visibility gate + average luminance of opaque
            // pixels. Sharing the pass avoids a second CGContext allocation.
            // `analyzeIconPixels` returns a sentinel neutral result (accept +
            // .dark default tile) on CGContext failure so we don't reject an
            // otherwise-valid icon over a bitmap-inspection glitch — matching
            // the legacy `hasVisibleContent` accept-on-failure semantic.
            let pixelStats = Self.analyzeIconPixels(normalized, feedID: feedID)
            guard pixelStats.isVisible else {
                Self.logger.warning("Image has no visible content (\(data.count, privacy: .public) bytes) from \(remoteURL.absoluteString, privacy: .public)")
                return nil
            }

            guard let encoded = normalized.pngData() else {
                Self.logger.warning("Failed to generate PNG data from image")
                return nil
            }

            pngData = encoded
            stats = pixelStats
        } catch {
            Self.logger.warning("Failed to fetch or decode icon for \(remoteURL.absoluteString, privacy: .public): \(error, privacy: .public)")
            return nil
        }

        let fileURL = iconFileURL(for: feedID)
        do {
            try ensureCacheDirectoryExists()
            try pngData.write(to: fileURL, options: .atomic)
        } catch {
            Self.logger.error("Failed to write icon cache for feed \(feedID.uuidString, privacy: .public) at \(fileURL.path(percentEncoded: false), privacy: .public): \(error, privacy: .public)")
            return nil
        }

        let backgroundStyle = Self.classifyBackgroundStyle(averageLuminance: stats.averageLuminance)
        Self.logger.debug("Cached icon for feed \(feedID.uuidString, privacy: .public) (\(pngData.count, privacy: .public) bytes, luminance=\(stats.averageLuminance, privacy: .public), background=\(backgroundStyle.rawValue, privacy: .public))")
        return backgroundStyle
    }

    func cachedIconFileURL(for feedID: UUID) -> URL? {
        let fileURL = iconFileURL(for: feedID)
        return FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) ? fileURL : nil
    }

    func loadValidatedIcon(for feedID: UUID) async -> UIImage? {
        guard let fileURL = cachedIconFileURL(for: feedID) else {
            Self.logger.debug("No cached icon for feed \(feedID.uuidString, privacy: .public) — awaiting next refresh")
            return nil
        }
        return await Task.detached(priority: .userInitiated) { () -> UIImage? in
            guard let image = UIImage(contentsOfFile: fileURL.path(percentEncoded: false)) else {
                Self.logger.warning("Cached icon file unreadable for feed \(feedID.uuidString, privacy: .public) at \(fileURL.path, privacy: .public) — deleting")
                self.deleteCachedIcon(for: feedID)
                return nil
            }
            guard Self.hasVisibleContent(image) else {
                Self.logger.warning("Cached icon for feed \(feedID.uuidString, privacy: .public) has no visible content — deleting")
                self.deleteCachedIcon(for: feedID)
                return nil
            }
            return image
        }.value
    }

    func resolveAndCacheIcon(feedSiteURL: URL?, feedImageURL: URL?, feedID: UUID) async -> (url: URL, backgroundStyle: FeedIconBackgroundStyle)? {
        let candidates = await resolveIconCandidates(feedSiteURL: feedSiteURL, feedImageURL: feedImageURL)
        for candidate in candidates {
            if let backgroundStyle = await cacheIcon(from: candidate, feedID: feedID) {
                return (candidate, backgroundStyle)
            }
        }
        Self.logger.debug("No icon cached for feed \(feedID.uuidString, privacy: .public) (\(candidates.count, privacy: .public) candidates tried)")
        return nil
    }

    func classifyCachedIconBackgroundStyle(for feedID: UUID) async -> FeedIconBackgroundStyle? {
        guard let fileURL = cachedIconFileURL(for: feedID) else {
            return nil
        }
        return await Task.detached(priority: .utility) { () -> FeedIconBackgroundStyle? in
            guard let image = UIImage(contentsOfFile: fileURL.path(percentEncoded: false)) else {
                Self.logger.warning("classifyCachedIconBackgroundStyle: cached icon file unreadable for feed \(feedID.uuidString, privacy: .public)")
                return nil
            }
            let stats = Self.analyzeIconPixels(image, feedID: feedID)
            // Respect the same visibility gate as cacheIcon so a transparent
            // cached file doesn't get misclassified as `.dark` by the sentinel
            // fallback. An invisible cached icon is treated as unclassifiable.
            guard stats.isVisible else {
                Self.logger.debug("classifyCachedIconBackgroundStyle: cached icon for feed \(feedID.uuidString, privacy: .public) is not visible — skipping classification")
                return nil
            }
            let backgroundStyle = Self.classifyBackgroundStyle(averageLuminance: stats.averageLuminance)
            Self.logger.debug("Reclassified cached icon for feed \(feedID.uuidString, privacy: .public) as \(backgroundStyle.rawValue, privacy: .public) (luminance=\(stats.averageLuminance, privacy: .public))")
            return backgroundStyle
        }.value
    }

    // RATIONALE: Uses removeItem (permanent delete) rather than trashItem because these are
    // ephemeral cache files in the Caches directory that the system can already purge at will.
    func deleteCachedIcon(for feedID: UUID) {
        let fileURL = iconFileURL(for: feedID)
        do {
            try FileManager.default.removeItem(at: fileURL)
            Self.logger.debug("Deleted cached icon for feed \(feedID.uuidString, privacy: .public)")
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            // File already absent — nothing to clean up
        } catch {
            Self.logger.warning("Failed to delete cached icon for feed \(feedID.uuidString, privacy: .public): \(error, privacy: .public)")
        }
    }

    // MARK: - Internal (visible to tests)

    /// Result of parsing a site's homepage HTML for icon-related URLs.
    struct HTMLIconResult {
        /// Icon URLs extracted from `<link>` tags, ordered by priority: apple-touch-icon first, then rel="icon".
        let linkIcons: [URL]
        /// The `og:image` URL from `<meta property="og:image">`, if present.
        /// Resolved against the page's base URL to handle protocol-relative and relative URLs.
        let ogImageURL: URL?
        /// The host of the final URL after redirects, if it differs from the
        /// requested host (indicates a platform-hosted blog like Medium/Substack).
        let redirectedHost: String?
    }

    /// Assembles icon candidate URLs in priority order from the given inputs.
    /// Pure function — no I/O — enabling direct unit testing of the ordering logic.
    static func assembleCandidates(
        feedSiteURL: URL?,
        feedImageURL: URL?,
        htmlResult: HTMLIconResult?
    ) -> [URL] {
        var candidates: [URL] = []

        // Priority 1: Image URL from feed XML
        if let feedImageURL, feedImageURL.scheme == "http" || feedImageURL.scheme == "https" {
            candidates.append(normalizeIconURL(feedImageURL))
        }

        if let htmlResult {
            // Priority 2: og:image from homepage — often blog-specific branding, which
            // survives platform redirects (Medium, Substack, Ghost) better than link icons
            if let ogImageURL = htmlResult.ogImageURL {
                candidates.append(ogImageURL)
            }

            // Priority 3: HTML link icons (apple-touch-icon first, then rel="icon")
            candidates.append(contentsOf: htmlResult.linkIcons)
        }

        // Priority 4: /favicon.ico fallback from the original site host
        if let siteURL = feedSiteURL,
           let host = siteURL.host(percentEncoded: false),
           !host.isEmpty,
           let faviconURL = URL(string: "\(siteURL.scheme ?? "https")://\(host)/favicon.ico") {
            candidates.append(faviconURL)
        }

        // Priority 5: When a cross-domain redirect occurred (e.g., bothsidesofthetable.com
        // → medium.com), also try the redirected host's /favicon.ico as a last resort
        // RATIONALE: The host inequality check is redundant with HTMLIconResult's own guard,
        // but kept as a defensive safety net in case the struct's construction logic changes.
        if let redirectedHost = htmlResult?.redirectedHost,
           let siteURL = feedSiteURL,
           redirectedHost != siteURL.host(percentEncoded: false),
           let faviconURL = URL(string: "\(siteURL.scheme ?? "https")://\(redirectedHost)/favicon.ico") {
            candidates.append(faviconURL)
        }

        return candidates
    }

    // MARK: - Private

    private func resolveFromHTML(siteURL: URL) async -> HTMLIconResult? {
        do {
            var request = URLRequest(url: siteURL, timeoutInterval: Self.htmlFetchTimeout)
            request.setBrowserUserAgent()
            let (bytes, response) = try await URLSession.shared.bytes(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                Self.logger.warning("Site HTML fetch returned HTTP \(code, privacy: .public) for \(siteURL.absoluteString, privacy: .public)")
                return nil
            }

            // Use the final URL (after redirects) as the base for resolving relative hrefs
            let baseURL = httpResponse.url ?? siteURL

            // Read only the first portion — icon metadata is in <head>, no need for the full body
            var collected = Data()
            collected.reserveCapacity(Self.htmlHeadMaxBytes)
            for try await byte in bytes {
                collected.append(byte)
                if collected.count >= Self.htmlHeadMaxBytes { break }
            }

            guard let html = String(data: collected, encoding: .utf8) else {
                let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "unknown"
                Self.logger.warning("Failed to decode site HTML as UTF-8 (\(contentType, privacy: .public), \(collected.count, privacy: .public) bytes) from \(siteURL.absoluteString, privacy: .public)")
                return nil
            }

            let linkIcons = HTMLUtilities.extractIconURLs(from: html, baseURL: baseURL)
            let ogImageURL = HTMLUtilities.extractOGImageURL(from: html, baseURL: baseURL)

            // Detect cross-domain redirects (e.g., bothsidesofthetable.com → medium.com)
            let originalHost = siteURL.host(percentEncoded: false)
            let finalHost = baseURL.host(percentEncoded: false)
            let redirectedHost: String?
            if let originalHost, let finalHost, originalHost != finalHost {
                Self.logger.debug("Cross-domain redirect detected: \(originalHost, privacy: .public) → \(finalHost, privacy: .public)")
                redirectedHost = finalHost
            } else {
                redirectedHost = nil
            }

            return HTMLIconResult(
                linkIcons: linkIcons,
                ogImageURL: ogImageURL,
                redirectedHost: redirectedHost
            )
        } catch {
            Self.logger.warning("Failed to fetch site HTML from \(siteURL.absoluteString, privacy: .public): \(error, privacy: .public)")
            return nil
        }
    }

    /// Strips trailing slashes from icon URLs that some feeds incorrectly append
    /// (e.g., `icon.png/` → `icon.png`).
    private static func normalizeIconURL(_ url: URL) -> URL {
        var path = url.path(percentEncoded: false)
        while path.hasSuffix("/") && path != "/" {
            path = String(path.dropLast())
        }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: true)
        components?.path = path
        return components?.url ?? url
    }

    /// Decodes an ICO file by extracting the largest embedded image.
    /// ICO files contain a directory of images (PNG or BMP) at various sizes.
    static func decodeICO(_ data: Data) -> UIImage? {
        // ICO header: 2 bytes reserved (0), 2 bytes type (1 = icon), 2 bytes image count
        guard data.count >= 6 else { return nil }
        let reserved = UInt16(data[0]) | UInt16(data[1]) << 8
        let type = UInt16(data[2]) | UInt16(data[3]) << 8
        let count = UInt16(data[4]) | UInt16(data[5]) << 8
        guard reserved == 0, type == 1, count > 0 else { return nil }

        // Each directory entry is 16 bytes, starting at offset 6
        let headerSize = 6
        let entrySize = 16
        guard data.count >= headerSize + Int(count) * entrySize else { return nil }

        // Find the largest image entry by pixel area
        var bestArea = 0
        var bestOffset: UInt32 = 0
        var bestSize: UInt32 = 0

        for i in 0..<Int(count) {
            let base = headerSize + i * entrySize
            // Width/height of 0 means 256
            let w = data[base] == 0 ? 256 : Int(data[base])
            let h = data[base + 1] == 0 ? 256 : Int(data[base + 1])
            let area = w * h

            let bytesInRes = UInt32(data[base + 8])
                | UInt32(data[base + 9]) << 8
                | UInt32(data[base + 10]) << 16
                | UInt32(data[base + 11]) << 24
            let imageOffset = UInt32(data[base + 12])
                | UInt32(data[base + 13]) << 8
                | UInt32(data[base + 14]) << 16
                | UInt32(data[base + 15]) << 24

            if area > bestArea {
                bestArea = area
                bestOffset = imageOffset
                bestSize = bytesInRes
            }
        }

        guard bestSize > 0,
              Int(bestOffset) + Int(bestSize) <= data.count else { return nil }

        let imageData = data[Int(bestOffset)..<Int(bestOffset) + Int(bestSize)]

        // Try PNG first (many modern ICOs embed PNG), then fall back to raw data
        if let image = UIImage(data: Data(imageData)) {
            logger.debug("Decoded ICO image (PNG-embedded, \(bestArea)px area)")
            return image
        }

        // BMP in ICO: starts with BITMAPINFOHEADER (40 bytes).
        // Wrap it in a proper BMP file so UIImage can decode it.
        if imageData.count > 40 {
            if let image = decodeBMPFromICO(Data(imageData), width: Int(sqrt(Double(bestArea)))) {
                logger.debug("Decoded ICO image (BMP, \(bestArea)px area)")
                return image
            }
        }

        return nil
    }

    /// Decodes a BMP image entry from an ICO file.
    /// ICO BMP entries omit the 14-byte BITMAPFILEHEADER and use doubled height
    /// (to account for the AND mask). This method prepends the file header and
    /// fixes the height before decoding via `UIImage(data:)`.
    private static func decodeBMPFromICO(_ bmpData: Data, width: Int) -> UIImage? {
        guard bmpData.count >= 40 else { return nil }

        // Read BITMAPINFOHEADER fields
        var header = bmpData.prefix(40)
        let biHeight = Int32(bitPattern:
            UInt32(header[8]) | UInt32(header[9]) << 8
            | UInt32(header[10]) << 16 | UInt32(header[11]) << 24
        )

        // ICO doubles the height to include the AND mask — halve it
        let realHeight = abs(biHeight) / 2
        let correctedHeight = UInt32(bitPattern: Int32(realHeight))
        header[8] = UInt8(correctedHeight & 0xFF)
        header[9] = UInt8((correctedHeight >> 8) & 0xFF)
        header[10] = UInt8((correctedHeight >> 16) & 0xFF)
        header[11] = UInt8((correctedHeight >> 24) & 0xFF)

        // Build a full BMP file: 14-byte file header + corrected BITMAPINFOHEADER + pixel data
        let pixelDataOffset: UInt32 = 14 + 40
        let fileSize = UInt32(14 + bmpData.count)
        var bmpFile = Data(capacity: Int(fileSize))
        // BITMAPFILEHEADER (14 bytes)
        bmpFile.append(contentsOf: [0x42, 0x4D]) // "BM"
        bmpFile.append(contentsOf: withUnsafeBytes(of: fileSize.littleEndian) { Array($0) })
        bmpFile.append(contentsOf: [0, 0, 0, 0]) // reserved
        bmpFile.append(contentsOf: withUnsafeBytes(of: pixelDataOffset.littleEndian) { Array($0) })
        // Corrected header + rest of pixel data
        bmpFile.append(header)
        bmpFile.append(bmpData.dropFirst(40))

        return UIImage(data: bmpFile)
    }

    /// Result of a single-pass bitmap walk: whether the image has visible
    /// opaque content and the average luminance of its opaque pixels.
    ///
    /// `averageLuminance` is meaningful only when `isVisible == true`. When the
    /// image is fully transparent, the walk produces `averageLuminance == 0`
    /// and the caller should ignore it. Values are in `[0, 1]`, computed over
    /// premultiplied-alpha-adjusted RGB using ITU-R BT.601 coefficients.
    struct IconPixelStats: Equatable {
        let isVisible: Bool
        let averageLuminance: Double
    }

    /// Returns `false` if the image is fully or mostly transparent (e.g., a tracking pixel
    /// or placeholder favicon). Pixels with alpha > 25 (out of 255) are considered visible;
    /// at least 1% of pixels must be visible for the image to pass.
    /// Returns `true` when CGContext inspection fails — accept-on-failure matches the
    /// legacy semantic so bitmap-inspection glitches don't drop otherwise-valid icons.
    static func hasVisibleContent(_ image: UIImage) -> Bool {
        analyzeIconPixels(image).isVisible
    }

    /// Walks the image bitmap once to compute visibility and the average
    /// luminance of opaque pixels.
    ///
    /// Combines the visibility gate and luminance analysis in a single pass
    /// so `cacheIcon` doesn't need to allocate a second bitmap to classify
    /// the icon's background style (issue #342).
    ///
    /// RATIONALE: On CGContext-allocation failure (rare — memory pressure or
    /// CIImage-backed UIImage with no CGImage) this returns a sentinel
    /// `IconPixelStats(isVisible: true, averageLuminance: 1.0)` rather than
    /// signalling failure. The accept-on-failure stance preserves the pre-PR
    /// `hasVisibleContent` semantic: a transient inspection failure should not
    /// drop an image that decoded successfully. Sentinel luminance 1.0 sits
    /// above `iconLightBackgroundLuminanceThreshold` so `classifyBackgroundStyle`
    /// returns `.dark` → black tile, matching the pre-classifier rendering
    /// for feeds that existed before this feature shipped.
    static func analyzeIconPixels(_ image: UIImage, feedID: UUID? = nil) -> IconPixelStats {
        let feedIDDesc = feedID?.uuidString ?? "unknown"
        guard let cgImage = image.cgImage else {
            logger.warning("analyzeIconPixels: image has no CGImage backing for feed \(feedIDDesc, privacy: .public) — defaulting to neutral stats")
            return IconPixelStats(isVisible: true, averageLuminance: 1.0)
        }
        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0 else {
            return IconPixelStats(isVisible: false, averageLuminance: 0)
        }

        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixelData = [UInt8](repeating: 0, count: height * bytesPerRow)

        return pixelData.withUnsafeMutableBytes { ptr -> IconPixelStats in
            guard let context = CGContext(
                data: ptr.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                logger.warning("analyzeIconPixels: CGContext creation failed for \(width)x\(height) image (feed \(feedIDDesc, privacy: .public)) — defaulting to neutral stats")
                return IconPixelStats(isVisible: true, averageLuminance: 1.0)
            }

            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

            let totalPixels = width * height
            var opaquePixels = 0
            var luminanceSum: Double = 0
            let alphaThreshold: UInt8 = 25
            // ITU-R BT.601 luminance coefficients
            let redWeight = 0.299
            let greenWeight = 0.587
            let blueWeight = 0.114

            for i in stride(from: 0, to: ptr.count, by: bytesPerPixel) {
                let alpha = ptr[i + 3]
                guard alpha > alphaThreshold else { continue }
                opaquePixels += 1
                // Context is premultipliedLast — divide by alpha to recover the
                // original color so dark-on-semitransparent strokes contribute
                // their true color, not a washed-out value. Clamp to [0, 1] to
                // match the doc comment's guarantee — bitmap roundtrip rounding
                // can leave channel/alpha values fractionally out of range.
                let alphaFraction = Double(alpha) / 255.0
                let r = min(1.0, Double(ptr[i]) / 255.0 / alphaFraction)
                let g = min(1.0, Double(ptr[i + 1]) / 255.0 / alphaFraction)
                let b = min(1.0, Double(ptr[i + 2]) / 255.0 / alphaFraction)
                luminanceSum += redWeight * r + greenWeight * g + blueWeight * b
            }

            let isVisible = Double(opaquePixels) / Double(totalPixels) >= 0.01
            let averageLuminance = opaquePixels > 0 ? luminanceSum / Double(opaquePixels) : 0
            return IconPixelStats(isVisible: isVisible, averageLuminance: averageLuminance)
        }
    }

    /// Luminance threshold above which an icon is considered "light enough"
    /// to need a dark (black) background behind it. Icons at or below the
    /// threshold get a light (white) background so their dark strokes stay
    /// visible where the PNG has transparency. 0.7 separates Apple-Insider-
    /// style white-on-transparent logos (≈1.0 average) from dark flat icons
    /// (≈0.2–0.4) in issue #342 test data.
    static let iconLightBackgroundLuminanceThreshold: Double = 0.7

    /// Maps an average luminance value to a `FeedIconBackgroundStyle`.
    /// Centralized so the threshold and the classification rule live in one
    /// place and tests can pin the boundary without reaching into `cacheIcon`.
    static func classifyBackgroundStyle(averageLuminance: Double) -> FeedIconBackgroundStyle {
        averageLuminance > iconLightBackgroundLuminanceThreshold ? .dark : .light
    }

    private func normalizeImage(_ image: UIImage) -> UIImage {
        let maxDim = Self.maxIconDimension
        guard image.size.width > maxDim || image.size.height > maxDim else {
            return image
        }
        let scale = min(maxDim / image.size.width, maxDim / image.size.height)
        let newSize = CGSize(
            width: (image.size.width * scale).rounded(),
            height: (image.size.height * scale).rounded()
        )
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    private func iconFileURL(for feedID: UUID) -> URL {
        cacheDirectory.appendingPathComponent("\(feedID.uuidString).png")
    }

    private var cacheDirectory: URL {
        if let cacheDirectoryOverride {
            return cacheDirectoryOverride
        }
        return FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Self.iconCacheDirectoryName)
    }

    private func ensureCacheDirectoryExists() throws {
        try FileManager.default.createDirectory(
            at: cacheDirectory,
            withIntermediateDirectories: true
        )
    }
}
