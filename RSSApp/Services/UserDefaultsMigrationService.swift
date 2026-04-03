import Foundation
import SwiftData
import os

@MainActor
struct UserDefaultsMigrationService {

    private static let logger = Logger(category: "UserDefaultsMigrationService")

    private static let migrationKey = "swiftdata_migration_complete_v1"

    static func migrateIfNeeded(
        modelContext: ModelContext,
        defaults: UserDefaults = .standard
    ) {
        guard !defaults.bool(forKey: migrationKey) else {
            logger.debug("SwiftData migration already complete, skipping")
            return
        }

        logger.notice("Starting UserDefaults → SwiftData migration")

        let legacyStorage = FeedStorageService(defaults: defaults)
        let feeds: [SubscribedFeed]
        do {
            feeds = try legacyStorage.loadFeeds()
        } catch {
            // Don't mark migration complete — retry on next launch in case a future
            // update can decode the data or the error is transient.
            logger.warning("Failed to load legacy feeds, will retry next launch: \(error, privacy: .public)")
            return
        }

        guard !feeds.isEmpty else {
            logger.debug("No legacy feeds to migrate")
            defaults.set(true, forKey: migrationKey)
            return
        }

        for subscribedFeed in feeds {
            let persistent = PersistentFeed(from: subscribedFeed)
            modelContext.insert(persistent)
        }

        do {
            try modelContext.save()
            defaults.removeObject(forKey: "subscribedFeeds")
            defaults.set(true, forKey: migrationKey)
            logger.notice("Migrated \(feeds.count, privacy: .public) feeds to SwiftData")
        } catch {
            logger.error("SwiftData migration save failed: \(error, privacy: .public)")
            // Don't set the flag — retry on next launch
        }
    }
}
