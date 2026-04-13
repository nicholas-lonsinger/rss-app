import Foundation
import os

/// Supported AI providers for article discussion.
enum AIProvider: String, CaseIterable, Sendable {
    case claude
    case gemini

    // MARK: - Display

    var displayName: String {
        switch self {
        case .claude: "Claude"
        case .gemini: "Gemini"
        }
    }

    // MARK: - Keychain

    /// The Keychain account identifier for this provider's API key.
    ///
    /// Claude uses `"anthropic-api-key"` to match the existing value already
    /// stored for users upgrading from the single-provider version.
    var keychainAccount: String {
        switch self {
        case .claude: "anthropic-api-key"
        case .gemini: "google-gemini-api-key"
        }
    }

    // MARK: - UserDefaults keys

    var modelDefaultsKey: String {
        switch self {
        case .claude: "claude_model_identifier"
        case .gemini: "gemini_model_identifier"
        }
    }

    var maxTokensDefaultsKey: String {
        switch self {
        case .claude: "claude_max_tokens"
        case .gemini: "gemini_max_tokens"
        }
    }

    // MARK: - Defaults

    var defaultModel: String {
        switch self {
        case .claude: "claude-haiku-4-5-20251001"
        case .gemini: "gemini-2.5-flash"
        }
    }

    var defaultMaxTokens: Int {
        switch self {
        case .claude: 4096
        case .gemini: 8192
        }
    }

    // MARK: - UI Hints

    var keyPlaceholder: String {
        switch self {
        case .claude: "sk-ant-…"
        case .gemini: "AIzaSy…"
        }
    }

    var keyHelpText: String {
        switch self {
        case .claude:
            "Your key is stored in the iOS Keychain and never leaves your device. Get a key at console.anthropic.com."
        case .gemini:
            "Your key is stored in the iOS Keychain and never leaves your device. Get a key at aistudio.google.com."
        }
    }

    // MARK: - Configuration reading

    /// Reads the current model from UserDefaults, falling back to `defaultModel`.
    func currentModel(defaults: UserDefaults = .standard) -> String {
        guard let stored = defaults.string(forKey: modelDefaultsKey), !stored.isEmpty else {
            return defaultModel
        }
        return stored
    }

    /// Reads the current max tokens from UserDefaults, falling back to `defaultMaxTokens`.
    func currentMaxTokens(defaults: UserDefaults = .standard) -> Int {
        let stored = defaults.integer(forKey: maxTokensDefaultsKey)
        return stored > 0 ? stored : defaultMaxTokens
    }

    // MARK: - Active provider persistence

    private static let activeProviderKey = "active_ai_provider"
    private static let logger = Logger(category: "AIProvider")

    /// The currently selected AI provider. Defaults to `.claude` when unset, matching
    /// the pre-multi-provider behavior so existing users are not disrupted on upgrade.
    static var active: AIProvider {
        guard let raw = UserDefaults.standard.string(forKey: activeProviderKey),
              let provider = AIProvider(rawValue: raw) else {
            return .claude
        }
        return provider
    }

    static func setActive(_ provider: AIProvider, defaults: UserDefaults = .standard) {
        defaults.set(provider.rawValue, forKey: activeProviderKey)
        logger.notice("Active AI provider set to \(provider.displayName, privacy: .public)")
    }

    // MARK: - Key auto-detection

    /// Attempts to infer the provider from a key string by prefix matching.
    ///
    /// Returns `nil` when the key does not match any known prefix, letting the
    /// caller fall back to the user's current provider selection.
    ///
    /// The detection table is a sequence of `(prefix, provider)` pairs so adding
    /// a future provider requires only one additional entry here.
    static func detect(from key: String) -> AIProvider? {
        let prefixTable: [(String, AIProvider)] = [
            ("sk-ant-", .claude),
            ("AIzaSy", .gemini),
        ]
        for (prefix, provider) in prefixTable {
            if key.hasPrefix(prefix) { return provider }
        }
        return nil
    }

    // MARK: - Migration

    /// Migrates the active provider preference on first launch after the
    /// multi-provider update. Sets the active provider to `.claude` when a
    /// Claude key already exists, ensuring existing users are not disrupted.
    ///
    /// No Keychain migration is needed: `AIProvider.claude.keychainAccount`
    /// is `"anthropic-api-key"`, which matches the pre-multi-provider account.
    static func migrateIfNeeded(
        keychain: any KeychainServicing,
        defaults: UserDefaults = .standard
    ) {
        let migrationKey = "ai_provider_migration_v1"
        guard !defaults.bool(forKey: migrationKey) else { return }
        defer { defaults.set(true, forKey: migrationKey) }

        if (try? keychain.hasAPIKey(for: .claude)) == true {
            setActive(.claude, defaults: defaults)
            logger.notice("AI provider migration: set active provider to Claude (existing key found)")
        }
    }
}
