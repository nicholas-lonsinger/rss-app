import Foundation
import SwiftData
@testable import RSSApp

@MainActor
final class MockFeedPersistenceService: FeedPersisting {

    // MARK: - State

    var feeds: [PersistentFeed] = []
    var errorToThrow: (any Error)?
    var unreadCountError: (any Error)?
    var unreadCountErrorByFeedID: [UUID: any Error] = [:]
    var saveError: (any Error)?
    var updateFeedErrorError: (any Error)?
    var updateFeedMetadataError: (any Error)?
    var upsertArticlesError: (any Error)?
    var updateFeedCacheHeadersError: (any Error)?
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
        if let error = updateFeedMetadataError ?? errorToThrow { throw error }
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
        if let error = updateFeedCacheHeadersError ?? errorToThrow { throw error }
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

    // Mirrors production: primary sort by `sortDate`, secondary tie-breaker by
    // `articleID` ascending. The tie-breaker matters because clamped sortDates
    // collide frequently for articles ingested in the same batch (future-dated
    // and nil-pubDate articles all map to ≈ now). See `FeedPersistenceService`
    // for the production SortDescriptors this mirrors.
    private static func sortDescending(_ lhs: PersistentArticle, _ rhs: PersistentArticle) -> Bool {
        if lhs.sortDate != rhs.sortDate { return lhs.sortDate > rhs.sortDate }
        return lhs.articleID < rhs.articleID
    }

    private static func sortAscending(_ lhs: PersistentArticle, _ rhs: PersistentArticle) -> Bool {
        if lhs.sortDate != rhs.sortDate { return lhs.sortDate < rhs.sortDate }
        return lhs.articleID < rhs.articleID
    }

    func articles(for feed: PersistentFeed, offset: Int, limit: Int, ascending: Bool = false) throws -> [PersistentArticle] {
        if let error = errorToThrow { throw error }
        let all = (articlesByFeedID[feed.id] ?? [])
            .sorted(by: ascending ? Self.sortAscending : Self.sortDescending)
        return Array(all.dropFirst(offset).prefix(limit))
    }

    func unreadArticles(for feed: PersistentFeed, offset: Int, limit: Int, ascending: Bool = false) throws -> [PersistentArticle] {
        if let error = errorToThrow { throw error }
        let all = (articlesByFeedID[feed.id] ?? [])
            .filter { !$0.isRead }
            .sorted(by: ascending ? Self.sortAscending : Self.sortDescending)
        return Array(all.dropFirst(offset).prefix(limit))
    }

    func allArticles() throws -> [PersistentArticle] {
        if let error = errorToThrow { throw error }
        return articlesByFeedID.values
            .flatMap { $0 }
            .sorted(by: Self.sortDescending)
    }

    func allArticles(offset: Int, limit: Int, ascending: Bool = false) throws -> [PersistentArticle] {
        if let error = errorToThrow { throw error }
        let all = articlesByFeedID.values
            .flatMap { $0 }
            .sorted(by: ascending ? Self.sortAscending : Self.sortDescending)
        return Array(all.dropFirst(offset).prefix(limit))
    }

    func allUnreadArticles() throws -> [PersistentArticle] {
        if let error = errorToThrow { throw error }
        return articlesByFeedID.values
            .flatMap { $0 }
            .filter { !$0.isRead }
            .sorted(by: Self.sortDescending)
    }

    func allUnreadArticles(offset: Int, limit: Int, ascending: Bool = false) throws -> [PersistentArticle] {
        if let error = errorToThrow { throw error }
        let all = articlesByFeedID.values
            .flatMap { $0 }
            .filter { !$0.isRead }
            .sorted(by: ascending ? Self.sortAscending : Self.sortDescending)
        return Array(all.dropFirst(offset).prefix(limit))
    }

    func upsertArticles(_ articles: [Article], for feed: PersistentFeed) throws {
        if let error = upsertArticlesError ?? errorToThrow { throw error }
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
        // Mirror SwiftDataFeedPersistenceService.markArticleRead's issue #74 clear so
        // view-model tests using this mock catch a regression that removes the
        // production clear. Asymmetric: only on isRead = true.
        if isRead {
            article.wasUpdated = false
        }
    }

    func markAllArticlesRead(for feed: PersistentFeed) throws {
        if let error = errorToThrow { throw error }
        let now = Date()
        for article in (articlesByFeedID[feed.id] ?? []) where !article.isRead {
            article.isRead = true
            article.readDate = now
            article.wasUpdated = false
        }
    }

    func markAllArticlesRead() throws {
        if let error = errorToThrow { throw error }
        let now = Date()
        for articles in articlesByFeedID.values {
            for article in articles where !article.isRead {
                article.isRead = true
                article.readDate = now
                article.wasUpdated = false
            }
        }
    }

    func unreadCount(for feed: PersistentFeed) throws -> Int {
        if let perFeedError = unreadCountErrorByFeedID[feed.id] { throw perFeedError }
        if let error = unreadCountError ?? errorToThrow { throw error }
        return (articlesByFeedID[feed.id] ?? []).filter { !$0.isRead }.count
    }

    func totalUnreadCount() throws -> Int {
        if let error = unreadCountError ?? errorToThrow { throw error }
        return articlesByFeedID.values.flatMap { $0 }.filter { !$0.isRead }.count
    }

    // MARK: - Saved Article Operations

    func toggleArticleSaved(_ article: PersistentArticle) throws {
        if let error = errorToThrow { throw error }
        let newSaved = !article.isSaved
        article.isSaved = newSaved
        article.savedDate = newSaved ? Date() : nil
    }

    func allSavedArticles(offset: Int, limit: Int) throws -> [PersistentArticle] {
        if let error = errorToThrow { throw error }
        let all = articlesByFeedID.values
            .flatMap { $0 }
            .filter { $0.isSaved }
            .sorted {
                // Mirror production: primary by savedDate desc, tie-breaker by
                // articleID asc, matching the FeedPersistenceService.allSavedArticles
                // SortDescriptor pair.
                let lhs = $0.savedDate ?? .distantPast
                let rhs = $1.savedDate ?? .distantPast
                if lhs != rhs { return lhs > rhs }
                return $0.articleID < $1.articleID
            }
        return Array(all.dropFirst(offset).prefix(limit))
    }

    func savedCount() throws -> Int {
        if let error = errorToThrow { throw error }
        return articlesByFeedID.values.flatMap { $0 }.filter { $0.isSaved }.count
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

    // MARK: - Thumbnail Tracking

    func articlesNeedingThumbnails(maxRetryCount: Int) throws -> [PersistentArticle] {
        if let error = errorToThrow { throw error }
        return articlesByFeedID.values
            .flatMap { $0 }
            .filter { !$0.isThumbnailCached && $0.thumbnailRetryCount < maxRetryCount }
    }

    func markThumbnailCached(_ article: PersistentArticle) throws {
        if let error = errorToThrow { throw error }
        article.isThumbnailCached = true
    }

    func incrementThumbnailRetryCount(_ article: PersistentArticle) throws {
        if let error = errorToThrow { throw error }
        article.thumbnailRetryCount += 1
    }

    // MARK: - Article Cleanup

    var deleteArticlesCallCount = 0
    var deleteArticlesError: (any Error)?
    var lastDeletedArticleIDs: Set<String> = []

    func totalArticleCount() throws -> Int {
        if let error = errorToThrow { throw error }
        return articlesByFeedID.values.flatMap { $0 }.count
    }

    func oldestArticleIDsExceedingLimit(_ limit: Int) throws -> [(articleID: String, isThumbnailCached: Bool)] {
        if let error = errorToThrow { throw error }
        let all = articlesByFeedID.values
            .flatMap { $0 }
            .sorted {
                if $0.sortDate != $1.sortDate {
                    return $0.sortDate < $1.sortDate
                }
                // Tie-breaker by articleID matches production's secondary SortDescriptor
                return $0.articleID < $1.articleID
            }
        let totalCount = all.count
        guard totalCount > limit else { return [] }
        let excess = totalCount - limit
        // Exclude saved articles from retention cleanup, matching real implementation
        let unsaved = all.filter { !$0.isSaved }
        return Array(unsaved.prefix(excess)).map { (articleID: $0.articleID, isThumbnailCached: $0.isThumbnailCached) }
    }

    func deleteArticles(withIDs articleIDs: Set<String>) throws {
        if let error = deleteArticlesError ?? errorToThrow { throw error }
        deleteArticlesCallCount += 1
        lastDeletedArticleIDs = articleIDs
        for feedID in articlesByFeedID.keys {
            articlesByFeedID[feedID]?.removeAll { articleIDs.contains($0.articleID) }
        }
    }

    // MARK: - Persistence

    func save() throws {
        if let error = saveError ?? errorToThrow { throw error }
    }
}
