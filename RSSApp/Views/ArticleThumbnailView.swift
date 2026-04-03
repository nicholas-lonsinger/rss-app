import SwiftUI

struct ArticleThumbnailView: View {

    let articleID: String
    // RATIONALE: thumbnailURL is not read directly — it exists so SwiftUI detects a property
    // change and re-evaluates the body when the thumbnail URL becomes available after parsing.
    let thumbnailURL: URL?
    let articleLink: URL?
    let thumbnailService: ArticleThumbnailCaching

    @State private var thumbnailImage: UIImage?

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

    private func loadThumbnail() async {
        // Try loading from cache first
        if let fileURL = thumbnailService.cachedThumbnailFileURL(for: articleID) {
            let image = await Task.detached(priority: .userInitiated) {
                UIImage(contentsOfFile: fileURL.path(percentEncoded: false))
            }.value
            thumbnailImage = image
            return
        }

        // Cache miss: resolve (direct URL → og:image fallback), cache, then load
        guard thumbnailURL != nil || articleLink != nil else {
            thumbnailImage = nil
            return
        }

        let cached = await thumbnailService.resolveAndCacheThumbnail(
            thumbnailURL: thumbnailURL,
            articleLink: articleLink,
            articleID: articleID
        )
        guard cached, let fileURL = thumbnailService.cachedThumbnailFileURL(for: articleID) else {
            thumbnailImage = nil
            return
        }

        let image = await Task.detached(priority: .userInitiated) {
            UIImage(contentsOfFile: fileURL.path(percentEncoded: false))
        }.value
        thumbnailImage = image
    }
}
