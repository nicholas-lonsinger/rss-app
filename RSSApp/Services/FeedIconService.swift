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

        // Priority 1: Image URL from feed XML
        if let feedImageURL, feedImageURL.scheme == "http" || feedImageURL.scheme == "https" {
            Self.logger.debug("Using feed XML image URL")
            return feedImageURL
        }

        // Priority 2: Parse site homepage HTML for icon links
        if let siteURL = feedSiteURL, let htmlIconURL = await resolveFromHTML(siteURL: siteURL) {
            Self.logger.debug("Resolved icon from site HTML: \(htmlIconURL.absoluteString, privacy: .public)")
            return htmlIconURL
        }

        // Priority 3: Fallback to /favicon.ico
        if let siteURL = feedSiteURL,
           let host = siteURL.host(percentEncoded: false),
           !host.isEmpty {
            let faviconURL = URL(string: "\(siteURL.scheme ?? "https")://\(host)/favicon.ico")
            Self.logger.debug("Falling back to favicon.ico: \(faviconURL?.absoluteString ?? "nil", privacy: .public)")
            return faviconURL
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

            guard let image = UIImage(data: data) else {
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

    private func resolveFromHTML(siteURL: URL) async -> URL? {
        do {
            let request = URLRequest(url: siteURL, timeoutInterval: Self.htmlFetchTimeout)
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                return nil
            }

            // Use the final URL (after redirects) as the base for resolving relative hrefs
            let baseURL = httpResponse.url ?? siteURL

            guard let html = String(data: data, encoding: .utf8) else { return nil }
            let icons = HTMLUtilities.extractIconURLs(from: html, baseURL: baseURL)
            return icons.first
        } catch {
            Self.logger.debug("Failed to fetch site HTML: \(error, privacy: .public)")
            return nil
        }
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
