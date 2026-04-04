import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        HomeView(
            persistence: SwiftDataFeedPersistenceService(modelContext: modelContext)
        )
    }
}

#Preview {
    ContentView()
        .modelContainer(
            for: [PersistentFeed.self, PersistentArticle.self, PersistentArticleContent.self],
            inMemory: true
        )
}
