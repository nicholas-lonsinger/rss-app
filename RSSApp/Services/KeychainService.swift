import Foundation
import os
import Security

protocol KeychainServicing: Sendable {
    func save(_ value: String, for account: String) throws
    func load(for account: String) -> String?
    func delete(for account: String)
}

enum KeychainError: Error, Sendable {
    case encodingFailed
    case saveFailed(OSStatus)
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

        delete(for: account)

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

    func load(for account: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    func delete(for account: String) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status == errSecSuccess {
            Self.logger.notice("Keychain value deleted for account '\(account, privacy: .public)'")
        } else if status != errSecItemNotFound {
            Self.logger.warning("Keychain delete failed for account '\(account, privacy: .public)': \(status, privacy: .public)")
        }
    }
}

// MARK: - API Key Convenience

extension KeychainServicing {

    /// The Keychain account identifier for the Anthropic API key.
    static var apiKeyAccount: String { "anthropic-api-key" }

    /// Whether a non-empty API key is currently stored in the Keychain.
    ///
    /// Returns `false` both when no key is stored and when a Keychain read
    /// error occurs (the underlying `load(for:)` returns `nil` on error).
    var hasAPIKey: Bool {
        loadAPIKey()?.isEmpty == false
    }

    /// Loads the stored API key, if any.
    func loadAPIKey() -> String? {
        load(for: Self.apiKeyAccount)
    }

    /// Saves the given API key to the Keychain.
    func saveAPIKey(_ value: String) throws {
        try save(value, for: Self.apiKeyAccount)
    }

    /// Deletes the stored API key from the Keychain.
    func deleteAPIKey() {
        delete(for: Self.apiKeyAccount)
    }
}
