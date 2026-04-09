import SwiftUI
import SwiftData

struct ContentView: View {
    let persistence: FeedPersisting
    let refreshService: FeedRefreshService

    var body: some View {
        HomeView(persistence: persistence, refreshService: refreshService)
    }
}

#Preview {
    let previewContainer = try! ModelContainer(
        for: PersistentFeed.self, PersistentArticle.self, PersistentArticleContent.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let persistence = SwiftDataFeedPersistenceService(modelContext: previewContainer.mainContext)
    ContentView(
        persistence: persistence,
        refreshService: FeedRefreshService(persistence: persistence)
    )
    .modelContainer(previewContainer)
}
