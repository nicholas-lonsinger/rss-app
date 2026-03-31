import SwiftUI

struct ArticleDetailView: View {
    let article: Article

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(article.title)
                    .font(.title2)
                    .fontWeight(.semibold)

                if let date = article.publishedDate {
                    Text(date, format: .dateTime.month().day().year().hour().minute())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Divider()

                Text(HTMLUtilities.stripHTML(article.articleDescription))
                    .font(.body)
            }
            .padding()
        }
        .navigationTitle("Article")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let link = article.link {
                ToolbarItem(placement: .topBarTrailing) {
                    Link(destination: link) {
                        Image(systemName: "safari")
                    }
                    .accessibilityLabel("Open in Safari")
                }
            }
        }
    }
}
