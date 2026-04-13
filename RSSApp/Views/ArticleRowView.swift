import SwiftUI
import os

/// Article row used by every list view in the app. Always shows the article's
/// source feed (icon + title) on the bottom line, regardless of whether the
/// containing list is cross-feed (All / Unread / Saved / Group / Label) or
/// single-feed (a feed's own article list). Unified so every row is
/// self-describing — removing per-list row variants and keeping behavior
/// identical across entry points.
struct ArticleRowView: View {

    private static let logger = Logger(category: "ArticleRowView")

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

                metadataFooter
                    .padding(.top, 2)
            }
        }
    }

    /// Bottom metadata block — feed source, date, saved indicator, and
    /// (optionally) the "Updated" call-to-action badge, laid out as a single
    /// left-aligned row:
    ///
    ///     [icon] Feed title · Apr 8                          [bookmark]
    ///     [icon] Feed title · Updated 3 hours ago            [bookmark]
    ///     [icon] Feed title · Apr 8  [Updated]               [bookmark]
    ///
    /// A middle dot (`·`) separates the feed name from the date or updated
    /// text. When `isRead && shouldShowUpdatedSuffix` is true the dot precedes
    /// the relative freshness string; otherwise it precedes the absolute publish
    /// date. The `isRead` gate prevents "Updated 3 hours ago" from appearing on
    /// articles the user has never opened — that label implies the user saw an
    /// earlier version, which is meaningless before first read.
    ///
    /// The orange "Updated" capsule badge is appended when `wasUpdated` is true,
    /// without an `isRead` gate. `upsertArticles` sets `wasUpdated = true` while
    /// the article is unread; `markRead` clears `wasUpdated` before setting
    /// `isRead = true`, so the badge is only ever visible on unread articles —
    /// suppressing it behind `isRead` would make it permanently invisible.
    @ViewBuilder
    private var metadataFooter: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            feedLabel
            Text("·")
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            if article.isRead && article.shouldShowUpdatedSuffix, let updated = article.updatedDate {
                Text("Updated \(updated, format: .relative(presentation: .named))")
            } else {
                Text(publishDateText)
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
            Spacer(minLength: 0)
            savedIndicator
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
                    feedURL: feed.feedURL,
                    feedImageURL: feed.feedImageURL,
                    iconURL: feed.iconURL,
                    iconBackgroundStyle: feed.iconBackgroundStyle,
                    iconService: iconService,
                    style: .inline
                )
                Text(feed.title)
            }
        } else {
            let _ = {
                Self.logger.fault("Article '\(self.article.articleID, privacy: .public)' has nil feed relationship")
                assertionFailure("Article '\(self.article.articleID)' has nil feed relationship")
            }()
            Color.clear
        }
    }

    /// Right-edge bookmark indicator, shown on every row whose article is
    /// currently saved. The orange fill matches the trailing swipe-action tint
    /// so the saved state reads consistently across all affordances.
    ///
    /// Always rendered and hidden via `.opacity(0)` on unsaved rows so the
    /// bookmark's footprint is reserved regardless of saved state. Conditional
    /// rendering would mostly work in the current `HStack` + `Spacer` layout
    /// (the `Spacer` absorbs the delta), but reserving the width makes the
    /// layout bit-identical across `isSaved` transitions and avoids a subtle
    /// reflow if the row ever runs tight on horizontal space and the `Spacer`
    /// collapses to its `minLength`.
    private var savedIndicator: some View {
        Image(systemName: "bookmark.fill")
            .foregroundStyle(.orange)
            .opacity(article.isSaved ? 1 : 0)
            .accessibilityLabel("Saved")
            .accessibilityHidden(!article.isSaved)
    }

    /// Absolute short date shown after the middle dot. Omits the year when
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
