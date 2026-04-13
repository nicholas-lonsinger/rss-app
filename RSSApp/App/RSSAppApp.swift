import BackgroundTasks
import SwiftUI
import SwiftData
import os

@main
struct RSSAppApp: App {

    private static let logger = Logger(category: "RSSAppApp")

    let modelContainer: ModelContainer
    private let persistence: FeedPersisting
    private let feedIconService: FeedIconResolving
    private let refreshService: FeedRefreshService
    private let backgroundRefreshCoordinator: BackgroundRefreshCoordinator

    init() {
        let isTestEnvironment = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        let schema = Schema([
            PersistentFeed.self,
            PersistentArticle.self,
            PersistentArticleContent.self,
            PersistentFeedGroup.self,
            PersistentFeedGroupMembership.self,
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
            AIProvider.migrateIfNeeded(keychain: KeychainService())
        }

        // Build the shared persistence + icon service + network monitor +
        // refresh service stack here so the background task coordinator and
        // the SwiftUI view tree reference the same instances. A single
        // process-wide FeedRefreshService is the coordination point that
        // prevents the foreground pull-to-refresh and a concurrent BGTask
        // launch from running the refresh loop twice against the same
        // ModelContext. The shared FeedIconService is passed to both the
        // refresh service (which writes new icons during refresh) and the
        // view models (which read cached icons for display) so both sides
        // see the same cache.
        //
        // NetworkMonitorService is constructed once and shared between
        // FeedRefreshService (image-download WiFi gate) and
        // BackgroundRefreshCoordinator (feed XML WiFi gate) so both gates
        // read from the same live NWPathMonitor.
        let persistence = SwiftDataFeedPersistenceService(modelContext: modelContainer.mainContext)
        let feedIconService = FeedIconService()
        let networkMonitor = NetworkMonitorService()
        let refreshService = FeedRefreshService(
            persistence: persistence,
            feedIconService: feedIconService,
            networkMonitor: networkMonitor
        )
        self.persistence = persistence
        self.feedIconService = feedIconService
        self.refreshService = refreshService
        self.backgroundRefreshCoordinator = BackgroundRefreshCoordinator(
            refreshService: refreshService,
            networkMonitor: networkMonitor
        )

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
            // A submit failure at launch is logged and swallowed — there is
            // no UI context to surface an alert, and the next user-initiated
            // setting change will retry via BackgroundRefreshSettingsView
            // (which does surface failures).
            do {
                try BackgroundRefreshScheduler.scheduleNextRefresh()
            } catch let error as BGTaskScheduler.Error where error.code == .unavailable {
                // .unavailable is expected on Simulator and when Background App
                // Refresh is disabled in Settings. Log at .debug — not a bug.
                Self.logger.debug("Background refresh unavailable at launch (Simulator or Background App Refresh disabled): \(error, privacy: .public)")
            } catch {
                Self.logger.error("Failed to seed background refresh at launch: \(error, privacy: .public)")
            }
        }

        Self.logger.notice("App initialization complete")
    }

    var body: some Scene {
        WindowGroup {
            ContentView(
                persistence: persistence,
                refreshService: refreshService,
                feedIconService: feedIconService
            )
        }
        .modelContainer(modelContainer)
    }
}
