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

                ArticleRowDateLine(article: article)
            }
        }
        .padding(.vertical, 4)
    }

}

/// Date line for article rows. Shows the original publication time, an "Updated [date]"
/// suffix when the publisher has revised the article (independent of the user's read
/// state), and an orange "Updated" badge call-to-action when the row carries an
/// unread update bump (`wasUpdated == true`).
///
/// Two distinct UI signals here, intentionally:
/// - The "Updated [date]" text is *informational* — it always appears for articles
///   that have an updated date, so users can see "this article was last touched 3
///   days ago" even after they've read the latest version.
/// - The orange badge is a *call to action* — it only appears when `wasUpdated == true`,
///   meaning the article has new content the user hasn't read yet. It clears when
///   `markArticleRead(_:isRead: true)` fires (issue #74).
struct ArticleRowDateLine: View {
    let article: PersistentArticle

    var body: some View {
        HStack(spacing: 6) {
            // Original publication time. Uses `displayedPublishedDate` (not `sortDate`)
            // so the label remains stable when `upsertArticles` bumps `sortDate` on
            // update detection — see the RATIONALE on `PersistentArticle.sortDate`
            // for why these are now distinct.
            Text(article.displayedPublishedDate, style: .relative)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let updated = article.updatedDate,
               abs(updated.timeIntervalSince(article.displayedPublishedDate)) > 1 {
                Text("\u{00B7}")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Updated \(updated, style: .relative)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
