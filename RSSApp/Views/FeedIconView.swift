import SwiftUI

struct FeedIconView: View {

    let feedID: UUID
    // RATIONALE: iconURL is not read directly — it exists so SwiftUI detects a property
    // change and re-evaluates the body when the icon becomes available after caching.
    let iconURL: URL?
    let iconService: FeedIconResolving

    @State private var iconImage: UIImage?

    private static let iconSize: CGFloat = 32
    private static let cornerRadius: CGFloat = 6

    var body: some View {
        ZStack {
            if let iconImage {
                Image(uiImage: iconImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius))
            } else {
                RoundedRectangle(cornerRadius: Self.cornerRadius)
                    .fill(Color(.tertiarySystemFill))
                    .overlay {
                        Image(systemName: "globe")
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .frame(width: Self.iconSize, height: Self.iconSize)
        .task(id: iconURL) {
            guard let fileURL = iconService.cachedIconFileURL(for: feedID) else {
                iconImage = nil
                return
            }
            let image = await Task.detached(priority: .userInitiated) {
                UIImage(contentsOfFile: fileURL.path(percentEncoded: false))
            }.value
            iconImage = image
        }
    }
}
