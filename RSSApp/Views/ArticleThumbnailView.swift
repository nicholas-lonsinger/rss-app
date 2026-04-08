import os
import SwiftUI

struct ArticleThumbnailView: View {

    let articleID: String
    // RATIONALE: thumbnailURL is passed to .task(id:) so SwiftUI re-runs the thumbnail
    // load when the URL changes (e.g., after parsing completes), and is forwarded to the
    // service for resolution. Without this property, the view would not react to late-arriving URLs.
    let thumbnailURL: URL?
    let articleLink: URL?
    let thumbnailService: ArticleThumbnailCaching

    @State private var thumbnailImage: UIImage?

    private static let logger = Logger(category: "ArticleThumbnailView")
    private static let thumbnailSize: CGFloat = 60
    private static let cornerRadius: CGFloat = 8

    var body: some View {
        ZStack {
            if let thumbnailImage {
                Image(uiImage: thumbnailImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius))
            } else {
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: Self.thumbnailSize, height: Self.thumbnailSize)
        .task(id: thumbnailURL) {
            await loadThumbnail()
        }
    }

    // RATIONALE: Thumbnails are primarily resolved during feed refresh via
    // ThumbnailPrefetchService. This view reads from disk cache first. On-demand
    // resolution is retained as a fallback for articles that predate the eager
    // prefetch feature or whose prefetch is still in progress.
    private func loadThumbnail() async {
        if let fileURL = thumbnailService.cachedThumbnailFileURL(for: articleID) {
            let image = await Task.detached(priority: .userInitiated) {
                UIImage(contentsOfFile: fileURL.path(percentEncoded: false))
            }.value
            if let image {
                thumbnailImage = image
                return
            }
            // Corrupt cache entry — purge it and fall through to resolution
            Self.logger.warning("Cached thumbnail file unreadable for article \(articleID, privacy: .public), purging")
            thumbnailService.deleteCachedThumbnail(for: articleID)
        }

        guard thumbnailURL != nil || articleLink != nil else {
            thumbnailImage = nil
            return
        }

        // RATIONALE: `resolveAndCacheThumbnail` is `throws(CancellationError)`, so the
        // unqualified `catch` below only ever receives a CancellationError and no
        // `catch { assertionFailure(...) }` safety net is needed. A `catch is
        // CancellationError` pattern would be flagged as always-true by Swift 6.
        let result: ThumbnailCacheResult
        do {
            result = try await thumbnailService.resolveAndCacheThumbnail(
                thumbnailURL: thumbnailURL,
                articleLink: articleLink,
                articleID: articleID
            )
        } catch {
            // View task was cancelled (e.g., row scrolled off-screen) — bail out quietly.
            return
        }
        guard result == .cached, let fileURL = thumbnailService.cachedThumbnailFileURL(for: articleID) else {
            thumbnailImage = nil
            return
        }

        let image = await Task.detached(priority: .userInitiated) {
            UIImage(contentsOfFile: fileURL.path(percentEncoded: false))
        }.value
        if image == nil {
            Self.logger.fault("Thumbnail cached successfully but file unreadable for article \(articleID, privacy: .public)")
            assertionFailure("Thumbnail cached successfully but file unreadable for article: \(articleID)")
        }
        thumbnailImage = image
    }
}
