import Foundation
import os

@MainActor
@Observable
final class FeedViewModel {

    private static let logger = Logger(category: "FeedViewModel")

    var articles: [PersistentArticle] = []
    var feedTitle: String = "Feed"
    var isLoading = false
    var errorMessage: String?

    let thumbnailService: ArticleThumbnailCaching

    private let feedFetching: FeedFetching
    private let persistence: FeedPersisting
    private let feed: PersistentFeed

    init(
        feed: PersistentFeed,
        feedFetching: FeedFetching = FeedFetchingService(),
        persistence: FeedPersisting,
        thumbnailService: ArticleThumbnailCaching = ArticleThumbnailService()
    ) {
        self.feed = feed
        self.feedFetching = feedFetching
        self.persistence = persistence
        self.thumbnailService = thumbnailService
        self.feedTitle = feed.title
    }

    func loadFeed() async {
        Self.logger.debug("loadFeed() called for '\(self.feed.title, privacy: .public)'")

        // Show cached articles immediately (cache-first loading for offline support)
        do {
            let cached = try persistence.articles(for: feed)
            if !cached.isEmpty {
                articles = cached
            }
        } catch {
            Self.logger.warning("Failed to load cached articles for '\(self.feed.title, privacy: .public)': \(error, privacy: .public)")
        }

        isLoading = articles.isEmpty
        errorMessage = nil
        defer { isLoading = false }

        do {
            let result = try await feedFetching.fetchFeed(
                from: feed.feedURL,
                etag: feed.etag,
                lastModified: feed.lastModifiedHeader
            )
            if let result {
                feedTitle = result.feed.title
                try persistence.upsertArticles(result.feed.articles, for: feed)
                try persistence.updateFeedCacheHeaders(feed, etag: result.etag, lastModified: result.lastModified)
                try persistence.save()
                articles = try persistence.articles(for: feed)
                Self.logger.notice("Feed loaded: \(self.articles.count, privacy: .public) articles")
                prefetchThumbnails()
            } else {
                Self.logger.debug("Feed unchanged (304) for '\(self.feed.title, privacy: .public)'")
            }
        } catch {
            if articles.isEmpty {
                errorMessage = error.localizedDescription
            }
            Self.logger.error("Feed load failed: \(error, privacy: .public)")
        }
    }

    func markAsRead(_ article: PersistentArticle) {
        guard !article.isRead else { return }
        do {
            try persistence.markArticleRead(article, isRead: true)
        } catch {
            errorMessage = "Unable to save read status."
            Self.logger.error("Failed to mark article as read: \(error, privacy: .public)")
        }
    }

    func toggleReadStatus(_ article: PersistentArticle) {
        do {
            try persistence.markArticleRead(article, isRead: !article.isRead)
        } catch {
            errorMessage = "Unable to save read status."
            Self.logger.error("Failed to toggle read status: \(error, privacy: .public)")
        }
    }

    // MARK: - Thumbnail Prefetching

    private func prefetchThumbnails() {
        let service = self.thumbnailService

        // Extract Sendable values before crossing isolation boundary
        let thumbnailsToFetch: [(articleID: String, thumbnailURL: URL?, articleLink: URL?)] = articles.prefix(20).compactMap { article in
            guard service.cachedThumbnailFileURL(for: article.articleID) == nil,
                  article.thumbnailURL != nil || article.link != nil else { return nil }
            return (article.articleID, article.thumbnailURL, article.link)
        }

        guard !thumbnailsToFetch.isEmpty else { return }

        Self.logger.debug("Prefetching \(thumbnailsToFetch.count, privacy: .public) thumbnails")

        Task.detached(priority: .utility) {
            await withTaskGroup(of: Void.self) { group in
                for item in thumbnailsToFetch {
                    group.addTask {
                        _ = await service.resolveAndCacheThumbnail(
                            thumbnailURL: item.thumbnailURL,
                            articleLink: item.articleLink,
                            articleID: item.articleID
                        )
                    }
                }
            }
        }
    }
}
