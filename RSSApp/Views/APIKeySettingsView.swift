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
        case .valid(_):
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
        case .valid(_):
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
        switch ModelValidation.validate(value) {
        case .empty:
            UserDefaults.standard.removeObject(forKey: ClaudeAPIService.modelDefaultsKey)
            Self.logger.notice("Model identifier cleared, will use default")
        case .valid(let validated):
            UserDefaults.standard.set(validated, forKey: ClaudeAPIService.modelDefaultsKey)
            Self.logger.notice("Model identifier saved: \(validated, privacy: .public)")
        case .invalid(let reason):
            Self.logger.debug("Model identifier input rejected: \(reason, privacy: .public)")
        }
    }

    private func saveMaxTokens(_ value: String) {
        switch MaxTokensValidation.validate(value) {
        case .empty:
            UserDefaults.standard.removeObject(forKey: ClaudeAPIService.maxTokensDefaultsKey)
            Self.logger.notice("Max tokens cleared, will use default")
        case .valid(let validated):
            UserDefaults.standard.set(validated, forKey: ClaudeAPIService.maxTokensDefaultsKey)
            Self.logger.notice("Max tokens saved: \(validated, privacy: .public)")
        case .invalid(let reason):
            Self.logger.debug("Max tokens input rejected: \(reason, privacy: .public)")
        }
    }
}
