import os
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
    /// Drives `.task(id:)` so the icon load re-runs after the feed's icon URL is
    /// resolved and cached. The value itself isn't used for rendering.
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
                inlineFeedIconLogger.debug("No cached icon for feed \(feedID.uuidString, privacy: .public) — awaiting next refresh")
                iconImage = nil
                return
            }
            // RATIONALE: Calls FeedIconService.hasVisibleContent directly rather than through
            // the FeedIconResolving protocol because it is a pure static utility with no I/O
            // or state — protocol abstraction would add complexity with no testability benefit.
            let image = await Task.detached(priority: .userInitiated) { [iconService] () -> UIImage? in
                guard let img = UIImage(contentsOfFile: fileURL.path(percentEncoded: false)) else {
                    inlineFeedIconLogger.warning("Cached icon file unreadable for feed \(feedID.uuidString, privacy: .public) at \(fileURL.path, privacy: .public) — deleting")
                    iconService.deleteCachedIcon(for: feedID)
                    return nil
                }
                guard FeedIconService.hasVisibleContent(img) else {
                    inlineFeedIconLogger.warning("Cached icon for feed \(feedID.uuidString, privacy: .public) has no visible content — deleting")
                    iconService.deleteCachedIcon(for: feedID)
                    return nil
                }
                return img
            }.value
            iconImage = image
        }
    }
}

// RATIONALE: File-private module-level logger so it can be accessed from inside
// `Task.detached` closures without crossing the `View`'s `@MainActor` isolation,
// matching the pattern used by `downloadRetryLogger` in ThumbnailPrefetchService.
private let inlineFeedIconLogger = Logger(category: "InlineFeedIconView")
