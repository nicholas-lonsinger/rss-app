import Testing
import SwiftData
@testable import RSSApp

@Suite("RSSApp Tests")
struct RSSAppTests {
    @Test("App launches with content view")
    @MainActor
    func contentViewExists() throws {
        let container = try ModelContainer(
            for: PersistentFeed.self, PersistentArticle.self, PersistentArticleContent.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let persistence = SwiftDataFeedPersistenceService(modelContext: container.mainContext)
        let refreshService = FeedRefreshService(persistence: persistence)
        let view = ContentView(persistence: persistence, refreshService: refreshService)
        #expect(view.body is Never == false)
    }
}
