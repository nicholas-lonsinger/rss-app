import Foundation
import os
import UIKit

// MARK: - Protocol

protocol FeedIconResolving: Sendable {

    /// Returns candidate icon URLs from multiple sources in priority order:
    /// feed XML image → site HTML link tags → /favicon.ico fallback.
    /// Callers should try each URL until one successfully downloads.
    func resolveIconCandidates(feedSiteURL: URL?, feedImageURL: URL?) async -> [URL]

    /// Downloads the image at `remoteURL`, normalizes it to PNG, and caches it
    /// to disk under the feed's UUID. Returns `true` on success.
    func cacheIcon(from remoteURL: URL, feedID: UUID) async -> Bool

    /// Returns the local file URL for a cached icon, or `nil` if not cached.
    func cachedIconFileURL(for feedID: UUID) -> URL?

    /// Resolves candidate icon URLs and caches the first one that downloads successfully.
    /// Returns the remote URL of the cached icon, or `nil` if no candidate could be cached.
    func resolveAndCacheIcon(feedSiteURL: URL?, feedImageURL: URL?, feedID: UUID) async -> URL?

    /// Deletes the cached icon file for the given feed.
    func deleteCachedIcon(for feedID: UUID)
}

// MARK: - Implementation

struct FeedIconService: FeedIconResolving {

    private static let logger = Logger(category: "FeedIconService")

    private static let iconCacheDirectoryName = "feed-icons"
    private static let htmlFetchTimeout: TimeInterval = 10
    private static let iconFetchTimeout: TimeInterval = 15
    private static let maxIconDimension: CGFloat = 128

    // MARK: - FeedIconResolving

    func resolveIconCandidates(feedSiteURL: URL?, feedImageURL: URL?) async -> [URL] {
        Self.logger.debug("resolveIconCandidates() feedImageURL=\(feedImageURL?.absoluteString ?? "nil", privacy: .public) siteURL=\(feedSiteURL?.absoluteString ?? "nil", privacy: .public)")

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

        Self.logger.debug("Found \(candidates.count, privacy: .public) icon candidates")
        return candidates
    }

    func cacheIcon(from remoteURL: URL, feedID: UUID) async -> Bool {
        Self.logger.debug("cacheIcon() from \(remoteURL.absoluteString, privacy: .public) for feed \(feedID.uuidString, privacy: .public)")

        do {
            let request = URLRequest(url: remoteURL, timeoutInterval: Self.iconFetchTimeout)
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                Self.logger.warning("Icon fetch returned HTTP \(code, privacy: .public) for \(remoteURL.absoluteString, privacy: .public)")
                return false
            }

            guard let image = UIImage(data: data) ?? Self.decodeICO(data) else {
                let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "unknown"
                Self.logger.warning("Downloaded data is not a valid image (\(contentType, privacy: .public), \(data.count, privacy: .public) bytes) from \(remoteURL.absoluteString, privacy: .public)")
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
            Self.logger.warning("Failed to cache icon for \(remoteURL.absoluteString, privacy: .public): \(error, privacy: .public)")
            return false
        }
    }

    func cachedIconFileURL(for feedID: UUID) -> URL? {
        let fileURL = iconFileURL(for: feedID)
        return FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) ? fileURL : nil
    }

    func resolveAndCacheIcon(feedSiteURL: URL?, feedImageURL: URL?, feedID: UUID) async -> URL? {
        let candidates = await resolveIconCandidates(feedSiteURL: feedSiteURL, feedImageURL: feedImageURL)
        for candidate in candidates {
            let cached = await cacheIcon(from: candidate, feedID: feedID)
            if cached {
                return candidate
            }
        }
        Self.logger.debug("No icon cached for feed \(feedID.uuidString, privacy: .public) (\(candidates.count, privacy: .public) candidates tried)")
        return nil
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
            Self.logger.warning("Failed to fetch site HTML from \(siteURL.absoluteString, privacy: .public): \(error, privacy: .public)")
            return []
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
