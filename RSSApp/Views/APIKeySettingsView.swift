import SwiftUI
import os

struct APIKeySettingsView: View {
    @State private var keyInput: String = ""
    @State private var isSaved: Bool = false
    @State private var modelInput: String = ""
    @State private var maxTokensInput: String = ""

    private static let logger = Logger(category: "APIKeySettingsView")

    private let keychainService = KeychainService()
    private static let account = "anthropic-api-key"

    /// Whether an API key is currently stored in the Keychain.
    private var hasAPIKey: Bool {
        keychainService.load(for: Self.account) != nil
    }

    var body: some View {
        Form {
            Section {
                TextField("sk-ant-…", text: $keyInput)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            } header: {
                Text("Anthropic API Key")
            } footer: {
                Text("Your key is stored in the iOS Keychain and never leaves your device. Get a key at console.anthropic.com.")
            }

            Section {
                HStack {
                    Image(systemName: hasAPIKey ? "checkmark.circle.fill" : "xmark.circle")
                        .foregroundStyle(hasAPIKey ? .green : .secondary)
                    Text(hasAPIKey ? "API key configured" : "No API key configured")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Status")
            }

            Section {
                Button("Save Key") {
                    saveKey()
                }
                .disabled(keyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button("Remove Key", role: .destructive) {
                    keychainService.delete(for: Self.account)
                    keyInput = ""
                }
                .disabled(!hasAPIKey)
            }

            modelConfigurationSection
        }
        .navigationTitle("API Key")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if let existing = keychainService.load(for: Self.account) {
                // Show a placeholder so the user knows a key is set, without revealing it.
                keyInput = String(repeating: "•", count: min(existing.count, 20))
            }
            loadModelConfiguration()
        }
        .alert("Key Saved", isPresented: $isSaved) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your Anthropic API key has been saved to the Keychain.")
        }
    }

    // MARK: - Model Configuration

    @ViewBuilder
    private var modelConfigurationSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                TextField("claude-haiku-4-5-20251001", text: $modelInput)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onChange(of: modelInput) { _, newValue in
                        saveModelIdentifier(newValue)
                    }

                modelValidationView
            }

            VStack(alignment: .leading, spacing: 4) {
                TextField("4096", text: $maxTokensInput)
                    .keyboardType(.numberPad)
                    .onChange(of: maxTokensInput) { _, newValue in
                        saveMaxTokens(newValue)
                    }

                maxTokensValidationView
            }
        } header: {
            Text("Model Configuration")
        } footer: {
            Text("Changes take effect on the next API call. The API will reject unsupported models or token values.")
        }
    }

    @ViewBuilder
    private var modelValidationView: some View {
        let result = ModelValidation.validate(modelInput)
        switch result {
        case .valid:
            Label("Valid model identifier", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        case .empty:
            Label("Will use default: \(ClaudeAPIService.defaultModel)", systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .invalid(let reason):
            Label(reason, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private var maxTokensValidationView: some View {
        let result = MaxTokensValidation.validate(maxTokensInput)
        switch result {
        case .valid:
            Label("Valid token count", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        case .empty:
            Label("Will use default: \(ClaudeAPIService.defaultMaxTokens)", systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .invalid(let reason):
            Label(reason, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    // MARK: - Persistence

    private func saveKey() {
        let trimmed = keyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.allSatisfy({ $0 == "•" }) else { return }
        try? keychainService.save(trimmed, for: Self.account)
        isSaved = true
    }

    private func loadModelConfiguration() {
        let storedModel = UserDefaults.standard.string(forKey: ClaudeAPIService.modelDefaultsKey) ?? ""
        modelInput = storedModel

        let storedTokens = UserDefaults.standard.integer(forKey: ClaudeAPIService.maxTokensDefaultsKey)
        maxTokensInput = storedTokens > 0 ? String(storedTokens) : ""
    }

    private func saveModelIdentifier(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            UserDefaults.standard.removeObject(forKey: ClaudeAPIService.modelDefaultsKey)
            Self.logger.debug("Model identifier cleared, will use default")
        } else if case .valid = ModelValidation.validate(trimmed) {
            UserDefaults.standard.set(trimmed, forKey: ClaudeAPIService.modelDefaultsKey)
            Self.logger.debug("Model identifier saved: \(trimmed, privacy: .public)")
        }
    }

    private func saveMaxTokens(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            UserDefaults.standard.removeObject(forKey: ClaudeAPIService.maxTokensDefaultsKey)
            Self.logger.debug("Max tokens cleared, will use default")
        } else if let intValue = Int(trimmed), intValue >= 1 {
            UserDefaults.standard.set(intValue, forKey: ClaudeAPIService.maxTokensDefaultsKey)
            Self.logger.debug("Max tokens saved: \(intValue, privacy: .public)")
        }
    }
}

// MARK: - Validation

enum ModelValidation: Equatable {
    case valid
    case empty
    case invalid(String)

    /// Pattern: lowercase alphanumeric characters, hyphens, and digits.
    private static let validCharacterSet = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-")

    static func validate(_ input: String) -> ModelValidation {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .empty }
        if !trimmed.hasPrefix("claude-") {
            return .invalid("Model ID must start with 'claude-'")
        }
        if trimmed.unicodeScalars.contains(where: { !validCharacterSet.contains($0) }) {
            return .invalid("Only lowercase letters, digits, and hyphens are allowed")
        }
        return .valid
    }
}

enum MaxTokensValidation: Equatable {
    case valid
    case empty
    case invalid(String)

    static func validate(_ input: String) -> MaxTokensValidation {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .empty }
        guard let value = Int(trimmed) else {
            return .invalid("Must be a whole number")
        }
        if value < 1 {
            return .invalid("Must be at least 1")
        }
        return .valid
    }
}
