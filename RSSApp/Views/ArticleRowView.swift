import SwiftUI

/// Article row used by every list view in the app. Always shows the article's
/// source feed (icon + title) on the bottom line, regardless of whether the
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

                metadataGrid
                    .padding(.top, 2)
            }
        }
    }

    /// Bottom metadata block — feed source, publish date, saved indicator, and
    /// (optionally) the "Updated" suffix and call-to-action badge laid out in a
    /// 3-column SwiftUI `Grid` so everything aligns:
    ///
    ///     | Feed icon + title | Publish date  <fills>  | bookmark.fill (if saved) |
    ///     |     (empty)       | Updated suffix <fills> |       (empty)            |
    ///
    /// Using `Grid` rather than a nested HStack keeps the feed name on its own
    /// horizontal baseline with the publish date instead of being vertically
    /// centered against a two-line `VStack` of dates — and keeps the "Updated"
    /// suffix horizontally aligned under the publish date it's annotating.
    /// Row 2 exists only when there is something to show there.
    @ViewBuilder
    private var metadataGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 6, verticalSpacing: 2) {
            GridRow {
                feedLabel
                Text(publishDateText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                savedIndicator
            }

            if article.shouldShowUpdatedSuffix || article.wasUpdated {
                GridRow {
                    // Empty first-column cell keeps the column's width but adds
                    // no content, so the updated suffix below aligns under the
                    // publish date in col 2.
                    Color.clear
                    updatedLine
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Color.clear
                }
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var feedLabel: some View {
        if let feed = article.feed {
            HStack(spacing: 3) {
                FeedIconView(
                    feedID: feed.id,
                    iconURL: feed.iconURL,
                    iconService: iconService,
                    style: .inline
                )
                Text(feed.title)
            }
        } else {
            // Placeholder keeps the grid column's intrinsic width at zero when
            // the article has no feed relationship (should not happen in
            // practice, but the grid cell still needs a view).
            Color.clear
        }
    }

    /// Right-edge bookmark indicator, shown on every row whose article is
    /// currently saved. The orange fill matches the trailing swipe-action tint
    /// so the saved state reads consistently across all affordances.
    ///
    /// Always rendered — hidden via `.opacity(0)` on unsaved rows rather than
    /// replaced with a conditional placeholder. A `Color.clear` placeholder
    /// collapses the grid column to zero width, which shifts col 2's flex
    /// allocation and cascades into the parent `VStack`'s natural width —
    /// making the title and snippet wrap differently on saved vs. unsaved
    /// rows of the same article. Reserving the bookmark's width on every row
    /// keeps the layout stable across state transitions.
    private var savedIndicator: some View {
        Image(systemName: "bookmark.fill")
            .foregroundStyle(.orange)
            .opacity(article.isSaved ? 1 : 0)
            .accessibilityLabel("Saved")
            .accessibilityHidden(!article.isSaved)
    }

    /// Row 2 content — the "Updated [relative date]" informational suffix and
    /// (optionally) the orange call-to-action capsule badge. Rendered only
    /// when `shouldShowUpdatedSuffix || wasUpdated`.
    ///
    /// - `shouldShowUpdatedSuffix` is kept relative ("Updated 3 days ago") so
    ///   freshness reads at a glance and is independent of the user's read
    ///   state, so it remains visible even after reading the latest version.
    /// - `wasUpdated` is the call-to-action: an orange capsule marking the
    ///   article as having new content the user hasn't read yet. Clears on
    ///   every read transition (`markArticleRead`, `markAllArticlesRead`).
    ///   When the suffix is suppressed (e.g. a feed reports `updated <=
    ///   published` per issue #299) but `wasUpdated` is still true, the badge
    ///   stands alone so the call to action is never lost.
    @ViewBuilder
    private var updatedLine: some View {
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

    /// Absolute short date for the publish line. Omits the year when
    /// `displayedPublishedDate` is in the current calendar year, includes it
    /// otherwise — keeps the common case compact ("Apr 7") while staying
    /// unambiguous across year boundaries ("Dec 28, 2024" vs this year's
    /// "Dec 28"). Sourced from `displayedPublishedDate` (not `sortDate`) so
    /// the future-date clamp and the `sortDate`-vs-`publishedDate` distinction
    /// on `PersistentArticle` are preserved — see the RATIONALE on
    /// `PersistentArticle.sortDate`.
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
