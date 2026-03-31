import Foundation
import os

@MainActor
@Observable
final class FeedViewModel {

    private static let logger = Logger(
        subsystem: "com.nicholas-lonsinger.rss-app",
        category: "FeedViewModel"
    )

    var articles: [Article] = []
    var isLoading = false
    var errorMessage: String?

    private let feedFetching: FeedFetching
    private let feedURL: URL

    init(feedFetching: FeedFetching = FeedFetchingService(), feedURL: URL? = nil) {
        self.feedFetching = feedFetching

        if let feedURL {
            self.feedURL = feedURL
            return
        }

        guard let url = URL(string: "https://appleinsider.com/rss/news/") else {
            Self.logger.fault("Failed to create URL for hardcoded AppleInsider feed")
            assertionFailure("Failed to create URL for hardcoded AppleInsider feed")
            // RATIONALE: "about:blank" is a well-known URI that always produces a valid URL.
            // This fallback is unreachable in practice since the Ars Technica URL is a valid literal.
            self.feedURL = URL(filePath: "/")
            return
        }
        self.feedURL = url
    }

    func loadFeed() async {
        Self.logger.debug("loadFeed() called")
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let feed = try await feedFetching.fetchFeed(from: feedURL)
            articles = feed.articles
            Self.logger.notice("Feed loaded: \(feed.articles.count, privacy: .public) articles")
        } catch {
            errorMessage = error.localizedDescription
            Self.logger.error("Feed load failed: \(error, privacy: .public)")
        }
    }
}
