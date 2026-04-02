import SwiftUI

struct FeedIconView: View {

    let feedID: UUID

    private static let iconSize: CGFloat = 32
    private static let cornerRadius: CGFloat = 6

    var body: some View {
        if let fileURL = FeedIconService().cachedIconFileURL(for: feedID),
           let uiImage = UIImage(contentsOfFile: fileURL.path(percentEncoded: false)) {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: Self.iconSize, height: Self.iconSize)
                .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius))
        } else {
            Image(systemName: "globe")
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: Self.iconSize, height: Self.iconSize)
        }
    }
}
