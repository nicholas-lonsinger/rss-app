import Foundation
import SwiftData
@testable import RSSApp

enum SwiftDataTestHelpers {

    @MainActor
    static func makeTestContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(
            "test-\(UUID().uuidString)",
            isStoredInMemoryOnly: true
        )
        return try ModelContainer(
            for: PersistentFeed.self, PersistentArticle.self, PersistentArticleContent.self,
            configurations: configuration
        )
    }

    @MainActor
    static func makeTestPersistenceService() throws -> (SwiftDataFeedPersistenceService, ModelContainer) {
        let container = try makeTestContainer()
        let service = SwiftDataFeedPersistenceService(modelContext: container.mainContext)
        return (service, container)
    }
}
