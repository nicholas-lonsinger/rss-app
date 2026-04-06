import Foundation
@testable import RSSApp

@MainActor
final class MockArticleRetentionService: ArticleRetaining {

    var articleLimit: ArticleLimit = .defaultLimit
    var enforceCallCount = 0
    var enforceError: (any Error)?
    var lastPersistence: (any FeedPersisting)?
    var lastThumbnailService: (any ArticleThumbnailCaching)?

    func enforceArticleLimit(
        persistence: FeedPersisting,
        thumbnailService: ArticleThumbnailCaching
    ) throws {
        enforceCallCount += 1
        lastPersistence = persistence
        lastThumbnailService = thumbnailService
        if let error = enforceError { throw error }
    }
}
