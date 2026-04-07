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

    @Test("Returns false when UserDefaults has false")
    func explicitFalseReturnsFalse() {
        UserDefaults.standard.set(false, forKey: Self.badgeEnabledDefaultsKey)
        let service = AppBadgeService()
        #expect(service.badgeEnabled == false)
    }

    // MARK: - Setter persistence

    @Test("Setting badgeEnabled to true persists and reads back")
    func setTrueReadsBack() {
        let service = AppBadgeService()
        service.badgeEnabled = true
        #expect(service.badgeEnabled == true)
    }

    @Test("Setting badgeEnabled to false after true persists and reads back")
    func setFalseAfterTrueReadsBack() {
        let service = AppBadgeService()
        service.badgeEnabled = true
        service.badgeEnabled = false
        #expect(service.badgeEnabled == false)
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
    }

    @Test("Migrates legacy 'unread' badge mode to enabled")
    func migratesLegacyUnreadToEnabled() {
        // The legacy 3-mode key used values like "unread" for "show unread count"
        // and "total" for "show total count"; anything that is not literally "off"
        // should map to enabled = true.
        UserDefaults.standard.set("unread", forKey: Self.legacyBadgeModeKey)
        let service = AppBadgeService()
        #expect(service.badgeEnabled == true)
        #expect(UserDefaults.standard.string(forKey: Self.legacyBadgeModeKey) == nil)
    }

    @Test("Migrates legacy 'total' badge mode to enabled")
    func migratesLegacyTotalToEnabled() {
        UserDefaults.standard.set("total", forKey: Self.legacyBadgeModeKey)
        let service = AppBadgeService()
        #expect(service.badgeEnabled == true)
        #expect(UserDefaults.standard.string(forKey: Self.legacyBadgeModeKey) == nil)
    }

    @Test("Migrates unrecognized legacy badge mode to enabled")
    func migratesUnrecognizedLegacyModeToEnabled() {
        // Any non-"off" string — including unexpected values from future or
        // corrupted stores — should default to enabled = true rather than
        // silently falling back to disabled.
        UserDefaults.standard.set("someFutureMode", forKey: Self.legacyBadgeModeKey)
        let service = AppBadgeService()
        #expect(service.badgeEnabled == true)
        #expect(UserDefaults.standard.string(forKey: Self.legacyBadgeModeKey) == nil)
    }

    @Test("Migrates legacy empty string to enabled")
    func migratesLegacyEmptyStringToEnabled() {
        // Empty string is not "off", so per the current migration rule it maps
        // to enabled = true. This pins the existing behavior.
        UserDefaults.standard.set("", forKey: Self.legacyBadgeModeKey)
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

    @Test("Numeric legacy value is stringified and migrates to enabled")
    func numericLegacyValueMigratesToEnabled() {
        // UserDefaults.string(forKey:) coerces numeric values to their decimal
        // string representation, so an integer written under the legacy key
        // becomes a non-"off" string and maps to enabled = true. This pins the
        // observed behavior so any future change (e.g., switching to
        // `object(forKey:) as? String`) is caught by the test suite.
        UserDefaults.standard.set(42, forKey: Self.legacyBadgeModeKey)
        let service = AppBadgeService()

        #expect(service.badgeEnabled == true)
        #expect(UserDefaults.standard.string(forKey: Self.legacyBadgeModeKey) == nil)
    }

    @Test("New key 'true' takes precedence over legacy 'off'")
    func newKeyTrueOverridesLegacyOff() {
        UserDefaults.standard.set(true, forKey: Self.badgeEnabledDefaultsKey)
        UserDefaults.standard.set("off", forKey: Self.legacyBadgeModeKey)
        let service = AppBadgeService()
        #expect(service.badgeEnabled == true)
        // Legacy key is left untouched since migration is skipped.
        #expect(UserDefaults.standard.string(forKey: Self.legacyBadgeModeKey) == "off")
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

    @Test("Rapid back-to-back instantiation migrates exactly once")
    func rapidInstantiationMigratesOnce() {
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
