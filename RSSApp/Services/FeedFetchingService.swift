import Foundation
import os

enum FeedFetchingError: Error, Sendable {
    case invalidResponse(statusCode: Int)
    case invalidFeedURL
}

struct FeedFetchResult: Sendable {
    let feed: RSSFeed
    let etag: String?
    let lastModified: String?
}

protocol FeedFetching: Sendable {
    func fetchFeed(from url: URL) async throws -> RSSFeed
    /// Fetches a feed with conditional HTTP headers. Returns nil on 304 Not Modified.
    func fetchFeed(from url: URL, etag: String?, lastModified: String?) async throws -> FeedFetchResult?
}

struct FeedFetchingService: FeedFetching {

    private static let logger = Logger(
        subsystem: Logger.appSubsystem,
        category: "FeedFetchingService"
    )

    private let parsingService = RSSParsingService()

    func fetchFeed(from url: URL) async throws -> RSSFeed {
        guard let result = try await fetchFeed(from: url, etag: nil, lastModified: nil) else {
            // Should never happen without conditional headers, but handle gracefully
            Self.logger.fault("Unexpected 304 without conditional headers for \(url.absoluteString, privacy: .public)")
            assertionFailure("304 without conditional headers")
            throw FeedFetchingError.invalidResponse(statusCode: 304)
        }
        return result.feed
    }

    func fetchFeed(from url: URL, etag: String?, lastModified: String?) async throws -> FeedFetchResult? {
        Self.logger.debug("fetchFeed() called for \(url.absoluteString, privacy: .public)")

        var request = URLRequest(url: url)
        if let etag {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        if let lastModified {
            request.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since")
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            Self.logger.error("Response is not HTTPURLResponse for \(url.absoluteString, privacy: .public)")
            throw FeedFetchingError.invalidResponse(statusCode: 0)
        }

        if httpResponse.statusCode == 304 {
            Self.logger.debug("304 Not Modified for \(url.absoluteString, privacy: .public)")
            return nil
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            Self.logger.error("HTTP \(httpResponse.statusCode, privacy: .public) for \(url.absoluteString, privacy: .public)")
            throw FeedFetchingError.invalidResponse(statusCode: httpResponse.statusCode)
        }

        Self.logger.info("Received \(data.count, privacy: .public) bytes from \(url.absoluteString, privacy: .public)")

        let feed = try parsingService.parse(data)
        let responseEtag = httpResponse.value(forHTTPHeaderField: "ETag")
        let responseLastModified = httpResponse.value(forHTTPHeaderField: "Last-Modified")

        Self.logger.notice("Feed fetched: '\(feed.title, privacy: .public)' with \(feed.articles.count, privacy: .public) articles")
        return FeedFetchResult(feed: feed, etag: responseEtag, lastModified: responseLastModified)
    }
}
