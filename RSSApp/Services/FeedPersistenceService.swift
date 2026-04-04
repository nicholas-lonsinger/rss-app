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

    func articles(for feed: PersistentFeed) throws -> [PersistentArticle]
    /// Returns articles for a feed with pagination, sorted by published date descending (newest first).
    func articles(for feed: PersistentFeed, offset: Int, limit: Int) throws -> [PersistentArticle]
    /// Returns all articles across all feeds, sorted by published date descending (newest first).
    func allArticles() throws -> [PersistentArticle]
    /// Returns articles across all feeds with pagination, sorted by published date descending (newest first).
    func allArticles(offset: Int, limit: Int) throws -> [PersistentArticle]
    /// Returns all unread articles across all feeds, sorted by published date descending (newest first).
    func allUnreadArticles() throws -> [PersistentArticle]
    /// Returns unread articles across all feeds with pagination, sorted by published date descending (newest first).
    func allUnreadArticles(offset: Int, limit: Int) throws -> [PersistentArticle]
    func upsertArticles(_ articles: [Article], for feed: PersistentFeed) throws
    func markArticleRead(_ article: PersistentArticle, isRead: Bool) throws
    func unreadCount(for feed: PersistentFeed) throws -> Int
    /// Returns the total number of unread articles across all feeds.
    func totalUnreadCount() throws -> Int

    // MARK: Content cache

    func cachedContent(for article: PersistentArticle) throws -> PersistentArticleContent?
    func cacheContent(_ content: ArticleContent, for article: PersistentArticle) throws

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
            sortBy: [SortDescriptor(\.publishedDate, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }

    func articles(for feed: PersistentFeed, offset: Int, limit: Int) throws -> [PersistentArticle] {
        let feedID = feed.persistentModelID
        var descriptor = FetchDescriptor<PersistentArticle>(
            predicate: #Predicate { $0.feed?.persistentModelID == feedID },
            sortBy: [SortDescriptor(\.publishedDate, order: .reverse)]
        )
        descriptor.fetchOffset = offset
        descriptor.fetchLimit = limit
        let articles = try modelContext.fetch(descriptor)
        Self.logger.debug("Fetched \(articles.count, privacy: .public) articles for feed (offset: \(offset, privacy: .public), limit: \(limit, privacy: .public))")
        return articles
    }

    func allArticles() throws -> [PersistentArticle] {
        let descriptor = FetchDescriptor<PersistentArticle>(
            sortBy: [SortDescriptor(\.publishedDate, order: .reverse)]
        )
        let articles = try modelContext.fetch(descriptor)
        Self.logger.debug("Fetched \(articles.count, privacy: .public) total articles")
        return articles
    }

    func allArticles(offset: Int, limit: Int) throws -> [PersistentArticle] {
        var descriptor = FetchDescriptor<PersistentArticle>(
            sortBy: [SortDescriptor(\.publishedDate, order: .reverse)]
        )
        descriptor.fetchOffset = offset
        descriptor.fetchLimit = limit
        let articles = try modelContext.fetch(descriptor)
        Self.logger.debug("Fetched \(articles.count, privacy: .public) total articles (offset: \(offset, privacy: .public), limit: \(limit, privacy: .public))")
        return articles
    }

    func allUnreadArticles() throws -> [PersistentArticle] {
        let descriptor = FetchDescriptor<PersistentArticle>(
            predicate: #Predicate { !$0.isRead },
            sortBy: [SortDescriptor(\.publishedDate, order: .reverse)]
        )
        let articles = try modelContext.fetch(descriptor)
        Self.logger.debug("Fetched \(articles.count, privacy: .public) unread articles")
        return articles
    }

    func allUnreadArticles(offset: Int, limit: Int) throws -> [PersistentArticle] {
        var descriptor = FetchDescriptor<PersistentArticle>(
            predicate: #Predicate { !$0.isRead },
            sortBy: [SortDescriptor(\.publishedDate, order: .reverse)]
        )
        descriptor.fetchOffset = offset
        descriptor.fetchLimit = limit
        let articles = try modelContext.fetch(descriptor)
        Self.logger.debug("Fetched \(articles.count, privacy: .public) unread articles (offset: \(offset, privacy: .public), limit: \(limit, privacy: .public))")
        return articles
    }

    // RATIONALE: Insert-only by design — existing articles are never updated because preserving
    // user-generated state (read status, cached content) is more important than reflecting
    // minor metadata edits (title rewording) from the feed source.
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
}
