import SwiftUI

/// Article row used by every list view in the app. Always shows the article's
/// source feed (icon + title) on the second line, regardless of whether the
/// containing list is cross-feed (All / Unread / Saved / Group / Label) or
/// single-feed (a feed's own article list). Unified so every row is
/// self-describing — removing per-list row variants and keeping behavior
/// identical across entry points.
struct ArticleRowView: View {
    let article: PersistentArticle
    let thumbnailService: ArticleThumbnailCaching
    let iconService: FeedIconResolving

    init(
        article: PersistentArticle,
        thumbnailService: ArticleThumbnailCaching,
        iconService: FeedIconResolving = FeedIconService()
    ) {
        self.article = article
        self.thumbnailService = thumbnailService
        self.iconService = iconService
    }

    var body: some View {
        HStack(spacing: 8) {
            ArticleThumbnailView(
                articleID: article.articleID,
                thumbnailURL: article.thumbnailURL,
                articleLink: article.link,
                thumbnailService: thumbnailService
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(article.title)
                    .font(.headline)
                    .fontWeight(article.isRead ? .regular : .semibold)
                    .foregroundStyle(article.isRead ? .secondary : .primary)
                    .lineLimit(2)

                Text(article.snippet)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                HStack(spacing: 3) {
                    if let feed = article.feed {
                        FeedIconView(
                            feedID: feed.id,
                            iconURL: feed.iconURL,
                            iconService: iconService,
                            style: .inline
                        )

                        Text(feed.title)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text("\u{00B7}")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    ArticleRowDateLine(article: article)
                }
                .padding(.top, 2)
            }
        }
    }
}

/// Two-line date block for article rows (issue #300).
///
/// **Line 1 (always):** the article's publish date as an absolute short date —
/// `Apr 7` for items in the current year, `Apr 7, 2025` when the year differs.
/// Absolute rather than relative so readers can scan a list and compare items
/// by real calendar position instead of parsing "2 days ago" phrases. Sourced
/// from `displayedPublishedDate` (not `sortDate`) so the future-date clamp and
/// the `sortDate`-vs-`publishedDate` distinction on `PersistentArticle` are
/// preserved — see the RATIONALE on `PersistentArticle.sortDate`.
///
/// **Line 2 (conditional):** rendered only when `shouldShowUpdatedSuffix` or
/// `wasUpdated` is true. Contains up to two adjacent elements:
/// - An *informational* "Updated [relative date]" suffix when
///   `shouldShowUpdatedSuffix` is true — kept relative so freshness reads at a
///   glance ("Updated 3 days ago"). Independent of the user's read state, so
///   it remains visible even after reading the latest version.
/// - An *orange capsule badge* — the `wasUpdated` call-to-action — rendered
///   when `wasUpdated == true`. Appears only when the article has new content
///   the user hasn't read yet; clears on every read transition
///   (`markArticleRead`, `markAllArticlesRead`). When the suffix is suppressed
///   (e.g., because a feed reports `updated <= published` per issue #299) but
///   `wasUpdated` is still true, the badge stands alone on line 2 so the call
///   to action is never lost.
struct ArticleRowDateLine: View {
    let article: PersistentArticle

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(publishDateText)

            if article.shouldShowUpdatedSuffix || article.wasUpdated {
                HStack(spacing: 6) {
                    if article.shouldShowUpdatedSuffix, let updated = article.updatedDate {
                        Text("Updated \(updated, format: .relative(presentation: .named))")
                    }

                    if article.wasUpdated {
                        Text("Updated")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.15), in: Capsule())
                    }
                }
            }
        }
        // Apply caption font and secondary color to the whole VStack so both
        // the absolute-date line and the "Updated [date]" suffix text inherit
        // them. The orange badge overrides both via its own modifier chain.
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    /// Absolute short date for the publish line. Omits the year when
    /// `displayedPublishedDate` is in the current calendar year, includes it
    /// otherwise — keeps the common case compact ("Apr 7") while staying
    /// unambiguous across year boundaries ("Dec 28, 2024" vs this year's
    /// "Dec 28").
    private var publishDateText: String {
        let sameYear = Calendar.current.isDate(
            article.displayedPublishedDate,
            equalTo: Date(),
            toGranularity: .year
        )
        let style: Date.FormatStyle = sameYear
            ? .dateTime.month(.abbreviated).day()
            : .dateTime.month(.abbreviated).day().year()
        return article.displayedPublishedDate.formatted(style)
    }
}
