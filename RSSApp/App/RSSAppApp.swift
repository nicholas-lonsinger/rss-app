import SwiftUI
import SwiftData
import os

@main
struct RSSAppApp: App {

    private static let logger = Logger(category: "RSSAppApp")

    let modelContainer: ModelContainer
    private let persistence: FeedPersisting
    private let refreshService: FeedRefreshService
    private let backgroundRefreshCoordinator: BackgroundRefreshCoordinator

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

        if !isTestEnvironment {
            UserDefaultsMigrationService.migrateIfNeeded(
                modelContext: modelContainer.mainContext
            )
        }

        // Build the shared persistence + refresh service stack here so the
        // background task coordinator and the SwiftUI view tree reference the
        // same instances. A single process-wide FeedRefreshService is the
        // coordination point that prevents the foreground pull-to-refresh
        // and a concurrent BGTask launch from running the refresh loop twice
        // against the same ModelContext.
        let persistence = SwiftDataFeedPersistenceService(modelContext: modelContainer.mainContext)
        let refreshService = FeedRefreshService(persistence: persistence)
        self.persistence = persistence
        self.refreshService = refreshService
        self.backgroundRefreshCoordinator = BackgroundRefreshCoordinator(refreshService: refreshService)

        // BGTaskScheduler.register(...) must be called before
        // didFinishLaunchingWithOptions returns. In a SwiftUI @main App struct,
        // init() is that window — any later hook is too late and `submit` will
        // reject unknown identifiers. Registration is skipped in the test
        // environment where BGTaskScheduler is not available and the app host
        // launches without the Background Modes capability.
        if !isTestEnvironment {
            BackgroundRefreshScheduler.registerLaunchHandlers(
                coordinator: backgroundRefreshCoordinator
            )
            // Seed the first scheduled run so the user doesn't wait a full
            // interval after launch for the first background refresh window.
            BackgroundRefreshScheduler.scheduleNextRefresh()
        }

        Self.logger.notice("App initialization complete")
    }

    var body: some Scene {
        WindowGroup {
            ContentView(persistence: persistence, refreshService: refreshService)
        }
        .modelContainer(modelContainer)
    }
}
