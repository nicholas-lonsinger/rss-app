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
    ///
    /// Throws `CancellationError` if the current task is cancelled during the download.
    /// The `throws(CancellationError)` typed-throws signature compile-time enforces that
    /// no other error type can escape this method: all network, HTTP, decode, and filesystem
    /// failures are surfaced via the returned `ThumbnailCacheResult` so callers can
    /// distinguish retry-worthy from permanent failures.
    func cacheThumbnail(from remoteURL: URL, articleID: String) async throws(CancellationError) -> ThumbnailCacheResult

    /// Resolves and caches a thumbnail: tries `thumbnailURL` first, then fetches
    /// the article page at `articleLink` to extract `og:image` as a fallback.
    ///
    /// Throws `CancellationError` if the current task is cancelled during resolution.
    /// The `throws(CancellationError)` typed-throws signature compile-time enforces that
    /// no other error type can escape; all other outcomes are reported via `ThumbnailCacheResult`.
    func resolveAndCacheThumbnail(thumbnailURL: URL?, articleLink: URL?, articleID: String) async throws(CancellationError) -> ThumbnailCacheResult

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
    // RATIONALE: thumbnailDimension derives from ArticleThumbnailView.thumbnailSize (the
    // single source of truth for the display size) multiplied by the screen scale, ensuring
    // cached thumbnails are always full-resolution (2× on SE/standard, 3× on Pro/Plus).
    // Both types live in the same RSSApp module so the cross-file reference adds no import.
    private static var thumbnailDimension: CGFloat {
        ceil(ArticleThumbnailView.thumbnailSize * UIScreen.main.scale)
    }
    private static let jpegQuality: CGFloat = 0.8

    /// Session used to fetch article HTML for og:image resolution. Injectable so tests
    /// can drive the HTTP classification paths in `resolveOGImage` with a URLProtocol mock
    /// without hitting the network. Production defaults to `URLSession.shared`.
    private let session: any URLSessionBytesProviding

    init(session: any URLSessionBytesProviding = URLSession.shared) {
        self.session = session
    }

    // MARK: - ArticleThumbnailCaching

    func cacheThumbnail(from remoteURL: URL, articleID: String) async throws(CancellationError) -> ThumbnailCacheResult {
        Self.logger.debug("cacheThumbnail() from \(remoteURL.absoluteString, privacy: .public) for article \(articleID, privacy: .public)")

        guard remoteURL.scheme == "http" || remoteURL.scheme == "https" else {
            Self.logger.warning("Rejecting non-HTTP URL scheme '\(remoteURL.scheme ?? "nil", privacy: .public)' for \(remoteURL.absoluteString, privacy: .public)")
            return .permanentFailure
        }

        // Reject SVG URLs before downloading — UIImage can't render SVGs
        if remoteURL.pathExtension.lowercased() == "svg" {
            Self.logger.debug("Rejecting SVG URL before download: \(remoteURL.absoluteString, privacy: .public)")
            return .permanentFailure
        }

        // RATIONALE: The inner do/catch is untyped because URLSession + Foundation APIs throw
        // generic `Error`. We classify failures into the typed return enum (`ThumbnailCacheResult`)
        // here, and only rethrow `CancellationError` so the outer typed-throws signature holds.
        let data: Data
        let response: URLResponse
        do {
            var request = URLRequest(url: remoteURL, timeoutInterval: Self.fetchTimeout)
            request.setBrowserUserAgent()
            (data, response) = try await URLSession.shared.data(for: request)
        } catch is CancellationError {
            // Propagate structured-concurrency cancellation so callers stop retrying immediately.
            throw CancellationError()
        } catch let urlError as URLError where urlError.code == .cancelled {
            // URLSession surfaces task cancellation as URLError(.cancelled); normalize to CancellationError.
            throw CancellationError()
        } catch let urlError as URLError {
            Self.logger.warning("Network error caching thumbnail for \(remoteURL.absoluteString, privacy: .public): \(urlError, privacy: .public)")
            return .transientFailure
        } catch {
            // RATIONALE: Unknown errors have unclear retryability; .transientFailure is the safer
            // default over permanently blacklisting a URL we can't classify. Logged at .error so
            // unexpected escapes remain visible in persisted logs.
            Self.logger.error("Unexpected error caching thumbnail for \(remoteURL.absoluteString, privacy: .public): \(error, privacy: .public)")
            return .transientFailure
        }

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            Self.logger.warning("Thumbnail fetch returned HTTP \(code, privacy: .public) for \(remoteURL.absoluteString, privacy: .public)")
            return Self.isPermanentHTTPFailure(code: code) ? .permanentFailure : .transientFailure
        }

        // Reject SVG content type — catches extensionless SVG URLs (e.g. deploy buttons)
        let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? ""
        if contentType.hasPrefix("image/svg") {
            Self.logger.debug("Rejecting SVG content type (\(contentType, privacy: .public), \(data.count, privacy: .public) bytes) from \(remoteURL.absoluteString, privacy: .public)")
            return .permanentFailure
        }

        guard let image = UIImage(data: data) else {
            Self.logger.warning("Downloaded data is not a valid image (\(contentType, privacy: .public), \(data.count, privacy: .public) bytes) from \(remoteURL.absoluteString, privacy: .public)")
            return .permanentFailure
        }

        let thumbnail = cropAndResize(image)
        guard let jpegData = thumbnail.jpegData(compressionQuality: Self.jpegQuality) else {
            Self.logger.warning("Failed to generate JPEG data from thumbnail")
            return .permanentFailure
        }

        // Filesystem errors (permissions, disk full) are permanent within this session.
        do {
            let fileURL = thumbnailFileURL(for: articleID)
            try ensureCacheDirectoryExists()
            try jpegData.write(to: fileURL, options: .atomic)
            Self.logger.debug("Cached thumbnail for article \(articleID, privacy: .public) (\(jpegData.count, privacy: .public) bytes)")
            return .cached
        } catch {
            Self.logger.warning("Failed to write thumbnail file for \(remoteURL.absoluteString, privacy: .public): \(error, privacy: .public)")
            return .permanentFailure
        }
    }

    func resolveAndCacheThumbnail(thumbnailURL: URL?, articleLink: URL?, articleID: String) async throws(CancellationError) -> ThumbnailCacheResult {
        Self.logger.debug("resolveAndCacheThumbnail() thumbnailURL=\(thumbnailURL?.absoluteString ?? "nil", privacy: .public) articleLink=\(articleLink?.absoluteString ?? "nil", privacy: .public) articleID=\(articleID, privacy: .public)")

        var sawTransient = false

        // Priority 1: Direct thumbnail URL from feed
        if let thumbnailURL {
            let result = try await cacheThumbnail(from: thumbnailURL, articleID: articleID)
            if result == .cached { return .cached }
            if result == .transientFailure { sawTransient = true }
        }

        // Priority 2: Fetch article page and extract og:image
        if let articleLink {
            switch try await resolveOGImage(from: articleLink) {
            case .found(let ogImageURL):
                let result = try await cacheThumbnail(from: ogImageURL, articleID: articleID)
                if result == .cached { return .cached }
                if result == .transientFailure { sawTransient = true }
            case .fetchFailed:
                sawTransient = true
            case .notFound:
                break
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

    /// Distinguishes successful og:image extraction from "no tag present" vs "fetch failed."
    // RATIONALE: Internal (not private) so `@testable` unit tests can drive
    // `resolveOGImage` directly and assert the HTTP classification outcomes.
    enum OGImageResult: Equatable {
        /// An og:image URL was found in the page's `<head>`.
        case found(URL)
        /// The page loaded successfully but contained no og:image meta tag, or the
        /// server returned a permanent HTTP client error (e.g. 404, 403) that makes
        /// og:image extraction impossible. Either way, retrying is futile.
        case notFound
        /// A network or transient HTTP error prevented loading the page — worth retrying.
        case fetchFailed
    }

    private static let htmlFetchTimeout: TimeInterval = 10

    /// The og:image meta tag is in the `<head>`, so we only need the first portion of the page.
    private static let htmlHeadMaxBytes = 51_200 // 50 KB

    /// Fetches the beginning of an article page and extracts the `og:image` meta tag URL.
    ///
    /// Throws `CancellationError` if the task is cancelled during the fetch. The
    /// `throws(CancellationError)` typed-throws signature compile-time enforces that no
    /// other error type can escape; non-cancellation errors (network, HTTP, decode) are
    /// surfaced via `OGImageResult`.
    // RATIONALE: Internal (not private) so `@testable` unit tests can exercise the
    // HTTP status classification paths with an injected URLProtocol-backed session.
    func resolveOGImage(from articleLink: URL) async throws(CancellationError) -> OGImageResult {
        Self.logger.debug("Resolving og:image from \(articleLink.absoluteString, privacy: .public)")

        // RATIONALE: Two separate untyped do/catches funnel network and stream errors into
        // the typed return enum (`OGImageResult`). Only `CancellationError` is rethrown, so
        // the outer typed-throws signature holds.
        let bytes: URLSession.AsyncBytes
        let response: URLResponse
        do {
            var request = URLRequest(url: articleLink, timeoutInterval: Self.htmlFetchTimeout)
            request.setBrowserUserAgent()
            (bytes, response) = try await session.bytes(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let urlError as URLError where urlError.code == .cancelled {
            throw CancellationError()
        } catch let urlError as URLError {
            Self.logger.warning("Network error fetching article page for og:image from \(articleLink.absoluteString, privacy: .public): \(urlError, privacy: .public)")
            return .fetchFailed
        } catch {
            // RATIONALE: Unknown errors have unclear retryability; .fetchFailed is the safer
            // default over permanently blacklisting a URL we can't classify. Logged at .error
            // so unexpected escapes remain visible in persisted logs.
            Self.logger.error("Unexpected error fetching article page for og:image from \(articleLink.absoluteString, privacy: .public): \(error, privacy: .public)")
            return .fetchFailed
        }

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            Self.logger.warning("Article page fetch returned HTTP \(code, privacy: .public) for \(articleLink.absoluteString, privacy: .public)")
            if Self.isPermanentHTTPFailure(code: code) {
                Self.logger.info("Treating HTTP \(code, privacy: .public) as permanent og:image failure for \(articleLink.absoluteString, privacy: .public)")
                return .notFound
            }
            return .fetchFailed
        }

        // Read only the first portion — og:image is in <head>, no need for the full body
        var collected = Data()
        collected.reserveCapacity(Self.htmlHeadMaxBytes)
        do {
            for try await byte in bytes {
                collected.append(byte)
                if collected.count >= Self.htmlHeadMaxBytes { break }
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let urlError as URLError where urlError.code == .cancelled {
            // URLSession.AsyncBytes surfaces mid-stream task cancellation as URLError(.cancelled);
            // normalize to CancellationError so callers stop retrying immediately.
            throw CancellationError()
        } catch let urlError as URLError {
            Self.logger.warning("Network error streaming article page for og:image from \(articleLink.absoluteString, privacy: .public): \(urlError, privacy: .public)")
            return .fetchFailed
        } catch {
            // RATIONALE: Unknown errors have unclear retryability; .fetchFailed is the safer
            // default over permanently blacklisting a URL we can't classify. Logged at .error
            // so unexpected escapes remain visible in persisted logs.
            Self.logger.error("Unexpected error streaming article page for og:image from \(articleLink.absoluteString, privacy: .public): \(error, privacy: .public)")
            return .fetchFailed
        }

        // RATIONALE: Decode tolerantly with `String(decoding:as:)` rather than the
        // failable `String(data:encoding:.utf8)`. The 50 KB head slice frequently
        // cuts through a multi-byte UTF-8 character at the boundary, which makes
        // strict decoding fail on otherwise-valid pages. Substituting replacement
        // characters for invalid bytes lets the og:image extractor still find the
        // tag (which is virtually always pure ASCII). If the page is genuinely
        // non-UTF-8, the regex will simply fail to match and we fall through to
        // `.notFound` — a permanent classification — so the prefetcher does not
        // burn retry budget on a request that can never succeed.
        let html = String(decoding: collected, as: UTF8.self)

        if let ogURL = HTMLUtilities.extractOGImageURL(from: html, baseURL: articleLink) {
            return .found(ogURL)
        }
        Self.logger.debug("No og:image meta tag found in page from \(articleLink.absoluteString, privacy: .public)")
        return .notFound
    }

    // MARK: - HTTP Classification

    /// Returns `true` if an HTTP status code represents a permanent client error
    /// where retrying will not help. Standard 4xx responses (404, 403, etc.) are
    /// permanent, but 429 (rate limited) and 408 (request timeout) are transient
    /// despite being 4xx. Everything else (5xx, code == -1 for non-HTTPURLResponse,
    /// unknown) is treated as transient.
    // RATIONALE: Internal (not private) so `@testable` unit tests can assert the
    // boundary values directly without needing to drive a URLSession mock.
    static func isPermanentHTTPFailure(code: Int) -> Bool {
        (400...499).contains(code) && code != 429 && code != 408
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
