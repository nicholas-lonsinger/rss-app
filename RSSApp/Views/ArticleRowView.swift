import SwiftUI

struct ArticleRowView: View {
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

                // Display the clamped `sortDate` rather than the raw `publishedDate` so
                // future-dated scheduled posts (e.g., the Cloudflare blog) render as
                // "just now" instead of a misleading "in 3 hours" — see
                // `PersistentArticle.sortDate` for the rationale.
                Text(article.sortDate, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

}
