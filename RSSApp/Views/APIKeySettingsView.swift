import SwiftUI
import os

struct APIKeySettingsView: View {
    @State private var keyInput: String = ""
    @State private var isSaved: Bool = false
    @State private var saveError: String?
    @State private var deleteError: String?
    @State private var modelInput: String = ""
    @State private var maxTokensInput: String = ""
    @State private var hasAPIKey: Bool = false
    @State private var loadError: String?

    private static let logger = Logger(category: "APIKeySettingsView")

    private let keychainService = KeychainService()

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
                    deleteKey()
                }
                .disabled(!hasAPIKey)
            }

            modelConfigurationSection
        }
        .navigationTitle("API Key")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            do {
                let existing = try keychainService.loadAPIKey()
                hasAPIKey = existing?.isEmpty == false
                if let existing {
                    // Show a placeholder so the user knows a key is set, without revealing it.
                    keyInput = String(repeating: "•", count: min(existing.count, 20))
                }
                loadError = nil
            } catch {
                hasAPIKey = false
                loadError = "Unable to read your API key from the Keychain. Please try again later."
                Self.logger.error("Failed to load API key from Keychain: \(error, privacy: .public)")
            }
            loadModelConfiguration()
        }
        .alert("Key Saved", isPresented: $isSaved) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your Anthropic API key has been saved to the Keychain.")
        }
        .alert("Save Failed", isPresented: $saveError.isPresented()) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveError ?? "")
        }
        .alert("Remove Failed", isPresented: $deleteError.isPresented()) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deleteError ?? "")
        }
        .alert("Load Failed", isPresented: $loadError.isPresented()) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(loadError ?? "")
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

    private func deleteKey() {
        do {
            try keychainService.deleteAPIKey()
            hasAPIKey = false
            keyInput = ""
            Self.logger.notice("API key removed from Keychain")
        } catch {
            deleteError = "Unable to remove your API key from the Keychain. Please try again."
            Self.logger.error("Failed to delete API key from Keychain: \(error, privacy: .public)")
        }
    }

    private func saveKey() {
        let trimmed = keyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.allSatisfy({ $0 == "•" }) else {
            Self.logger.debug("saveKey skipped: input is empty or masked placeholder")
            return
        }
        do {
            try keychainService.saveAPIKey(trimmed)
            hasAPIKey = true
            isSaved = true
            Self.logger.notice("API key saved to Keychain")
        } catch {
            saveError = "Unable to save your API key to the Keychain. Please try again."
            Self.logger.error("Failed to save API key to Keychain: \(error, privacy: .public)")
        }
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
