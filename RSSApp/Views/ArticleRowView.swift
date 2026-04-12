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

    /// Bottom metadata block — feed source, publish date, saved indicator, and
    /// (optionally) the "Updated" suffix and call-to-action badge, laid out as:
    ///
    ///     [icon] Feed title        Apr 8              [bookmark]
    ///     Updated 9 hours ago
    ///
    /// The left column is a `VStack` holding the feed label and (when present)
    /// the updated line — stacking the relative freshness directly under the
    /// feed source so the right side of the row stays compact and the feed
    /// identity + freshness read as a single left-anchored block. The outer
    /// `HStack(alignment: .firstTextBaseline)` baseline-aligns the feed name
    /// with the publish date so they sit on the same line instead of the feed
    /// name vertically centering against the two-row left column.
    ///
    /// This was previously a SwiftUI `Grid` for explicit column alignment, but
    /// `Grid`'s column-sizing algorithm shrinks non-flex columns to the width
    /// of their longest unbreakable token (longest word) rather than their
    /// natural single-line width. That forced mid-word wraps even with plenty
    /// of horizontal space — e.g. "AWS Architecture Blog" broke at "AWS
    /// Architecture / Blog", and "Updated 9 hours ago" broke at "Updated 9 /
    /// hours ago". The HStack version lets each child size to its natural
    /// width and the trailing `Spacer` absorbs the slack, so nothing wraps
    /// until the row actually runs out of room.
    @ViewBuilder
    private var metadataFooter: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                feedLabel
                if article.shouldShowUpdatedSuffix || article.wasUpdated {
                    updatedLine
                }
            }
            Text(publishDateText)
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
