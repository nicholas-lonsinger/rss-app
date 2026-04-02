import Foundation
import os
import UIKit

// MARK: - Protocol

protocol FeedIconResolving: Sendable {

    /// Resolves an icon URL from multiple sources in priority order:
    /// feed XML image → site HTML meta tags → /favicon.ico fallback.
    func resolveIconURL(feedSiteURL: URL?, feedImageURL: URL?) async -> URL?

    /// Downloads the image at `remoteURL`, normalizes it to PNG, and caches it
    /// to disk under the feed's UUID. Returns `true` on success.
    func cacheIcon(from remoteURL: URL, feedID: UUID) async -> Bool

    /// Returns the local file URL for a cached icon, or `nil` if not cached.
    func cachedIconFileURL(for feedID: UUID) -> URL?

    /// Deletes the cached icon file for the given feed.
    func deleteCachedIcon(for feedID: UUID)
}

// MARK: - Implementation

struct FeedIconService: FeedIconResolving {

    private static let logger = Logger(
        subsystem: "com.nicholas-lonsinger.rss-app",
        category: "FeedIconService"
    )

    private static let iconCacheDirectoryName = "feed-icons"
    private static let htmlFetchTimeout: TimeInterval = 10
    private static let iconFetchTimeout: TimeInterval = 15
    private static let maxIconDimension: CGFloat = 128

    // MARK: - FeedIconResolving

    func resolveIconURL(feedSiteURL: URL?, feedImageURL: URL?) async -> URL? {
        Self.logger.debug("resolveIconURL() feedImageURL=\(feedImageURL?.absoluteString ?? "nil", privacy: .public) siteURL=\(feedSiteURL?.absoluteString ?? "nil", privacy: .public)")

        // Build candidate URLs in priority order, then return the first one that works
        var candidates: [URL] = []

        // Priority 1: Image URL from feed XML
        if let feedImageURL, feedImageURL.scheme == "http" || feedImageURL.scheme == "https" {
            candidates.append(Self.normalizeIconURL(feedImageURL))
        }

        // Priority 2: Parse site homepage HTML for icon links
        if let siteURL = feedSiteURL {
            let htmlIcons = await resolveFromHTML(siteURL: siteURL)
            candidates.append(contentsOf: htmlIcons)
        }

        // Priority 3: Fallback to /favicon.ico
        if let siteURL = feedSiteURL,
           let host = siteURL.host(percentEncoded: false),
           !host.isEmpty,
           let faviconURL = URL(string: "\(siteURL.scheme ?? "https")://\(host)/favicon.ico") {
            candidates.append(faviconURL)
        }

        // Try each candidate — return the first one that responds with a valid image
        for candidate in candidates {
            if await isDownloadable(candidate) {
                Self.logger.debug("Resolved icon: \(candidate.absoluteString, privacy: .public)")
                return candidate
            }
            Self.logger.debug("Candidate failed: \(candidate.absoluteString, privacy: .public)")
        }

        Self.logger.debug("No icon URL could be resolved")
        return nil
    }

    func cacheIcon(from remoteURL: URL, feedID: UUID) async -> Bool {
        Self.logger.debug("cacheIcon() from \(remoteURL.absoluteString, privacy: .public) for feed \(feedID.uuidString, privacy: .public)")

        do {
            let request = URLRequest(url: remoteURL, timeoutInterval: Self.iconFetchTimeout)
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                Self.logger.debug("Icon fetch failed with non-2xx status")
                return false
            }

            guard let image = UIImage(data: data) ?? Self.decodeICO(data) else {
                Self.logger.debug("Downloaded data is not a valid image")
                return false
            }

            // Normalize: resize if too large, convert to PNG
            let normalized = normalizeImage(image)
            guard let pngData = normalized.pngData() else {
                Self.logger.warning("Failed to generate PNG data from image")
                return false
            }

            let fileURL = iconFileURL(for: feedID)
            try ensureCacheDirectoryExists()
            try pngData.write(to: fileURL, options: .atomic)

            Self.logger.debug("Cached icon for feed \(feedID.uuidString, privacy: .public) (\(pngData.count, privacy: .public) bytes)")
            return true
        } catch {
            Self.logger.debug("Failed to cache icon: \(error, privacy: .public)")
            return false
        }
    }

    func cachedIconFileURL(for feedID: UUID) -> URL? {
        let fileURL = iconFileURL(for: feedID)
        return FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) ? fileURL : nil
    }

    func deleteCachedIcon(for feedID: UUID) {
        let fileURL = iconFileURL(for: feedID)
        try? FileManager.default.removeItem(at: fileURL)
        Self.logger.debug("Deleted cached icon for feed \(feedID.uuidString, privacy: .public)")
    }

    // MARK: - Private

    private func resolveFromHTML(siteURL: URL) async -> [URL] {
        do {
            let request = URLRequest(url: siteURL, timeoutInterval: Self.htmlFetchTimeout)
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                return []
            }

            // Use the final URL (after redirects) as the base for resolving relative hrefs
            let baseURL = httpResponse.url ?? siteURL

            guard let html = String(data: data, encoding: .utf8) else { return [] }
            return HTMLUtilities.extractIconURLs(from: html, baseURL: baseURL)
        } catch {
            Self.logger.debug("Failed to fetch site HTML: \(error, privacy: .public)")
            return []
        }
    }

    /// Strips trailing slashes from icon URLs (e.g., `icon.png/` → `icon.png`).
    private static func normalizeIconURL(_ url: URL) -> URL {
        var path = url.path(percentEncoded: false)
        while path.hasSuffix("/") && path != "/" {
            path = String(path.dropLast())
        }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: true)
        components?.path = path
        return components?.url ?? url
    }

    /// Quick HEAD request to verify a URL returns a 2xx response with image content.
    private func isDownloadable(_ url: URL) async -> Bool {
        do {
            var request = URLRequest(url: url, timeoutInterval: Self.iconFetchTimeout)
            request.httpMethod = "HEAD"
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return false }
            return (200...299).contains(httpResponse.statusCode)
        } catch {
            return false
        }
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
        // Wrap it in a proper BMP file so CGImage can decode it.
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
    /// fixes the height before passing to CGDataProvider.
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
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Self.iconCacheDirectoryName)
    }

    private func ensureCacheDirectoryExists() throws {
        try FileManager.default.createDirectory(
            at: cacheDirectory,
            withIntermediateDirectories: true
        )
    }
}
