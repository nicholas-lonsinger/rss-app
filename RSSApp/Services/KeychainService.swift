import Foundation
import os
import Security

protocol KeychainServicing: Sendable {
    func save(_ value: String, for account: String) throws
    func load(for account: String) throws -> String?
    func delete(for account: String) throws
}

enum KeychainError: Error, Sendable {
    case encodingFailed
    case saveFailed(OSStatus)
    case loadFailed(OSStatus)
    case dataCorrupted
    case deleteFailed(OSStatus)
}

struct KeychainService: KeychainServicing {

    private static let logger = Logger(category: "KeychainService")

    let service: String

    init(service: String = "com.nicholas-lonsinger.rss-app") {
        self.service = service
    }

    func save(_ value: String, for account: String) throws {
        guard let data = value.data(using: .utf8) else {
            Self.logger.error("Failed to encode value for account '\(account, privacy: .public)'")
            throw KeychainError.encodingFailed
        }

        try delete(for: account)

        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecValueData: data
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            Self.logger.error("Keychain save failed for account '\(account, privacy: .public)': \(status, privacy: .public)")
            throw KeychainError.saveFailed(status)
        }
        Self.logger.notice("Keychain value saved for account '\(account, privacy: .public)'")
    }

    func load(for account: String) throws -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            Self.logger.error(
                "Keychain load failed for account '\(account, privacy: .public)': OSStatus \(status, privacy: .public)"
            )
            throw KeychainError.loadFailed(status)
        }

        guard let data = result as? Data else {
            Self.logger.fault(
                "Keychain returned non-Data result for account '\(account, privacy: .public)' despite errSecSuccess"
            )
            assertionFailure("Keychain returned non-Data result for account '\(account)'")
            throw KeychainError.dataCorrupted
        }

        guard let value = String(data: data, encoding: .utf8) else {
            Self.logger.fault(
                "Keychain data is not valid UTF-8 for account '\(account, privacy: .public)'"
            )
            assertionFailure("Keychain data is not valid UTF-8 for account '\(account)'")
            throw KeychainError.dataCorrupted
        }

        return value
    }

    func delete(for account: String) throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status == errSecSuccess {
            Self.logger.notice("Keychain value deleted for account '\(account, privacy: .public)'")
        } else if status == errSecItemNotFound {
            Self.logger.debug("Keychain delete skipped for account '\(account, privacy: .public)': no existing value")
        } else {
            Self.logger.error("Keychain delete failed for account '\(account, privacy: .public)': \(status, privacy: .public)")
            throw KeychainError.deleteFailed(status)
        }
    }
}

// MARK: - API Key Convenience

extension KeychainServicing {

    // MARK: Per-provider methods

    /// Whether a non-empty API key is stored for the given provider.
    func hasAPIKey(for provider: AIProvider) throws -> Bool {
        guard let key = try loadAPIKey(for: provider) else { return false }
        return !key.isEmpty
    }

    /// Loads the stored API key for the given provider, if any.
    func loadAPIKey(for provider: AIProvider) throws -> String? {
        try load(for: provider.keychainAccount)
    }

    /// Saves the given API key for the specified provider.
    func saveAPIKey(_ value: String, for provider: AIProvider) throws {
        try save(value, for: provider.keychainAccount)
    }

    /// Deletes the stored API key for the specified provider.
    func deleteAPIKey(for provider: AIProvider) throws {
        try delete(for: provider.keychainAccount)
    }

    // MARK: Active provider convenience

    /// Whether the currently active provider has a non-empty API key stored.
    func hasActiveAPIKey() throws -> Bool {
        try hasAPIKey(for: AIProvider.active)
    }

    // MARK: Legacy single-provider methods (Claude / Anthropic)
    //
    // These delegate to the provider-aware methods using the Claude provider so
    // any callers that have not yet been updated continue to work unchanged.

    /// The Keychain account identifier for the Anthropic API key.
    static var apiKeyAccount: String { AIProvider.claude.keychainAccount }

    /// Whether a non-empty Anthropic API key is currently stored in the Keychain.
    func hasAPIKey() throws -> Bool {
        try hasAPIKey(for: .claude)
    }

    /// Loads the stored Anthropic API key, if any.
    func loadAPIKey() throws -> String? {
        try loadAPIKey(for: .claude)
    }

    /// Saves the given Anthropic API key to the Keychain.
    func saveAPIKey(_ value: String) throws {
        try saveAPIKey(value, for: .claude)
    }

    /// Deletes the stored Anthropic API key from the Keychain.
    func deleteAPIKey() throws {
        try deleteAPIKey(for: .claude)
    }
}
