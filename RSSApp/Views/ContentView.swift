import SwiftUI
import SwiftData

struct ContentView: View {
    let persistence: FeedPersisting
    let refreshService: FeedRefreshService
    let feedIconService: FeedIconResolving

    var body: some View {
        HomeView(
            persistence: persistence,
            refreshService: refreshService,
            feedIconService: feedIconService
        )
    }
}

#Preview {
    let previewContainer = try! ModelContainer(
        for: PersistentFeed.self, PersistentArticle.self, PersistentArticleContent.self,
        PersistentFeedGroup.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let persistence = SwiftDataFeedPersistenceService(modelContext: previewContainer.mainContext)
    let feedIconService = FeedIconService()
    ContentView(
        persistence: persistence,
        refreshService: FeedRefreshService(
            persistence: persistence,
            feedIconService: feedIconService
        ),
        feedIconService: feedIconService
    )
    .modelContainer(previewContainer)
}
