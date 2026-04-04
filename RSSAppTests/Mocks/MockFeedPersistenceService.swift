import Foundation
import SwiftData
@testable import RSSApp

@MainActor
final class MockFeedPersistenceService: FeedPersisting {

    // MARK: - State

    var feeds: [PersistentFeed] = []
    var errorToThrow: (any Error)?
    var unreadCountError: (any Error)?
    var saveError: (any Error)?
    var updateFeedErrorError: (any Error)?
    var addFeedFailureAfterCount: Int?

    var articlesByFeedID: [UUID: [PersistentArticle]] = [:]
    private var contentByArticleID: [String: PersistentArticleContent] = [:]
    private var addFeedCallCount = 0

    // MARK: - Feed Operations

    func allFeeds() throws -> [PersistentFeed] {
        if let error = errorToThrow { throw error }
        return feeds
    }

    func addFeed(_ feed: PersistentFeed) throws {
        if let error = errorToThrow { throw error }
        if let limit = addFeedFailureAfterCount, addFeedCallCount >= limit {
            throw NSError(domain: "MockPersistence", code: 1, userInfo: [NSLocalizedDescriptionKey: "Simulated persistence failure"])
        }
        addFeedCallCount += 1
        feeds.append(feed)
    }

    func deleteFeed(_ feed: PersistentFeed) throws {
        if let error = errorToThrow { throw error }
        feeds.removeAll { $0.id == feed.id }
        articlesByFeedID.removeValue(forKey: feed.id)
    }

    func updateFeedMetadata(_ feed: PersistentFeed, title: String, description: String) throws {
        if let error = errorToThrow { throw error }
        feed.title = title
        feed.feedDescription = description
        feed.lastRefreshDate = Date()
        feed.lastFetchError = nil
        feed.lastFetchErrorDate = nil
    }

    func updateFeedError(_ feed: PersistentFeed, error: String?) throws {
        if let error = updateFeedErrorError ?? errorToThrow { throw error }
        feed.lastFetchError = error
        feed.lastFetchErrorDate = error != nil ? Date() : nil
    }

    func updateFeedURL(_ feed: PersistentFeed, newURL: URL) throws {
        if let error = errorToThrow { throw error }
        feed.feedURL = newURL
        feed.lastFetchError = nil
        feed.lastFetchErrorDate = nil
    }

    func updateFeedCacheHeaders(_ feed: PersistentFeed, etag: String?, lastModified: String?) throws {
        if let error = errorToThrow { throw error }
        feed.etag = etag
        feed.lastModifiedHeader = lastModified
    }

    func updateFeedIcon(_ feed: PersistentFeed, iconURL: URL?) throws {
        if let error = errorToThrow { throw error }
        feed.iconURL = iconURL
    }

    func feedExists(url: URL) throws -> Bool {
        if let error = errorToThrow { throw error }
        return feeds.contains { $0.feedURL == url }
    }

    // MARK: - Article Operations

    func articles(for feed: PersistentFeed) throws -> [PersistentArticle] {
        if let error = errorToThrow { throw error }
        return articlesByFeedID[feed.id] ?? []
    }

    func allArticles() throws -> [PersistentArticle] {
        if let error = errorToThrow { throw error }
        return articlesByFeedID.values
            .flatMap { $0 }
            .sorted { ($0.publishedDate ?? .distantPast) > ($1.publishedDate ?? .distantPast) }
    }

    func allUnreadArticles() throws -> [PersistentArticle] {
        if let error = errorToThrow { throw error }
        return articlesByFeedID.values
            .flatMap { $0 }
            .filter { !$0.isRead }
            .sorted { ($0.publishedDate ?? .distantPast) > ($1.publishedDate ?? .distantPast) }
    }

    func upsertArticles(_ articles: [Article], for feed: PersistentFeed) throws {
        if let error = errorToThrow { throw error }
        let existingIDs = Set((articlesByFeedID[feed.id] ?? []).map(\.articleID))
        for article in articles where !existingIDs.contains(article.id) {
            let persistent = PersistentArticle(from: article)
            persistent.feed = feed
            var existing = articlesByFeedID[feed.id] ?? []
            existing.append(persistent)
            articlesByFeedID[feed.id] = existing
        }
    }

    func markArticleRead(_ article: PersistentArticle, isRead: Bool) throws {
        if let error = errorToThrow { throw error }
        article.isRead = isRead
        article.readDate = isRead ? Date() : nil
    }

    func unreadCount(for feed: PersistentFeed) throws -> Int {
        if let error = unreadCountError ?? errorToThrow { throw error }
        return (articlesByFeedID[feed.id] ?? []).filter { !$0.isRead }.count
    }

    func totalUnreadCount() throws -> Int {
        if let error = unreadCountError ?? errorToThrow { throw error }
        return articlesByFeedID.values.flatMap { $0 }.filter { !$0.isRead }.count
    }

    // MARK: - Content Cache

    func cachedContent(for article: PersistentArticle) throws -> PersistentArticleContent? {
        if let error = errorToThrow { throw error }
        return contentByArticleID[article.articleID]
    }

    func cacheContent(_ content: ArticleContent, for article: PersistentArticle) throws {
        if let error = errorToThrow { throw error }
        let persistent = PersistentArticleContent(from: content)
        persistent.article = article
        contentByArticleID[article.articleID] = persistent
    }

    // MARK: - Persistence

    func save() throws {
        if let error = saveError ?? errorToThrow { throw error }
    }
}
