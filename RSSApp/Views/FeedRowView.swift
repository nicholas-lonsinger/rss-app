import SwiftUI

struct FeedRowView: View {
    let feed: PersistentFeed
    let unreadCount: Int
    let iconService: FeedIconResolving

    var body: some View {
        HStack(spacing: 10) {
            FeedIconView(feedID: feed.id, iconURL: feed.iconURL, iconService: iconService)

            VStack(alignment: .leading, spacing: 4) {
                Text(feed.title)
                    .font(.headline)
                    .lineLimit(1)
                if !feed.feedDescription.isEmpty {
                    Text(feed.feedDescription)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if let error = feed.lastFetchError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Spacer()

            if unreadCount > 0 {
                Text("\(unreadCount)")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.blue)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, 4)
    }
}
