import CryptoKit
import Foundation
import os
import UIKit

// MARK: - Protocol

protocol ArticleThumbnailCaching: Sendable {

    /// Downloads the image at `remoteURL`, resizes it to thumbnail dimensions,
    /// and caches it to disk under a hash of the article ID. Returns `true` on success.
    func cacheThumbnail(from remoteURL: URL, articleID: String) async -> Bool

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

    func cacheThumbnail(from remoteURL: URL, articleID: String) async -> Bool {
        Self.logger.debug("cacheThumbnail() from \(remoteURL.absoluteString, privacy: .public) for article \(articleID, privacy: .public)")

        do {
            let request = URLRequest(url: remoteURL, timeoutInterval: Self.fetchTimeout)
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                Self.logger.warning("Thumbnail fetch returned HTTP \(code, privacy: .public) for \(remoteURL.absoluteString, privacy: .public)")
                return false
            }

            guard let image = UIImage(data: data) else {
                let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "unknown"
                Self.logger.warning("Downloaded data is not a valid image (\(contentType, privacy: .public), \(data.count, privacy: .public) bytes) from \(remoteURL.absoluteString, privacy: .public)")
                return false
            }

            let thumbnail = cropAndResize(image)
            guard let jpegData = thumbnail.jpegData(compressionQuality: Self.jpegQuality) else {
                Self.logger.warning("Failed to generate JPEG data from thumbnail")
                return false
            }

            let fileURL = thumbnailFileURL(for: articleID)
            try ensureCacheDirectoryExists()
            try jpegData.write(to: fileURL, options: .atomic)

            Self.logger.debug("Cached thumbnail for article \(articleID, privacy: .public) (\(jpegData.count, privacy: .public) bytes)")
            return true
        } catch {
            Self.logger.warning("Failed to cache thumbnail for \(remoteURL.absoluteString, privacy: .public): \(error, privacy: .public)")
            return false
        }
    }

    func cachedThumbnailFileURL(for articleID: String) -> URL? {
        let fileURL = thumbnailFileURL(for: articleID)
        return FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) ? fileURL : nil
    }

    func deleteCachedThumbnail(for articleID: String) {
        let fileURL = thumbnailFileURL(for: articleID)
        try? FileManager.default.removeItem(at: fileURL)
    }

    // MARK: - Image Processing

    /// Aspect-fill crops and resizes the image to a square thumbnail.
    private func cropAndResize(_ image: UIImage) -> UIImage {
        let targetSize = CGSize(width: Self.thumbnailDimension, height: Self.thumbnailDimension)

        // Images already at or below target size don't need processing
        guard image.size.width > targetSize.width || image.size.height > targetSize.height else {
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

    // MARK: - File System

    private func thumbnailFileURL(for articleID: String) -> URL {
        let hash = SHA256.hash(data: Data(articleID.utf8))
        let filename = hash.compactMap { String(format: "%02x", $0) }.joined()
        return cacheDirectory.appendingPathComponent("\(filename).jpg")
    }

    private var cacheDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Self.cacheDirectoryName)
    }

    private func ensureCacheDirectoryExists() throws {
        try FileManager.default.createDirectory(
            at: cacheDirectory,
            withIntermediateDirectories: true
        )
    }
}
