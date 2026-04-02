import SwiftUI
import SwiftData
import os

@main
struct RSSAppApp: App {

    private static let logger = Logger(
        subsystem: "com.nicholas-lonsinger.rss-app",
        category: "RSSAppApp"
    )

    let modelContainer: ModelContainer

    init() {
        let isTestEnvironment = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        let schema = Schema([
            PersistentFeed.self,
            PersistentArticle.self,
            PersistentArticleContent.self,
        ])
        let configuration: ModelConfiguration
        if isTestEnvironment {
            configuration = ModelConfiguration(
                "app-host-test-store",
                schema: schema,
                isStoredInMemoryOnly: true
            )
        } else {
            configuration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false
            )
        }
        do {
            modelContainer = try ModelContainer(for: schema, configurations: configuration)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }

        Self.logger.notice("App launched, ModelContainer initialized")

        if !isTestEnvironment {
            UserDefaultsMigrationService.migrateIfNeeded(
                modelContext: modelContainer.mainContext
            )
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(modelContainer)
    }
}
