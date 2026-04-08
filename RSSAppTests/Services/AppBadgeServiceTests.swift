import Testing
import Foundation
@testable import RSSApp

@Suite("AppBadgeService Tests", .serialized)
@MainActor
struct AppBadgeServiceTests {

    private static let badgeEnabledDefaultsKey = "appBadgeEnabled"
    private static let legacyBadgeModeKey = "appBadgeMode"

    init() {
        // Clean slate for each test
        UserDefaults.standard.removeObject(forKey: Self.badgeEnabledDefaultsKey)
        UserDefaults.standard.removeObject(forKey: Self.legacyBadgeModeKey)
    }

    // MARK: - Default value

    @Test("Default value is false (badge off) when key has never been set")
    func defaultIsFalse() {
        let service = AppBadgeService()
        #expect(service.badgeEnabled == false)
    }

    // MARK: - Explicit values

    @Test("Returns true when UserDefaults has true")
    func explicitTrueReturnsTrue() {
        UserDefaults.standard.set(true, forKey: Self.badgeEnabledDefaultsKey)
        let service = AppBadgeService()
        #expect(service.badgeEnabled == true)
    }

    // MARK: - Setter persistence

    @Test("Setting badgeEnabled to true persists and reads back")
    func setTrueReadsBack() {
        let service = AppBadgeService()
        service.badgeEnabled = true
        #expect(service.badgeEnabled == true)
    }

    // MARK: - Legacy migration

    @Test("Migrates legacy 'on' badge mode to enabled")
    func migratesLegacyOnToEnabled() {
        UserDefaults.standard.set("on", forKey: Self.legacyBadgeModeKey)
        let service = AppBadgeService()
        #expect(service.badgeEnabled == true)
        #expect(UserDefaults.standard.string(forKey: Self.legacyBadgeModeKey) == nil)
    }

    @Test("Migrates legacy 'off' badge mode to disabled")
    func migratesLegacyOffToDisabled() {
        UserDefaults.standard.set("off", forKey: Self.legacyBadgeModeKey)
        let service = AppBadgeService()
        #expect(service.badgeEnabled == false)
        #expect(UserDefaults.standard.string(forKey: Self.legacyBadgeModeKey) == nil)
    }

    @Test("Does not migrate when new key already exists")
    func noMigrationWhenNewKeyExists() {
        UserDefaults.standard.set(false, forKey: Self.badgeEnabledDefaultsKey)
        UserDefaults.standard.set("on", forKey: Self.legacyBadgeModeKey)
        let service = AppBadgeService()
        // New key takes precedence — legacy key is not migrated
        #expect(service.badgeEnabled == false)
        // Legacy key must be left untouched when the new key already exists.
        #expect(UserDefaults.standard.string(forKey: Self.legacyBadgeModeKey) == "on")
    }

    @Test("Migrates legacy non-'off' badge mode (representative: 'unread') to enabled")
    func migratesLegacyNonOffModeToEnabled() {
        // The legacy 3-mode key used values like "unread" for "show unread count"
        // and "total" for "show total count"; anything that is not literally "off"
        // — including unexpected values from future or corrupted stores and empty
        // strings — should default to enabled = true rather than silently falling
        // back to disabled. All non-"off" values share the same code path; this
        // test covers the representative "unread" case.
        UserDefaults.standard.set("unread", forKey: Self.legacyBadgeModeKey)
        let service = AppBadgeService()
        #expect(service.badgeEnabled == true)
        #expect(UserDefaults.standard.string(forKey: Self.legacyBadgeModeKey) == nil)
    }

    // MARK: - No-migration cases (neither key or non-string legacy)

    @Test("No migration when neither legacy nor new key exists — default is false and key stays unset")
    func noMigrationWhenNeitherKeyExists() {
        // Clean slate established by init(). Creating the service must NOT
        // write a value for the new key (so the getter's "never set" default
        // path is preserved), and must not invent a legacy key.
        #expect(UserDefaults.standard.object(forKey: Self.badgeEnabledDefaultsKey) == nil)
        #expect(UserDefaults.standard.object(forKey: Self.legacyBadgeModeKey) == nil)

        let service = AppBadgeService()

        #expect(service.badgeEnabled == false)
        // Getter should still report "never set" — the new key must remain absent
        // so the default-false path is exercised rather than a written false value.
        #expect(UserDefaults.standard.object(forKey: Self.badgeEnabledDefaultsKey) == nil)
        #expect(UserDefaults.standard.object(forKey: Self.legacyBadgeModeKey) == nil)
    }

    // MARK: - Repeated initialization safety

    @Test("Repeated service initialization after migration is idempotent")
    func repeatedInitAfterMigrationIsIdempotent() {
        UserDefaults.standard.set("on", forKey: Self.legacyBadgeModeKey)

        // First init performs the migration.
        let first = AppBadgeService()
        #expect(first.badgeEnabled == true)
        #expect(UserDefaults.standard.string(forKey: Self.legacyBadgeModeKey) == nil)

        // Any subsequent init must be a no-op: the new key is preserved,
        // the legacy key stays absent, and the reported value is unchanged.
        let second = AppBadgeService()
        let third = AppBadgeService()
        #expect(second.badgeEnabled == true)
        #expect(third.badgeEnabled == true)
        #expect(UserDefaults.standard.string(forKey: Self.legacyBadgeModeKey) == nil)
        #expect(UserDefaults.standard.bool(forKey: Self.badgeEnabledDefaultsKey) == true)
    }

    @Test("Repeated service initialization does not overwrite user-modified value post-migration")
    func repeatedInitDoesNotOverwritePostMigrationChange() {
        // Simulate: legacy 'on' is migrated, the user then toggles the badge
        // off, then the service is re-instantiated (e.g., view rebuild).
        // The re-init must NOT re-run migration and must NOT revert the user's choice.
        UserDefaults.standard.set("on", forKey: Self.legacyBadgeModeKey)

        let first = AppBadgeService()
        #expect(first.badgeEnabled == true)

        first.badgeEnabled = false

        let second = AppBadgeService()
        #expect(second.badgeEnabled == false)
        #expect(UserDefaults.standard.string(forKey: Self.legacyBadgeModeKey) == nil)
    }

    @Test("Rapid back-to-back instantiation converges to migrated state")
    func rapidInstantiationConvergesToMigratedState() {
        UserDefaults.standard.set("unread", forKey: Self.legacyBadgeModeKey)

        // Creating many services in rapid succession on the main actor must
        // converge to a single migration: the new key is set once, the legacy
        // key is removed once, and every instance reports the same value.
        let services = (0..<10).map { _ in AppBadgeService() }
        for service in services {
            #expect(service.badgeEnabled == true)
        }
        #expect(UserDefaults.standard.object(forKey: Self.badgeEnabledDefaultsKey) != nil)
        #expect(UserDefaults.standard.bool(forKey: Self.badgeEnabledDefaultsKey) == true)
        #expect(UserDefaults.standard.string(forKey: Self.legacyBadgeModeKey) == nil)
    }
}
