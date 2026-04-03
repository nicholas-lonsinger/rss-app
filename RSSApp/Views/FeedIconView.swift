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
            RoundedRectangle(cornerRadius: Self.cornerRadius)
                .fill(Color(.tertiarySystemFill))

            if let iconImage {
                Image(uiImage: iconImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius))
            } else {
                Image(systemName: "globe")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: Self.iconSize, height: Self.iconSize)
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
