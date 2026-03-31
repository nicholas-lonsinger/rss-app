import Foundation
import os

enum FeedFetchingError: Error, Sendable {
    case invalidResponse(statusCode: Int)
    case invalidFeedURL
}

protocol FeedFetching: Sendable {
    func fetchFeed(from url: URL) async throws -> RSSFeed
}

struct FeedFetchingService: FeedFetching {

    private static let logger = Logger(
        subsystem: "com.nicholas-lonsinger.rss-app",
        category: "FeedFetchingService"
    )

    private let parsingService = RSSParsingService()

    func fetchFeed(from url: URL) async throws -> RSSFeed {
        Self.logger.debug("fetchFeed() called for \(url.absoluteString, privacy: .public)")

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            Self.logger.error("Response is not HTTPURLResponse for \(url.absoluteString, privacy: .public)")
            throw FeedFetchingError.invalidResponse(statusCode: 0)
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            Self.logger.error("HTTP \(httpResponse.statusCode, privacy: .public) for \(url.absoluteString, privacy: .public)")
            throw FeedFetchingError.invalidResponse(statusCode: httpResponse.statusCode)
        }

        Self.logger.info("Received \(data.count, privacy: .public) bytes from \(url.absoluteString, privacy: .public)")

        let feed = try parsingService.parse(data)
        Self.logger.notice("Feed fetched: '\(feed.title, privacy: .public)' with \(feed.articles.count, privacy: .public) articles")
        return feed
    }
}
