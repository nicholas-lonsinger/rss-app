import Foundation
import Testing
@testable import RSSApp

@Suite("KeychainService")
struct KeychainServiceTests {

    // Each test uses a unique account derived from a UUID so tests never share Keychain state.
    private func makeService() -> (KeychainService, String) {
        let account = "test-\(UUID().uuidString)"
        return (KeychainService(service: "com.nicholas-lonsinger.rss-app.tests"), account)
    }

    @Test("load returns nil when no value has been saved")
    func loadWhenEmpty() {
        let (service, account) = makeService()
        #expect(service.load(for: account) == nil)
    }

    @Test("save and load roundtrip")
    func saveAndLoad() throws {
        let (service, account) = makeService()
        defer { service.delete(for: account) }
        try service.save("sk-test-key", for: account)
        #expect(service.load(for: account) == "sk-test-key")
    }

    @Test("delete clears a saved value")
    func deleteClears() throws {
        let (service, account) = makeService()
        try service.save("sk-test-key", for: account)
        service.delete(for: account)
        #expect(service.load(for: account) == nil)
    }

    @Test("save overwrites an existing value")
    func saveOverwrites() throws {
        let (service, account) = makeService()
        defer { service.delete(for: account) }
        try service.save("first-value", for: account)
        try service.save("second-value", for: account)
        #expect(service.load(for: account) == "second-value")
    }
}

// MARK: - API Key Convenience Extension

@Suite("KeychainServicing API Key Convenience")
struct KeychainAPIKeyConvenienceTests {

    @Test("hasAPIKey returns false when no key is stored")
    func hasAPIKeyWhenEmpty() {
        let mock = MockKeychainService()
        #expect(mock.hasAPIKey == false)
    }

    @Test("hasAPIKey returns true after saving a key")
    func hasAPIKeyAfterSave() throws {
        let mock = MockKeychainService()
        try mock.saveAPIKey("sk-test")
        #expect(mock.hasAPIKey == true)
    }

    @Test("loadAPIKey returns nil when no key is stored")
    func loadAPIKeyWhenEmpty() {
        let mock = MockKeychainService()
        #expect(mock.loadAPIKey() == nil)
    }

    @Test("saveAPIKey and loadAPIKey roundtrip")
    func saveAndLoadAPIKey() throws {
        let mock = MockKeychainService()
        try mock.saveAPIKey("sk-my-key")
        #expect(mock.loadAPIKey() == "sk-my-key")
    }

    @Test("deleteAPIKey clears a saved key")
    func deleteAPIKey() throws {
        let mock = MockKeychainService()
        try mock.saveAPIKey("sk-my-key")
        mock.deleteAPIKey()
        #expect(mock.hasAPIKey == false)
        #expect(mock.loadAPIKey() == nil)
    }

    @Test("apiKeyAccount returns the expected account identifier")
    func apiKeyAccountValue() {
        #expect(MockKeychainService.apiKeyAccount == "anthropic-api-key")
        #expect(KeychainService.apiKeyAccount == "anthropic-api-key")
    }
}
