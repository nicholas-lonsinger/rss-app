import SwiftUI

/// Article row for cross-feed lists (All Articles, Unread Articles).
/// Includes the feed name as a label so the user can identify the source.
struct CrossFeedArticleRowView: View {
    let article: PersistentArticle
    let thumbnailService: ArticleThumbnailCaching

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

                HStack(spacing: 4) {
                    if let feedTitle = article.feed?.title {
                        Text(feedTitle)
                            .font(.caption)
                            .foregroundStyle(Color.accentColor)
                    }

                    if article.feed?.title != nil, article.publishedDate != nil {
                        Text("\u{00B7}")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let date = article.publishedDate {
                        Text(date, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}
