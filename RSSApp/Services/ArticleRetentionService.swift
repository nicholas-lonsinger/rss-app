import Foundation
import os

// MARK: - Article Limit Options

enum ArticleLimit: Int, CaseIterable, Identifiable {
    case oneThousand = 1_000
    case twoThousandFiveHundred = 2_500
    case fiveThousand = 5_000
    case tenThousand = 10_000
    case twelveThousandFiveHundred = 12_500
    case fifteenThousand = 15_000
    case twentyFiveThousand = 25_000

    var id: Int { rawValue }

    var displayLabel: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: rawValue)) ?? "\(rawValue)"
    }

    static let defaultLimit: ArticleLimit = .tenThousand
}

// MARK: - Protocol

@MainActor
protocol ArticleRetaining: Sendable {
    /// The current article limit setting.
    var articleLimit: ArticleLimit { get set }

    /// Cleans up articles that exceed the configured limit.
    /// Deletes the oldest articles (by `publishedDate`) and their associated thumbnail files.
    /// - Parameters:
    ///   - persistence: The persistence service to query and delete articles.
    ///   - thumbnailService: The thumbnail service to delete cached thumbnail files.
    func enforceArticleLimit(
        persistence: FeedPersisting,
        thumbnailService: ArticleThumbnailCaching
    ) throws
}

// MARK: - Implementation

@MainActor
struct ArticleRetentionService: ArticleRetaining {

    private static let logger = Logger(category: "ArticleRetentionService")

    static let articleLimitDefaultsKey = "articleRetentionLimit"

    var articleLimit: ArticleLimit {
        get {
            let stored = UserDefaults.standard.integer(forKey: Self.articleLimitDefaultsKey)
            return ArticleLimit(rawValue: stored) ?? .defaultLimit
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: Self.articleLimitDefaultsKey)
            Self.logger.notice("Article limit changed to \(newValue.rawValue, privacy: .public)")
        }
    }

    func enforceArticleLimit(
        persistence: FeedPersisting,
        thumbnailService: ArticleThumbnailCaching
    ) throws {
        let limit = articleLimit.rawValue
        let totalCount = try persistence.totalArticleCount()

        guard totalCount > limit else {
            Self.logger.debug("Article count \(totalCount, privacy: .public) within limit \(limit, privacy: .public), no cleanup needed")
            return
        }

        Self.logger.notice("Article count \(totalCount, privacy: .public) exceeds limit \(limit, privacy: .public), starting cleanup")

        let articlesToDelete = try persistence.oldestArticleIDsExceedingLimit(limit)
        guard !articlesToDelete.isEmpty else { return }

        // Delete thumbnail files for articles that have cached thumbnails
        for article in articlesToDelete where article.isThumbnailCached {
            thumbnailService.deleteCachedThumbnail(for: article.articleID)
        }

        let articleIDs = Set(articlesToDelete.map(\.articleID))
        try persistence.deleteArticles(withIDs: articleIDs)

        Self.logger.notice("Cleanup complete: deleted \(articlesToDelete.count, privacy: .public) articles")
    }
}
