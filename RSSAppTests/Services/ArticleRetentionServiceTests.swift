import Testing
import Foundation
@testable import RSSApp

@Suite("ArticleRetentionService Tests")
struct ArticleRetentionServiceTests {

    /// The UserDefaults key used by ArticleRetentionService, duplicated here for
    /// tests that deliberately write invalid values to verify fallback behavior.
    /// The production key is intentionally private to prevent direct UserDefaults access.
    private static let articleLimitDefaultsKey = "articleRetentionLimit"

    // MARK: - ArticleLimit enum

    @Test("ArticleLimit has correct raw values")
    func articleLimitRawValues() {
        #expect(ArticleLimit.oneThousand.rawValue == 1_000)
        #expect(ArticleLimit.twoThousandFiveHundred.rawValue == 2_500)
        #expect(ArticleLimit.fiveThousand.rawValue == 5_000)
        #expect(ArticleLimit.tenThousand.rawValue == 10_000)
        #expect(ArticleLimit.twelveThousandFiveHundred.rawValue == 12_500)
        #expect(ArticleLimit.fifteenThousand.rawValue == 15_000)
        #expect(ArticleLimit.twentyFiveThousand.rawValue == 25_000)
    }

    @Test("ArticleLimit has seven options")
    func articleLimitAllCases() {
        #expect(ArticleLimit.allCases.count == 7)
    }

    @Test("ArticleLimit default is 10,000")
    func articleLimitDefault() {
        #expect(ArticleLimit.defaultLimit == .tenThousand)
        #expect(ArticleLimit.defaultLimit.rawValue == 10_000)
    }

    @Test("ArticleLimit displayLabel formats with separator")
    func articleLimitDisplayLabel() {
        #expect(ArticleLimit.oneThousand.displayLabel == "1,000")
        #expect(ArticleLimit.tenThousand.displayLabel == "10,000")
        #expect(ArticleLimit.twentyFiveThousand.displayLabel == "25,000")
    }

    @Test("ArticleLimit id matches rawValue")
    func articleLimitID() {
        for limit in ArticleLimit.allCases {
            #expect(limit.id == limit.rawValue)
        }
    }

    @Test("ArticleLimit initializes from valid rawValue")
    func articleLimitFromRawValue() {
        #expect(ArticleLimit(rawValue: 5_000) == .fiveThousand)
        #expect(ArticleLimit(rawValue: 25_000) == .twentyFiveThousand)
    }

    @Test("ArticleLimit returns nil for invalid rawValue")
    func articleLimitInvalidRawValue() {
        #expect(ArticleLimit(rawValue: 999) == nil)
        #expect(ArticleLimit(rawValue: 0) == nil)
        #expect(ArticleLimit(rawValue: 50_000) == nil)
    }

    // MARK: - enforceArticleLimit

    @Test("enforceArticleLimit does nothing when count is within limit")
    @MainActor
    func enforceWithinLimit() throws {
        let persistence = MockFeedPersistenceService()
        let thumbnailService = MockArticleThumbnailService()

        let feed = TestFixtures.makePersistentFeed()
        persistence.feeds = [feed]
        persistence.articlesByFeedID[feed.id] = [
            TestFixtures.makePersistentArticle(articleID: "a1"),
            TestFixtures.makePersistentArticle(articleID: "a2"),
        ]

        let service = ArticleRetentionService()
        service.articleLimit = .tenThousand
        defer { service.articleLimit = .defaultLimit }

        try service.enforceArticleLimit(
            persistence: persistence,
            thumbnailService: thumbnailService
        )

        #expect(persistence.deleteArticlesCallCount == 0)
        #expect(thumbnailService.deleteCallCount == 0)
    }

    @Test("enforceArticleLimit does nothing when count exactly equals limit")
    @MainActor
    func enforceExactlyAtLimit() throws {
        let persistence = MockFeedPersistenceService()
        let thumbnailService = MockArticleThumbnailService()

        let feed = TestFixtures.makePersistentFeed()
        persistence.feeds = [feed]

        let baseDate = Date(timeIntervalSince1970: 1_000_000)
        // Create exactly 1000 articles with a limit of 1000
        persistence.articlesByFeedID[feed.id] = (0..<1000).map { i in
            TestFixtures.makePersistentArticle(
                articleID: "article-\(i)",
                publishedDate: baseDate.addingTimeInterval(Double(i) * 60)
            )
        }

        let service = ArticleRetentionService()
        service.articleLimit = .oneThousand
        defer { service.articleLimit = .defaultLimit }

        try service.enforceArticleLimit(
            persistence: persistence,
            thumbnailService: thumbnailService
        )

        #expect(persistence.deleteArticlesCallCount == 0)
        #expect(thumbnailService.deleteCallCount == 0)
    }

    @Test("enforceArticleLimit deletes oldest articles when count exceeds limit")
    @MainActor
    func enforceExceedsLimit() throws {
        let persistence = MockFeedPersistenceService()
        let thumbnailService = MockArticleThumbnailService()

        let feed = TestFixtures.makePersistentFeed()
        persistence.feeds = [feed]

        let baseDate = Date(timeIntervalSince1970: 1_000_000)
        // Create 1002 articles with limit of 1000 => 2 oldest should be deleted
        persistence.articlesByFeedID[feed.id] = (0..<1002).map { i in
            TestFixtures.makePersistentArticle(
                articleID: "article-\(i)",
                publishedDate: baseDate.addingTimeInterval(Double(i) * 60)
            )
        }

        // Set smallest valid limit
        let service = ArticleRetentionService()
        service.articleLimit = .oneThousand
        defer { service.articleLimit = .defaultLimit }

        try service.enforceArticleLimit(
            persistence: persistence,
            thumbnailService: thumbnailService
        )

        #expect(persistence.deleteArticlesCallCount == 1)
        #expect(persistence.lastDeletedArticleIDs.count == 2)
        #expect(persistence.lastDeletedArticleIDs.contains("article-0"))
        #expect(persistence.lastDeletedArticleIDs.contains("article-1"))
    }

    @Test("enforceArticleLimit deletes thumbnails for cached articles only")
    @MainActor
    func enforceThumbnailCleanup() throws {
        let persistence = MockFeedPersistenceService()
        let thumbnailService = MockArticleThumbnailService()

        let feed = TestFixtures.makePersistentFeed()
        persistence.feeds = [feed]

        let baseDate = Date(timeIntervalSince1970: 1_000_000)
        // 1002 articles: 2 oldest will be deleted (one cached, one uncached thumbnail).
        var articles: [PersistentArticle] = [
            TestFixtures.makePersistentArticle(
                articleID: "old-cached",
                publishedDate: baseDate,
                isThumbnailCached: true
            ),
            TestFixtures.makePersistentArticle(
                articleID: "old-uncached",
                publishedDate: baseDate.addingTimeInterval(60),
                isThumbnailCached: false
            ),
        ]
        // Add 1000 newer articles to push total to 1002
        for i in 0..<1000 {
            articles.append(TestFixtures.makePersistentArticle(
                articleID: "new-\(i)",
                publishedDate: baseDate.addingTimeInterval(Double(i + 2) * 60)
            ))
        }
        persistence.articlesByFeedID[feed.id] = articles

        let service = ArticleRetentionService()
        service.articleLimit = .oneThousand
        defer { service.articleLimit = .defaultLimit }

        try service.enforceArticleLimit(
            persistence: persistence,
            thumbnailService: thumbnailService
        )

        // Only 1 of the 2 deleted articles has a cached thumbnail
        #expect(thumbnailService.deleteCallCount == 1)
        #expect(thumbnailService.deletedArticleIDs == ["old-cached"])
        #expect(persistence.deleteArticlesCallCount == 1)
        #expect(persistence.lastDeletedArticleIDs.count == 2)
        #expect(persistence.lastDeletedArticleIDs.contains("old-cached"))
        #expect(persistence.lastDeletedArticleIDs.contains("old-uncached"))
    }

    @Test("enforceArticleLimit deletes articles globally across feeds by oldest date")
    @MainActor
    func enforceGlobalCleanup() throws {
        let persistence = MockFeedPersistenceService()
        let thumbnailService = MockArticleThumbnailService()

        let feed1 = TestFixtures.makePersistentFeed(title: "Feed 1")
        let feed2 = TestFixtures.makePersistentFeed(title: "Feed 2")
        persistence.feeds = [feed1, feed2]

        let baseDate = Date(timeIntervalSince1970: 1_000_000)
        // Feed 1: 1 old + 500 new articles
        var feed1Articles = [TestFixtures.makePersistentArticle(
            articleID: "f1-old",
            publishedDate: baseDate
        )]
        for i in 0..<500 {
            feed1Articles.append(TestFixtures.makePersistentArticle(
                articleID: "f1-new-\(i)",
                publishedDate: baseDate.addingTimeInterval(Double(i + 2) * 60)
            ))
        }
        persistence.articlesByFeedID[feed1.id] = feed1Articles

        // Feed 2: 1 mid-age + 500 new articles
        var feed2Articles = [TestFixtures.makePersistentArticle(
            articleID: "f2-mid",
            publishedDate: baseDate.addingTimeInterval(30)
        )]
        for i in 0..<500 {
            feed2Articles.append(TestFixtures.makePersistentArticle(
                articleID: "f2-new-\(i)",
                publishedDate: baseDate.addingTimeInterval(Double(i + 2) * 60 + 30)
            ))
        }
        persistence.articlesByFeedID[feed2.id] = feed2Articles

        // Total: 1002 articles. Limit of 1000 => delete 2 oldest (f1-old and f2-mid)
        let service = ArticleRetentionService()
        service.articleLimit = .oneThousand
        defer { service.articleLimit = .defaultLimit }

        try service.enforceArticleLimit(
            persistence: persistence,
            thumbnailService: thumbnailService
        )

        #expect(persistence.deleteArticlesCallCount == 1)
        #expect(persistence.lastDeletedArticleIDs.count == 2)
        #expect(persistence.lastDeletedArticleIDs.contains("f1-old"))
        #expect(persistence.lastDeletedArticleIDs.contains("f2-mid"))
    }

    @Test("enforceArticleLimit propagates persistence errors")
    @MainActor
    func enforcePersistenceError() throws {
        let persistence = MockFeedPersistenceService()
        let thumbnailService = MockArticleThumbnailService()
        persistence.errorToThrow = NSError(domain: "test", code: 1)

        let service = ArticleRetentionService()

        #expect(throws: (any Error).self) {
            try service.enforceArticleLimit(
                persistence: persistence,
                thumbnailService: thumbnailService
            )
        }
    }

    @Test("enforceArticleLimit uses default limit when UserDefaults has no value")
    @MainActor
    func enforceDefaultLimit() throws {
        UserDefaults.standard.removeObject(forKey: Self.articleLimitDefaultsKey)

        let service = ArticleRetentionService()
        #expect(service.articleLimit == .defaultLimit)
        #expect(service.articleLimit.rawValue == 10_000)
    }

    @Test("enforceArticleLimit uses default limit when UserDefaults has invalid value")
    @MainActor
    func enforceInvalidUserDefaultsValue() throws {
        UserDefaults.standard.set(999, forKey: Self.articleLimitDefaultsKey)
        defer { UserDefaults.standard.removeObject(forKey: Self.articleLimitDefaultsKey) }

        let service = ArticleRetentionService()
        #expect(service.articleLimit == .defaultLimit)
    }
}
