import SwiftUI

struct FeedRowView: View {
    let feed: SubscribedFeed

    var body: some View {
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
        .padding(.vertical, 4)
    }
}
