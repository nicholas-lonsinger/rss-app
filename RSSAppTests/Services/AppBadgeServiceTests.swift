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
}
