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
    var feedTitle: String = "Feed"
    var isLoading = false
    var errorMessage: String?

    private let feedFetching: FeedFetching
    private let feedURL: URL

    init(feedFetching: FeedFetching = FeedFetchingService(), feedURL: URL) {
        self.feedFetching = feedFetching
        self.feedURL = feedURL
    }

    func loadFeed() async {
        Self.logger.debug("loadFeed() called")
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let feed = try await feedFetching.fetchFeed(from: feedURL)
            feedTitle = feed.title
            articles = feed.articles
            Self.logger.notice("Feed loaded: \(feed.articles.count, privacy: .public) articles")
        } catch {
            errorMessage = error.localizedDescription
            Self.logger.error("Feed load failed: \(error, privacy: .public)")
        }
    }
}
