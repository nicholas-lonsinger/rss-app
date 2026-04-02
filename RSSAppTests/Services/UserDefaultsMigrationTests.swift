import Testing
import Foundation
import SwiftData
@testable import RSSApp

@Suite("UserDefaultsMigrationService Tests", .serialized)
struct UserDefaultsMigrationTests {

    private func makeDefaults() -> (UserDefaults, String) {
        let suiteName = "MigrationTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }

    @Test("migrateIfNeeded migrates feeds from UserDefaults to SwiftData")
    @MainActor
    func migrateFeeds() throws {
        let (defaults, _) = makeDefaults()
        let container = try SwiftDataTestHelpers.makeTestContainer()

        // Seed UserDefaults with legacy data
        let legacyFeeds = [
            TestFixtures.makeSubscribedFeed(title: "Feed A", url: URL(string: "https://a.com/feed")!),
            TestFixtures.makeSubscribedFeed(title: "Feed B", url: URL(string: "https://b.com/feed")!),
        ]
        let data = try JSONEncoder().encode(legacyFeeds)
        defaults.set(data, forKey: "subscribedFeeds")

        UserDefaultsMigrationService.migrateIfNeeded(
            modelContext: container.mainContext,
            defaults: defaults
        )

        let descriptor = FetchDescriptor<PersistentFeed>(sortBy: [SortDescriptor(\.title)])
        let migrated = try container.mainContext.fetch(descriptor)

        #expect(migrated.count == 2)
        #expect(migrated[0].title == "Feed A")
        #expect(migrated[1].title == "Feed B")
    }

    @Test("migrateIfNeeded clears UserDefaults after migration")
    @MainActor
    func clearsUserDefaults() throws {
        let (defaults, _) = makeDefaults()
        let container = try SwiftDataTestHelpers.makeTestContainer()

        let legacyFeeds = [TestFixtures.makeSubscribedFeed()]
        let data = try JSONEncoder().encode(legacyFeeds)
        defaults.set(data, forKey: "subscribedFeeds")

        UserDefaultsMigrationService.migrateIfNeeded(
            modelContext: container.mainContext,
            defaults: defaults
        )

        #expect(defaults.data(forKey: "subscribedFeeds") == nil)
    }

    @Test("migrateIfNeeded sets migration flag")
    @MainActor
    func setsMigrationFlag() throws {
        let (defaults, _) = makeDefaults()
        let container = try SwiftDataTestHelpers.makeTestContainer()

        UserDefaultsMigrationService.migrateIfNeeded(
            modelContext: container.mainContext,
            defaults: defaults
        )

        #expect(defaults.bool(forKey: "swiftdata_migration_complete_v1") == true)
    }

    @Test("migrateIfNeeded skips when migration flag already set")
    @MainActor
    func skipsWhenAlreadyMigrated() throws {
        let (defaults, _) = makeDefaults()
        let container = try SwiftDataTestHelpers.makeTestContainer()

        defaults.set(true, forKey: "swiftdata_migration_complete_v1")

        // Seed data that should NOT be migrated
        let legacyFeeds = [TestFixtures.makeSubscribedFeed()]
        let data = try JSONEncoder().encode(legacyFeeds)
        defaults.set(data, forKey: "subscribedFeeds")

        UserDefaultsMigrationService.migrateIfNeeded(
            modelContext: container.mainContext,
            defaults: defaults
        )

        let descriptor = FetchDescriptor<PersistentFeed>()
        #expect(try container.mainContext.fetchCount(descriptor) == 0)
    }

    @Test("migrateIfNeeded handles empty UserDefaults gracefully")
    @MainActor
    func handlesEmptyDefaults() throws {
        let (defaults, _) = makeDefaults()
        let container = try SwiftDataTestHelpers.makeTestContainer()

        UserDefaultsMigrationService.migrateIfNeeded(
            modelContext: container.mainContext,
            defaults: defaults
        )

        let descriptor = FetchDescriptor<PersistentFeed>()
        #expect(try container.mainContext.fetchCount(descriptor) == 0)
        #expect(defaults.bool(forKey: "swiftdata_migration_complete_v1") == true)
    }

    @Test("migrateIfNeeded preserves feed IDs during migration")
    @MainActor
    func preservesFeedIDs() throws {
        let (defaults, _) = makeDefaults()
        let container = try SwiftDataTestHelpers.makeTestContainer()

        let feedID = UUID()
        let legacyFeeds = [TestFixtures.makeSubscribedFeed(id: feedID)]
        let data = try JSONEncoder().encode(legacyFeeds)
        defaults.set(data, forKey: "subscribedFeeds")

        UserDefaultsMigrationService.migrateIfNeeded(
            modelContext: container.mainContext,
            defaults: defaults
        )

        let descriptor = FetchDescriptor<PersistentFeed>()
        let migrated = try container.mainContext.fetch(descriptor)

        #expect(migrated[0].id == feedID)
    }
}
