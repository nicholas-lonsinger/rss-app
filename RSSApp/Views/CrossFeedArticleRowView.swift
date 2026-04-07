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

                HStack(spacing: 4) {
                    if let feed = article.feed {
                        InlineFeedIconView(
                            feedID: feed.id,
                            iconURL: feed.iconURL,
                            iconService: iconService
                        )

                        Text(feed.title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
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

/// Compact inline feed icon sized to sit alongside `.caption`-sized text.
/// Loads from `FeedIconResolving`'s on-disk cache and renders nothing when no
/// cached icon is available, so rows without resolved icons collapse to text only.
private struct InlineFeedIconView: View {
    let feedID: UUID
    // RATIONALE: iconURL is not read directly — it exists so SwiftUI detects a property
    // change and re-evaluates the body when the icon becomes available after caching.
    let iconURL: URL?
    let iconService: FeedIconResolving

    @State private var iconImage: UIImage?

    private static let iconSize: CGFloat = 14
    private static let cornerRadius: CGFloat = 3

    var body: some View {
        Group {
            if let iconImage {
                Image(uiImage: iconImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: Self.iconSize, height: Self.iconSize)
                    .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius))
            }
        }
        .task(id: iconURL) {
            guard let fileURL = iconService.cachedIconFileURL(for: feedID) else {
                iconImage = nil
                return
            }
            // RATIONALE: Calls FeedIconService.hasVisibleContent directly rather than through
            // the FeedIconResolving protocol because it is a pure static utility with no I/O
            // or state — protocol abstraction would add complexity with no testability benefit.
            let image = await Task.detached(priority: .userInitiated) { [iconService] () -> UIImage? in
                guard let img = UIImage(contentsOfFile: fileURL.path(percentEncoded: false)),
                      FeedIconService.hasVisibleContent(img) else {
                    // Cached icon is corrupt or transparent — remove so next refresh retries
                    iconService.deleteCachedIcon(for: feedID)
                    return nil
                }
                return img
            }.value
            iconImage = image
        }
    }
}
