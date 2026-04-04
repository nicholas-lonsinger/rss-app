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

    /// The Keychain account identifier for the Anthropic API key.
    static var apiKeyAccount: String { "anthropic-api-key" }

    /// Whether a non-empty API key is currently stored in the Keychain.
    ///
    /// Returns `false` when no key is stored. Throws when the Keychain read
    /// fails, allowing callers to distinguish "no key" from "error."
    func hasAPIKey() throws -> Bool {
        guard let key = try loadAPIKey() else { return false }
        return !key.isEmpty
    }

    /// Loads the stored API key, if any.
    ///
    /// Returns `nil` when no key is stored. Throws on Keychain read errors
    /// or data corruption so callers can show appropriate error messages.
    func loadAPIKey() throws -> String? {
        try load(for: Self.apiKeyAccount)
    }

    /// Saves the given API key to the Keychain.
    func saveAPIKey(_ value: String) throws {
        try save(value, for: Self.apiKeyAccount)
    }

    /// Deletes the stored API key from the Keychain.
    func deleteAPIKey() throws {
        try delete(for: Self.apiKeyAccount)
    }
}
