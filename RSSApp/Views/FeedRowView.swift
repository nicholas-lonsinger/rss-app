import SwiftUI

struct FeedRowView: View {
    let feed: PersistentFeed
    let unreadCount: Int
    let iconService: FeedIconResolving

    var body: some View {
        HStack(spacing: 10) {
            FeedIconView(
                feedID: feed.id,
                feedURL: feed.feedURL,
                feedImageURL: feed.feedImageURL,
                iconURL: feed.iconURL,
                iconBackgroundStyle: feed.iconBackgroundStyle,
                iconService: iconService
            )

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

            BadgeView(count: unreadCount)
        }
        .padding(.vertical, 4)
    }
}
