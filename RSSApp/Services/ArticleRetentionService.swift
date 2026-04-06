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

    private static let logger = Logger(category: "ArticleLimit")

    var id: Int { rawValue }

    private static let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()

    var displayLabel: String {
        guard let formatted = Self.numberFormatter.string(from: NSNumber(value: rawValue)) else {
            Self.logger.fault("NumberFormatter failed for rawValue '\(rawValue, privacy: .public)'")
            assertionFailure("NumberFormatter failed for rawValue: \(rawValue)")
            return "\(rawValue)"
        }
        return formatted
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

    private static let articleLimitDefaultsKey = "articleRetentionLimit"

    var articleLimit: ArticleLimit {
        get {
            let stored = UserDefaults.standard.integer(forKey: Self.articleLimitDefaultsKey)
            return ArticleLimit(rawValue: stored) ?? .defaultLimit
        }
        // RATIONALE: nonmutating because the backing store is UserDefaults, not a stored
        // property on self. This allows views to call the setter without requiring a mutable
        // binding to the service.
        nonmutating set {
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
        guard !articlesToDelete.isEmpty else {
            Self.logger.warning("Count \(totalCount, privacy: .public) exceeds limit \(limit, privacy: .public) but no articles returned for deletion — possible count/fetch inconsistency")
            return
        }

        // Collect thumbnail info before deletion so we can clean up files afterward
        let cachedThumbnailIDs = articlesToDelete
            .filter(\.isThumbnailCached)
            .map(\.articleID)

        // Delete database records first. With batched deletion, a failure in a later
        // batch leaves earlier batches committed. Deleting DB records before thumbnails
        // ensures articles still in the DB always have their thumbnail files intact.
        // On partial failure, orphaned thumbnail files from successfully-deleted articles
        // are harmless disk waste — they remain on disk until the OS purges the Caches
        // directory under storage pressure. There is no orphan-scanning mechanism;
        // only articles still in the DB have their thumbnails cleaned up.
        let articleIDs = Set(articlesToDelete.map(\.articleID))
        try persistence.deleteArticles(withIDs: articleIDs)

        // Full success: delete all thumbnail files for deleted articles
        for articleID in cachedThumbnailIDs {
            thumbnailService.deleteCachedThumbnail(for: articleID)
        }

        Self.logger.notice("Cleanup complete: deleted \(articlesToDelete.count, privacy: .public) articles")
    }
}
