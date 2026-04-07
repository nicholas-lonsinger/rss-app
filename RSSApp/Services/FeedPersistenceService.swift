import Foundation
import SwiftData
import os

// MARK: - Protocol

@MainActor
protocol FeedPersisting: Sendable {

    // MARK: Feed operations

    func allFeeds() throws -> [PersistentFeed]
    func addFeed(_ feed: PersistentFeed) throws
    func deleteFeed(_ feed: PersistentFeed) throws
    func updateFeedMetadata(_ feed: PersistentFeed, title: String, description: String) throws
    func updateFeedError(_ feed: PersistentFeed, error: String?) throws
    func updateFeedURL(_ feed: PersistentFeed, newURL: URL) throws
    func updateFeedCacheHeaders(_ feed: PersistentFeed, etag: String?, lastModified: String?) throws
    func updateFeedIcon(_ feed: PersistentFeed, iconURL: URL?) throws
    func feedExists(url: URL) throws -> Bool

    // MARK: Article operations

    /// Returns all articles for a feed, sorted by `sortDate` descending (newest first).
    /// `sortDate` is the publisher-supplied `publishedDate` clamped to ingestion time at insert
    /// — see `PersistentArticle.sortDate` for the rationale.
    func articles(for feed: PersistentFeed) throws -> [PersistentArticle]
    /// Returns a page of articles for a feed, sorted by `sortDate`.
    /// - Parameters:
    ///   - offset: Number of articles to skip from the beginning of the sorted result set.
    ///   - limit: Maximum number of articles to return.
    ///   - ascending: When `true`, sorts oldest first; when `false` (default), sorts newest first.
    func articles(for feed: PersistentFeed, offset: Int, limit: Int, ascending: Bool) throws -> [PersistentArticle]
    /// Returns a page of unread articles for a feed, sorted by `sortDate`.
    /// - Parameters:
    ///   - offset: Number of articles to skip from the beginning of the sorted result set.
    ///   - limit: Maximum number of articles to return.
    ///   - ascending: When `true`, sorts oldest first; when `false` (default), sorts newest first.
    func unreadArticles(for feed: PersistentFeed, offset: Int, limit: Int, ascending: Bool) throws -> [PersistentArticle]
    /// Returns all articles across all feeds, sorted by `sortDate` descending (newest first).
    func allArticles() throws -> [PersistentArticle]
    /// Returns a page of all articles across all feeds, sorted by `sortDate`.
    /// - Parameters:
    ///   - offset: Number of articles to skip from the beginning of the sorted result set.
    ///   - limit: Maximum number of articles to return.
    ///   - ascending: When `true`, sorts oldest first; when `false` (default), sorts newest first.
    func allArticles(offset: Int, limit: Int, ascending: Bool) throws -> [PersistentArticle]
    /// Returns all unread articles across all feeds, sorted by `sortDate` descending (newest first).
    func allUnreadArticles() throws -> [PersistentArticle]
    /// Returns a page of unread articles across all feeds, sorted by `sortDate`.
    /// - Parameters:
    ///   - offset: Number of articles to skip from the beginning of the sorted result set.
    ///   - limit: Maximum number of articles to return.
    ///   - ascending: When `true`, sorts oldest first; when `false` (default), sorts newest first.
    func allUnreadArticles(offset: Int, limit: Int, ascending: Bool) throws -> [PersistentArticle]
    func upsertArticles(_ articles: [Article], for feed: PersistentFeed) throws
    func markArticleRead(_ article: PersistentArticle, isRead: Bool) throws
    /// Marks all articles in a specific feed as read.
    func markAllArticlesRead(for feed: PersistentFeed) throws
    /// Marks all articles across all feeds as read.
    func markAllArticlesRead() throws
    func unreadCount(for feed: PersistentFeed) throws -> Int
    /// Returns the total number of unread articles across all feeds.
    func totalUnreadCount() throws -> Int

    // MARK: Saved article operations

    /// Toggles the saved state of an article. Sets `isSaved` and updates `savedDate`.
    func toggleArticleSaved(_ article: PersistentArticle) throws
    /// Returns a page of saved articles across all feeds, sorted by saved date descending (most recently saved first).
    func allSavedArticles(offset: Int, limit: Int) throws -> [PersistentArticle]
    /// Returns the total number of saved articles across all feeds.
    func savedCount() throws -> Int

    // MARK: Content cache

    func cachedContent(for article: PersistentArticle) throws -> PersistentArticleContent?
    func cacheContent(_ content: ArticleContent, for article: PersistentArticle) throws

    // MARK: Thumbnail tracking

    /// Returns articles that need thumbnail downloads: not yet cached and under the retry cap.
    func articlesNeedingThumbnails(maxRetryCount: Int) throws -> [PersistentArticle]

    /// Marks an article's thumbnail as successfully cached.
    func markThumbnailCached(_ article: PersistentArticle) throws

    /// Increments the thumbnail retry count for an article after a failed download attempt.
    func incrementThumbnailRetryCount(_ article: PersistentArticle) throws

    // MARK: Article cleanup

    /// Returns the total number of articles across all feeds.
    func totalArticleCount() throws -> Int

    /// Returns the article IDs of the oldest unsaved articles exceeding the given limit,
    /// sorted by `sortDate` ascending (oldest first). Saved articles are exempt from
    /// retention cleanup and are excluded from the returned results. Sorting by `sortDate`
    /// rather than `publishedDate` prevents future-dated scheduled posts (e.g., the
    /// Cloudflare blog's upcoming-content feed) from being deleted prematurely.
    /// - Parameter limit: The maximum number of articles to retain.
    /// - Returns: Article IDs that should be deleted, along with their `isThumbnailCached` flag.
    func oldestArticleIDsExceedingLimit(_ limit: Int) throws -> [(articleID: String, isThumbnailCached: Bool)]

    /// Deletes articles by their article IDs.
    /// - Parameter articleIDs: The set of article IDs to delete.
    func deleteArticles(withIDs articleIDs: Set<String>) throws

    // MARK: Persistence

    func save() throws
}

// MARK: - SwiftData Implementation

@MainActor
final class SwiftDataFeedPersistenceService: FeedPersisting {

    private static let logger = Logger(category: "FeedPersistenceService")

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Feed Operations

    func allFeeds() throws -> [PersistentFeed] {
        let descriptor = FetchDescriptor<PersistentFeed>(
            sortBy: [SortDescriptor(\.addedDate)]
        )
        let feeds = try modelContext.fetch(descriptor)
        Self.logger.debug("Fetched \(feeds.count, privacy: .public) feeds")
        return feeds
    }

    func addFeed(_ feed: PersistentFeed) throws {
        modelContext.insert(feed)
        try modelContext.save()
        Self.logger.notice("Added feed '\(feed.title, privacy: .public)'")
    }

    func deleteFeed(_ feed: PersistentFeed) throws {
        let title = feed.title
        modelContext.delete(feed)
        try modelContext.save()
        Self.logger.notice("Deleted feed '\(title, privacy: .public)'")
    }

    func updateFeedMetadata(_ feed: PersistentFeed, title: String, description: String) throws {
        feed.title = title
        feed.feedDescription = description
        feed.lastRefreshDate = Date()
        feed.lastFetchError = nil
        feed.lastFetchErrorDate = nil
        Self.logger.debug("Updated metadata for '\(title, privacy: .public)'")
    }

    func updateFeedError(_ feed: PersistentFeed, error: String?) throws {
        feed.lastFetchError = error
        feed.lastFetchErrorDate = error != nil ? Date() : nil
        Self.logger.debug("Updated error state for '\(feed.title, privacy: .public)'")
    }

    func updateFeedURL(_ feed: PersistentFeed, newURL: URL) throws {
        feed.feedURL = newURL
        feed.lastFetchError = nil
        feed.lastFetchErrorDate = nil
        try modelContext.save()
        Self.logger.debug("Updated URL for '\(feed.title, privacy: .public)'")
    }

    func updateFeedCacheHeaders(_ feed: PersistentFeed, etag: String?, lastModified: String?) throws {
        feed.etag = etag
        feed.lastModifiedHeader = lastModified
        Self.logger.debug("Updated cache headers for '\(feed.title, privacy: .public)'")
    }

    func updateFeedIcon(_ feed: PersistentFeed, iconURL: URL?) throws {
        feed.iconURL = iconURL
        Self.logger.debug("Updated icon for '\(feed.title, privacy: .public)'")
    }

    func feedExists(url: URL) throws -> Bool {
        let feedURL = url
        var descriptor = FetchDescriptor<PersistentFeed>(
            predicate: #Predicate { $0.feedURL == feedURL }
        )
        descriptor.fetchLimit = 1
        let count = try modelContext.fetchCount(descriptor)
        return count > 0
    }

    // MARK: - Article Operations

    func articles(for feed: PersistentFeed) throws -> [PersistentArticle] {
        let feedID = feed.persistentModelID
        let descriptor = FetchDescriptor<PersistentArticle>(
            predicate: #Predicate { $0.feed?.persistentModelID == feedID },
            sortBy: [
                SortDescriptor(\.sortDate, order: .reverse),
                SortDescriptor(\.articleID, order: .forward)
            ]
        )
        return try modelContext.fetch(descriptor)
    }

    func articles(for feed: PersistentFeed, offset: Int, limit: Int, ascending: Bool = false) throws -> [PersistentArticle] {
        let feedID = feed.persistentModelID
        let sortOrder: SortOrder = ascending ? .forward : .reverse
        var descriptor = FetchDescriptor<PersistentArticle>(
            predicate: #Predicate { $0.feed?.persistentModelID == feedID },
            sortBy: [
                SortDescriptor(\.sortDate, order: sortOrder),
                SortDescriptor(\.articleID, order: .forward)
            ]
        )
        descriptor.fetchOffset = offset
        descriptor.fetchLimit = limit
        let articles = try modelContext.fetch(descriptor)
        Self.logger.debug("Fetched \(articles.count, privacy: .public) articles for feed (offset: \(offset, privacy: .public), limit: \(limit, privacy: .public), ascending: \(ascending, privacy: .public))")
        return articles
    }

    func unreadArticles(for feed: PersistentFeed, offset: Int, limit: Int, ascending: Bool = false) throws -> [PersistentArticle] {
        let feedID = feed.persistentModelID
        let sortOrder: SortOrder = ascending ? .forward : .reverse
        var descriptor = FetchDescriptor<PersistentArticle>(
            predicate: #Predicate { $0.feed?.persistentModelID == feedID && !$0.isRead },
            sortBy: [
                SortDescriptor(\.sortDate, order: sortOrder),
                SortDescriptor(\.articleID, order: .forward)
            ]
        )
        descriptor.fetchOffset = offset
        descriptor.fetchLimit = limit
        let articles = try modelContext.fetch(descriptor)
        Self.logger.debug("Fetched \(articles.count, privacy: .public) unread articles for feed (offset: \(offset, privacy: .public), limit: \(limit, privacy: .public), ascending: \(ascending, privacy: .public))")
        return articles
    }

    func allArticles() throws -> [PersistentArticle] {
        let descriptor = FetchDescriptor<PersistentArticle>(
            sortBy: [
                SortDescriptor(\.sortDate, order: .reverse),
                SortDescriptor(\.articleID, order: .forward)
            ]
        )
        let articles = try modelContext.fetch(descriptor)
        Self.logger.debug("Fetched \(articles.count, privacy: .public) total articles")
        return articles
    }

    func allArticles(offset: Int, limit: Int, ascending: Bool = false) throws -> [PersistentArticle] {
        let sortOrder: SortOrder = ascending ? .forward : .reverse
        var descriptor = FetchDescriptor<PersistentArticle>(
            sortBy: [
                SortDescriptor(\.sortDate, order: sortOrder),
                SortDescriptor(\.articleID, order: .forward)
            ]
        )
        descriptor.fetchOffset = offset
        descriptor.fetchLimit = limit
        let articles = try modelContext.fetch(descriptor)
        Self.logger.debug("Fetched \(articles.count, privacy: .public) total articles (offset: \(offset, privacy: .public), limit: \(limit, privacy: .public), ascending: \(ascending, privacy: .public))")
        return articles
    }

    func allUnreadArticles() throws -> [PersistentArticle] {
        let descriptor = FetchDescriptor<PersistentArticle>(
            predicate: #Predicate { !$0.isRead },
            sortBy: [
                SortDescriptor(\.sortDate, order: .reverse),
                SortDescriptor(\.articleID, order: .forward)
            ]
        )
        let articles = try modelContext.fetch(descriptor)
        Self.logger.debug("Fetched \(articles.count, privacy: .public) unread articles")
        return articles
    }

    func allUnreadArticles(offset: Int, limit: Int, ascending: Bool = false) throws -> [PersistentArticle] {
        let sortOrder: SortOrder = ascending ? .forward : .reverse
        var descriptor = FetchDescriptor<PersistentArticle>(
            predicate: #Predicate { !$0.isRead },
            sortBy: [
                SortDescriptor(\.sortDate, order: sortOrder),
                SortDescriptor(\.articleID, order: .forward)
            ]
        )
        descriptor.fetchOffset = offset
        descriptor.fetchLimit = limit
        let articles = try modelContext.fetch(descriptor)
        Self.logger.debug("Fetched \(articles.count, privacy: .public) unread articles (offset: \(offset, privacy: .public), limit: \(limit, privacy: .public), ascending: \(ascending, privacy: .public))")
        return articles
    }

    // RATIONALE: Insert-only by design — existing articles are never updated because preserving
    // user-generated state (read status, saved status, cached content) is more important than
    // reflecting minor metadata edits (title rewording) from the feed source.
    func upsertArticles(_ articles: [Article], for feed: PersistentFeed) throws {
        // Query only the articleIDs we need to check, avoiding loading full article objects
        let feedID = feed.persistentModelID
        let incomingIDs = articles.map(\.id)
        let descriptor = FetchDescriptor<PersistentArticle>(
            predicate: #Predicate { article in
                article.feed?.persistentModelID == feedID
                    && incomingIDs.contains(article.articleID)
            }
        )
        let existingArticles = try modelContext.fetch(descriptor)
        let existingIDs = Set(existingArticles.map(\.articleID))
        var insertedCount = 0

        for article in articles {
            guard !existingIDs.contains(article.id) else { continue }
            let persistent = PersistentArticle(from: article)
            persistent.feed = feed
            modelContext.insert(persistent)
            insertedCount += 1
        }

        Self.logger.debug("Upserted articles for '\(feed.title, privacy: .public)': \(insertedCount, privacy: .public) new, \(articles.count - insertedCount, privacy: .public) existing")
    }

    func markArticleRead(_ article: PersistentArticle, isRead: Bool) throws {
        article.isRead = isRead
        article.readDate = isRead ? Date() : nil
        try modelContext.save()
        Self.logger.debug("Marked article '\(article.title, privacy: .public)' as \(isRead ? "read" : "unread", privacy: .public)")
    }

    func markAllArticlesRead(for feed: PersistentFeed) throws {
        let feedID = feed.persistentModelID
        let descriptor = FetchDescriptor<PersistentArticle>(
            predicate: #Predicate { $0.feed?.persistentModelID == feedID && !$0.isRead }
        )
        let unreadArticles = try modelContext.fetch(descriptor)
        guard !unreadArticles.isEmpty else {
            Self.logger.debug("No unread articles to mark as read for feed '\(feed.title, privacy: .public)'")
            return
        }
        let now = Date()
        for article in unreadArticles {
            article.isRead = true
            article.readDate = now
        }
        try modelContext.save()
        Self.logger.notice("Marked \(unreadArticles.count, privacy: .public) articles as read for feed '\(feed.title, privacy: .public)'")
    }

    func markAllArticlesRead() throws {
        let descriptor = FetchDescriptor<PersistentArticle>(
            predicate: #Predicate { !$0.isRead }
        )
        let unreadArticles = try modelContext.fetch(descriptor)
        guard !unreadArticles.isEmpty else {
            Self.logger.debug("No unread articles to mark as read across all feeds")
            return
        }
        let now = Date()
        for article in unreadArticles {
            article.isRead = true
            article.readDate = now
        }
        try modelContext.save()
        Self.logger.notice("Marked \(unreadArticles.count, privacy: .public) articles as read across all feeds")
    }

    // MARK: - Saved Article Operations

    func toggleArticleSaved(_ article: PersistentArticle) throws {
        let newSaved = !article.isSaved
        article.isSaved = newSaved
        article.savedDate = newSaved ? Date() : nil
        try modelContext.save()
        Self.logger.notice("Toggled saved state for '\(article.title, privacy: .public)' to \(newSaved ? "saved" : "unsaved", privacy: .public)")
    }

    func allSavedArticles(offset: Int, limit: Int) throws -> [PersistentArticle] {
        var descriptor = FetchDescriptor<PersistentArticle>(
            predicate: #Predicate { $0.isSaved },
            sortBy: [
                SortDescriptor(\.savedDate, order: .reverse),
                SortDescriptor(\.articleID, order: .forward)
            ]
        )
        descriptor.fetchOffset = offset
        descriptor.fetchLimit = limit
        let articles = try modelContext.fetch(descriptor)
        Self.logger.debug("Fetched \(articles.count, privacy: .public) saved articles (offset: \(offset, privacy: .public), limit: \(limit, privacy: .public))")
        return articles
    }

    func savedCount() throws -> Int {
        let descriptor = FetchDescriptor<PersistentArticle>(
            predicate: #Predicate { $0.isSaved }
        )
        return try modelContext.fetchCount(descriptor)
    }

    // MARK: - Thumbnail Tracking

    func articlesNeedingThumbnails(maxRetryCount: Int) throws -> [PersistentArticle] {
        let descriptor = FetchDescriptor<PersistentArticle>(
            predicate: #Predicate {
                !$0.isThumbnailCached && $0.thumbnailRetryCount < maxRetryCount
            },
            sortBy: [
                SortDescriptor(\.sortDate, order: .reverse),
                SortDescriptor(\.articleID, order: .forward)
            ]
        )
        let articles = try modelContext.fetch(descriptor)
        Self.logger.debug("Found \(articles.count, privacy: .public) articles needing thumbnails (max retries: \(maxRetryCount, privacy: .public))")
        return articles
    }

    func markThumbnailCached(_ article: PersistentArticle) throws {
        article.isThumbnailCached = true
        Self.logger.debug("Marked thumbnail cached for '\(article.title, privacy: .public)'")
    }

    func incrementThumbnailRetryCount(_ article: PersistentArticle) throws {
        article.thumbnailRetryCount += 1
        Self.logger.debug("Incremented thumbnail retry count to \(article.thumbnailRetryCount, privacy: .public) for '\(article.title, privacy: .public)'")
    }

    func save() throws {
        try modelContext.save()
    }

    func unreadCount(for feed: PersistentFeed) throws -> Int {
        let feedID = feed.persistentModelID
        let descriptor = FetchDescriptor<PersistentArticle>(
            predicate: #Predicate { $0.feed?.persistentModelID == feedID && !$0.isRead }
        )
        return try modelContext.fetchCount(descriptor)
    }

    func totalUnreadCount() throws -> Int {
        let descriptor = FetchDescriptor<PersistentArticle>(
            predicate: #Predicate { !$0.isRead }
        )
        return try modelContext.fetchCount(descriptor)
    }

    // MARK: - Content Cache

    func cachedContent(for article: PersistentArticle) throws -> PersistentArticleContent? {
        article.content
    }

    func cacheContent(_ content: ArticleContent, for article: PersistentArticle) throws {
        if let existing = article.content {
            existing.title = content.title
            existing.byline = content.byline
            existing.htmlContent = content.htmlContent
            existing.textContent = content.textContent
            existing.extractedDate = Date()
        } else {
            let persistent = PersistentArticleContent(from: content)
            persistent.article = article
            modelContext.insert(persistent)
        }
        try modelContext.save()
        Self.logger.debug("Cached content for '\(article.title, privacy: .public)'")
    }

    // MARK: - Article Cleanup

    func totalArticleCount() throws -> Int {
        let descriptor = FetchDescriptor<PersistentArticle>()
        return try modelContext.fetchCount(descriptor)
    }

    func oldestArticleIDsExceedingLimit(_ limit: Int) throws -> [(articleID: String, isThumbnailCached: Bool)] {
        let totalCount = try totalArticleCount()
        guard totalCount > limit else { return [] }

        let excess = totalCount - limit
        // Exclude saved articles from retention cleanup — they are exempt from the limit
        var descriptor = FetchDescriptor<PersistentArticle>(
            predicate: #Predicate { !$0.isSaved },
            sortBy: [
                SortDescriptor(\.sortDate, order: .forward),
                SortDescriptor(\.articleID, order: .forward)
            ]
        )
        descriptor.fetchLimit = excess
        let articles = try modelContext.fetch(descriptor)
        Self.logger.debug("Found \(articles.count, privacy: .public) unsaved articles exceeding limit of \(limit, privacy: .public)")
        return articles.map { (articleID: $0.articleID, isThumbnailCached: $0.isThumbnailCached) }
    }

    /// Batch size for article deletion. Kept below SQLite's default 999 variable limit
    /// to avoid parameter overflow, while being large enough for efficient throughput.
    private static let deletionBatchSize = 500

    func deleteArticles(withIDs articleIDs: Set<String>) throws {
        guard !articleIDs.isEmpty else { return }

        let allIDs = Array(articleIDs)
        var totalDeleted = 0

        for batchStart in stride(from: 0, to: allIDs.count, by: Self.deletionBatchSize) {
            let batchNumber = batchStart / Self.deletionBatchSize + 1
            let batchEnd = min(batchStart + Self.deletionBatchSize, allIDs.count)
            let batchIDs = Array(allIDs[batchStart..<batchEnd])

            do {
                let descriptor = FetchDescriptor<PersistentArticle>(
                    predicate: #Predicate { batchIDs.contains($0.articleID) }
                )
                let articles = try modelContext.fetch(descriptor)
                for article in articles {
                    modelContext.delete(article)
                }
                try modelContext.save()
                totalDeleted += articles.count
                Self.logger.debug("Deleted batch \(batchNumber, privacy: .public): \(articles.count, privacy: .public) articles")
            } catch {
                Self.logger.error("Batch \(batchNumber, privacy: .public) failed after \(totalDeleted, privacy: .public) of \(articleIDs.count, privacy: .public) articles already deleted: \(error, privacy: .public)")
                throw error
            }
        }

        if totalDeleted != articleIDs.count {
            Self.logger.warning("Requested deletion of \(articleIDs.count, privacy: .public) articles but deleted \(totalDeleted, privacy: .public)")
        } else {
            Self.logger.notice("Deleted \(totalDeleted, privacy: .public) articles during cleanup")
        }
    }
}
