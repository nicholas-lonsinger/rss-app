import SwiftUI

/// Article row for cross-feed lists (All Articles, Unread Articles, Saved Articles).
/// Includes the feed name (with inline icon) as a label so the user can identify the source.
struct CrossFeedArticleRowView: View {
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

                    // Display the clamped `sortDate` rather than the raw `publishedDate` so
                    // future-dated scheduled posts (e.g., the Cloudflare blog) render as
                    // "just now" instead of a misleading "in 3 hours" — see
                    // `PersistentArticle.sortDate` for the rationale. `sortDate` is
                    // non-optional, so no `if let` guard is needed.
                    Text(article.sortDate, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 2)
            }
        }
    }
}
