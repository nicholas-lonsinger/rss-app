import CryptoKit
import Foundation
import os
import UIKit

// MARK: - Result Type

/// Outcome of a single thumbnail cache attempt, distinguishing permanent from transient failures
/// so callers can decide whether to retry.
enum ThumbnailCacheResult: Sendable {
    /// Thumbnail was successfully downloaded and cached.
    case cached
    /// A transient failure occurred (5xx, timeout, network error) — worth retrying.
    case transientFailure
    /// A permanent failure occurred (4xx, invalid image data, bad URL scheme) — retrying won't help.
    case permanentFailure
}

// MARK: - Protocol

protocol ArticleThumbnailCaching: Sendable {

    /// Downloads the image at `remoteURL`, resizes it to thumbnail dimensions,
    /// and caches it to disk under a hash of the article ID.
    func cacheThumbnail(from remoteURL: URL, articleID: String) async -> ThumbnailCacheResult

    /// Resolves and caches a thumbnail: tries `thumbnailURL` first, then fetches
    /// the article page at `articleLink` to extract `og:image` as a fallback.
    func resolveAndCacheThumbnail(thumbnailURL: URL?, articleLink: URL?, articleID: String) async -> ThumbnailCacheResult

    /// Returns the local file URL for a cached thumbnail, or `nil` if not cached.
    func cachedThumbnailFileURL(for articleID: String) -> URL?

    /// Deletes the cached thumbnail file for the given article.
    func deleteCachedThumbnail(for articleID: String)
}

// MARK: - Implementation

struct ArticleThumbnailService: ArticleThumbnailCaching {

    private static let logger = Logger(category: "ArticleThumbnailService")

    private static let cacheDirectoryName = "article-thumbnails"
    private static let fetchTimeout: TimeInterval = 15
    private static let thumbnailDimension: CGFloat = 120 // 2× retina for 60pt display
    private static let jpegQuality: CGFloat = 0.8

    // MARK: - ArticleThumbnailCaching

    func cacheThumbnail(from remoteURL: URL, articleID: String) async -> ThumbnailCacheResult {
        Self.logger.debug("cacheThumbnail() from \(remoteURL.absoluteString, privacy: .public) for article \(articleID, privacy: .public)")

        guard remoteURL.scheme == "http" || remoteURL.scheme == "https" else {
            Self.logger.warning("Rejecting non-HTTP URL scheme '\(remoteURL.scheme ?? "nil", privacy: .public)' for \(remoteURL.absoluteString, privacy: .public)")
            return .permanentFailure
        }

        do {
            var request = URLRequest(url: remoteURL, timeoutInterval: Self.fetchTimeout)
            request.setBrowserUserAgent()
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                Self.logger.warning("Thumbnail fetch returned HTTP \(code, privacy: .public) for \(remoteURL.absoluteString, privacy: .public)")
                return (400...499).contains(code) ? .permanentFailure : .transientFailure
            }

            guard let image = UIImage(data: data) else {
                let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "unknown"
                Self.logger.warning("Downloaded data is not a valid image (\(contentType, privacy: .public), \(data.count, privacy: .public) bytes) from \(remoteURL.absoluteString, privacy: .public)")
                return .permanentFailure
            }

            let thumbnail = cropAndResize(image)
            guard let jpegData = thumbnail.jpegData(compressionQuality: Self.jpegQuality) else {
                Self.logger.warning("Failed to generate JPEG data from thumbnail")
                return .permanentFailure
            }

            let fileURL = thumbnailFileURL(for: articleID)
            try ensureCacheDirectoryExists()
            try jpegData.write(to: fileURL, options: .atomic)

            Self.logger.debug("Cached thumbnail for article \(articleID, privacy: .public) (\(jpegData.count, privacy: .public) bytes)")
            return .cached
        } catch {
            Self.logger.warning("Failed to cache thumbnail for \(remoteURL.absoluteString, privacy: .public): \(error, privacy: .public)")
            return .transientFailure
        }
    }

    func resolveAndCacheThumbnail(thumbnailURL: URL?, articleLink: URL?, articleID: String) async -> ThumbnailCacheResult {
        Self.logger.debug("resolveAndCacheThumbnail() thumbnailURL=\(thumbnailURL?.absoluteString ?? "nil", privacy: .public) articleLink=\(articleLink?.absoluteString ?? "nil", privacy: .public) articleID=\(articleID, privacy: .public)")

        var sawTransient = false

        // Priority 1: Direct thumbnail URL from feed
        if let thumbnailURL {
            let result = await cacheThumbnail(from: thumbnailURL, articleID: articleID)
            if result == .cached { return .cached }
            if result == .transientFailure { sawTransient = true }
        }

        // Priority 2: Fetch article page and extract og:image
        if let articleLink {
            if let ogImageURL = await resolveOGImage(from: articleLink) {
                let result = await cacheThumbnail(from: ogImageURL, articleID: articleID)
                if result == .cached { return .cached }
                if result == .transientFailure { sawTransient = true }
            }
        }

        return sawTransient ? .transientFailure : .permanentFailure
    }

    func cachedThumbnailFileURL(for articleID: String) -> URL? {
        let fileURL = thumbnailFileURL(for: articleID)
        return FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) ? fileURL : nil
    }

    // RATIONALE: Uses removeItem (permanent delete) rather than trashItem because these are
    // ephemeral cache files in the Caches directory that the system can already purge at will.
    func deleteCachedThumbnail(for articleID: String) {
        let fileURL = thumbnailFileURL(for: articleID)
        do {
            try FileManager.default.removeItem(at: fileURL)
            Self.logger.debug("Deleted cached thumbnail for article \(articleID, privacy: .public)")
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            // File already absent — nothing to clean up
        } catch {
            Self.logger.warning("Failed to delete cached thumbnail for article \(articleID, privacy: .public): \(error, privacy: .public)")
        }
    }

    // MARK: - Image Processing

    /// Aspect-fill crops and resizes the image to a square thumbnail.
    private func cropAndResize(_ image: UIImage) -> UIImage {
        let targetSize = CGSize(width: Self.thumbnailDimension, height: Self.thumbnailDimension)

        // Only skip if already the correct size and square
        guard image.size != targetSize else {
            return image
        }

        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            // Scale to fill the target square (aspect-fill), then center-crop
            let scale = max(targetSize.width / image.size.width, targetSize.height / image.size.height)
            let scaledSize = CGSize(
                width: (image.size.width * scale).rounded(),
                height: (image.size.height * scale).rounded()
            )
            let origin = CGPoint(
                x: ((targetSize.width - scaledSize.width) / 2).rounded(),
                y: ((targetSize.height - scaledSize.height) / 2).rounded()
            )
            image.draw(in: CGRect(origin: origin, size: scaledSize))
        }
    }

    // MARK: - OG Image Resolution

    private static let htmlFetchTimeout: TimeInterval = 10

    /// The og:image meta tag is in the `<head>`, so we only need the first portion of the page.
    private static let htmlHeadMaxBytes = 51_200 // 50 KB

    /// Fetches the beginning of an article page and extracts the `og:image` meta tag URL.
    private func resolveOGImage(from articleLink: URL) async -> URL? {
        Self.logger.debug("Resolving og:image from \(articleLink.absoluteString, privacy: .public)")

        do {
            var request = URLRequest(url: articleLink, timeoutInterval: Self.htmlFetchTimeout)
            request.setBrowserUserAgent()
            let (bytes, response) = try await URLSession.shared.bytes(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                Self.logger.warning("Article page fetch returned HTTP \(code, privacy: .public) for \(articleLink.absoluteString, privacy: .public)")
                return nil
            }

            // Read only the first portion — og:image is in <head>, no need for the full body
            var collected = Data()
            collected.reserveCapacity(Self.htmlHeadMaxBytes)
            for try await byte in bytes {
                collected.append(byte)
                if collected.count >= Self.htmlHeadMaxBytes { break }
            }

            guard let html = String(data: collected, encoding: .utf8) else {
                Self.logger.warning("Article page response is not valid UTF-8 from \(articleLink.absoluteString, privacy: .public)")
                return nil
            }
            return HTMLUtilities.extractOGImageURL(from: html, baseURL: articleLink)
        } catch {
            Self.logger.warning("Failed to fetch article page for og:image: \(error, privacy: .public)")
            return nil
        }
    }

    // MARK: - File System

    private func thumbnailFileURL(for articleID: String) -> URL {
        let hash = SHA256.hash(data: Data(articleID.utf8))
        let filename = hash.compactMap { String(format: "%02x", $0) }.joined()
        return cacheDirectory.appendingPathComponent("\(filename).jpg")
    }

    private var cacheDirectory: URL {
        guard let cachesURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            Self.logger.fault("System caches directory not available")
            assertionFailure("System caches directory not available")
            return URL.temporaryDirectory.appendingPathComponent(Self.cacheDirectoryName)
        }
        return cachesURL.appendingPathComponent(Self.cacheDirectoryName)
    }

    private func ensureCacheDirectoryExists() throws {
        try FileManager.default.createDirectory(
            at: cacheDirectory,
            withIntermediateDirectories: true
        )
    }
}
