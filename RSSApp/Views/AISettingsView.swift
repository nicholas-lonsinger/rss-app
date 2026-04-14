import SwiftUI
import os

struct AISettingsView: View {

    private static let logger = Logger(category: "AISettingsView")

    // MARK: - State

    @State private var selectedProvider: AIProvider = AIProvider.active()
    @State private var keyInputs: [AIProvider: String] = [:]
    @State private var keyPresence: [AIProvider: Bool] = [:]
    @State private var modelInputs: [AIProvider: String] = [:]
    @State private var maxTokensInputs: [AIProvider: String] = [:]
    @State private var isSaved: Bool = false
    @State private var saveError: String?
    @State private var deleteError: String?
    @State private var loadError: String?

    // Gemini model picker state
    @State private var geminiModels: [GeminiModel] = []
    @State private var isFetchingGeminiModels: Bool = false
    @State private var selectedGeminiModel: String = AIProvider.gemini.defaultModel

    private let keychainService = KeychainService()
    private let geminiModelService = GeminiModelService()

    var body: some View {
        Form {
            providerPickerSection
            keySection(for: selectedProvider)
            statusSection(for: selectedProvider)
            keyActionsSection(for: selectedProvider)
            modelConfigurationSection(for: selectedProvider)
        }
        .navigationTitle("AI")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadAllState()
        }
        .onChange(of: selectedProvider) { _, newProvider in
            // Only persist the provider switch when the new provider already has a stored key.
            // Switching the picker to an unconfigured provider should not override the active
            // provider until the user actually saves a key for it.
            if keyPresence[newProvider] == true {
                AIProvider.setActive(newProvider)
            }
            // Trigger Gemini model fetch when switching to Gemini
            if newProvider == .gemini, geminiModels.isEmpty {
                fetchGeminiModels()
            }
        }
        .alert("Key Saved", isPresented: $isSaved) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your \(selectedProvider.displayName) API key has been saved to the Keychain.")
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

    // MARK: - Sections

    private var providerPickerSection: some View {
        Section("AI Provider") {
            Picker("Provider", selection: $selectedProvider) {
                ForEach(AIProvider.allCases, id: \.self) { provider in
                    Text(provider.displayName).tag(provider)
                }
            }
        }
    }

    private func keySection(for provider: AIProvider) -> some View {
        Section {
            TextField(provider.keyPlaceholder, text: keyInputBinding(for: provider))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onChange(of: keyInputs[provider] ?? "") { _, newValue in
                    // Auto-detect provider when the user pastes a key with a known prefix
                    if let detected = AIProvider.detect(from: newValue), detected != selectedProvider {
                        selectedProvider = detected
                        AIProvider.setActive(detected)
                    }
                }
        } header: {
            Text("\(provider.displayName) API Key")
        } footer: {
            Text(provider.keyHelpText)
        }
    }

    private func statusSection(for provider: AIProvider) -> some View {
        Section("Status") {
            HStack {
                let hasKey = keyPresence[provider] == true
                Image(systemName: hasKey ? "checkmark.circle.fill" : "xmark.circle")
                    .foregroundStyle(hasKey ? .green : .secondary)
                Text(hasKey ? "API key configured" : "No API key configured")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func keyActionsSection(for provider: AIProvider) -> some View {
        Section {
            Button("Save Key") {
                saveKey(for: provider)
            }
            .disabled((keyInputs[provider] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Button("Remove Key", role: .destructive) {
                deleteKey(for: provider)
            }
            .disabled(keyPresence[provider] != true)
        }
    }

    @ViewBuilder
    private func modelConfigurationSection(for provider: AIProvider) -> some View {
        Section {
            switch provider {
            case .claude:
                claudeModelField
            case .gemini:
                geminiModelPicker
            }

            maxTokensField(for: provider)
        } header: {
            Text("Model Configuration")
        } footer: {
            Text("Changes take effect on the next API call. The API will reject unsupported models or token values.")
        }
    }

    // MARK: - Claude model input

    private var claudeModelField: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField(AIProvider.claude.defaultModel, text: modelInputBinding(for: .claude))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onChange(of: modelInputs[.claude] ?? "") { _, newValue in
                    saveModelIdentifier(newValue, for: .claude)
                }

            claudeModelValidationView
        }
    }

    @ViewBuilder
    private var claudeModelValidationView: some View {
        let result = ModelValidation.validate(modelInputs[.claude] ?? "")
        switch result {
        case .valid:
            Label("Valid model identifier", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        case .empty:
            Label("Will use default: \(AIProvider.claude.defaultModel)", systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .invalid(let reason):
            Label(reason, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    // MARK: - Gemini model picker

    @ViewBuilder
    private var geminiModelPicker: some View {
        if isFetchingGeminiModels {
            HStack {
                ProgressView()
                Text("Loading models…")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            }
        } else if geminiModels.isEmpty {
            // Fallback: show the default model as the only option
            HStack {
                Text("Model")
                Spacer()
                Text(selectedGeminiModel)
                    .foregroundStyle(.secondary)
            }
        } else {
            Picker("Model", selection: $selectedGeminiModel) {
                ForEach(geminiModels) { model in
                    Text(model.displayName).tag(model.id)
                }
            }
            .onChange(of: selectedGeminiModel) { _, newValue in
                saveModelIdentifier(newValue, for: .gemini)
            }
        }
    }

    // MARK: - Max tokens

    private func maxTokensField(for provider: AIProvider) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField(String(provider.defaultMaxTokens), text: maxTokensInputBinding(for: provider))
                .keyboardType(.numberPad)
                .onChange(of: maxTokensInputs[provider] ?? "") { _, newValue in
                    saveMaxTokens(newValue, for: provider)
                }

            maxTokensValidationView(for: provider)
        }
    }

    @ViewBuilder
    private func maxTokensValidationView(for provider: AIProvider) -> some View {
        let result = MaxTokensValidation.validate(maxTokensInputs[provider] ?? "")
        switch result {
        case .valid:
            Label("Valid token count", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        case .empty:
            Label("Will use default: \(provider.defaultMaxTokens)", systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .invalid(let reason):
            Label(reason, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    // MARK: - Binding helpers

    private func keyInputBinding(for provider: AIProvider) -> Binding<String> {
        Binding(
            get: { keyInputs[provider] ?? "" },
            set: { keyInputs[provider] = $0 }
        )
    }

    private func modelInputBinding(for provider: AIProvider) -> Binding<String> {
        Binding(
            get: { modelInputs[provider] ?? "" },
            set: { modelInputs[provider] = $0 }
        )
    }

    private func maxTokensInputBinding(for provider: AIProvider) -> Binding<String> {
        Binding(
            get: { maxTokensInputs[provider] ?? "" },
            set: { maxTokensInputs[provider] = $0 }
        )
    }

    // MARK: - Load state

    private func loadAllState() {
        selectedProvider = AIProvider.active()
        loadError = nil

        for provider in AIProvider.allCases {
            loadKeyState(for: provider)
            loadModelConfiguration(for: provider)
        }

        // Pre-select stored Gemini model for the picker
        selectedGeminiModel = AIProvider.gemini.currentModel()

        // Fetch Gemini models if Gemini is selected
        if selectedProvider == .gemini {
            fetchGeminiModels()
        }
    }

    private func loadKeyState(for provider: AIProvider) {
        do {
            let existing = try keychainService.loadAPIKey(for: provider)
            keyPresence[provider] = existing?.isEmpty == false
            if let existing, !existing.isEmpty {
                // Show a placeholder so the user knows a key is set, without revealing it.
                keyInputs[provider] = String(repeating: "•", count: min(existing.count, 20))
            } else {
                keyInputs[provider] = ""
            }
        } catch {
            keyPresence[provider] = false
            loadError = "Unable to read your API key from the Keychain. Please try again later."
            Self.logger.error("Failed to load \(provider.displayName, privacy: .public) API key: \(error, privacy: .public)")
        }
    }

    private func loadModelConfiguration(for provider: AIProvider) {
        let storedModel = UserDefaults.standard.string(forKey: provider.modelDefaultsKey) ?? ""
        modelInputs[provider] = storedModel

        let storedTokens = UserDefaults.standard.integer(forKey: provider.maxTokensDefaultsKey)
        maxTokensInputs[provider] = storedTokens > 0 ? String(storedTokens) : ""
    }

    // MARK: - Save / Delete

    private func saveKey(for provider: AIProvider) {
        let trimmed = (keyInputs[provider] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.allSatisfy({ $0 == "•" }) else {
            Self.logger.debug("saveKey skipped for \(provider.displayName, privacy: .public): input is empty or masked placeholder")
            return
        }
        do {
            try keychainService.saveAPIKey(trimmed, for: provider)
            keyPresence[provider] = true
            isSaved = true
            Self.logger.notice("\(provider.displayName, privacy: .public) API key saved to Keychain")
            // Now that a key exists, activate the provider if the user had selected it but
            // persistence was deferred (because no key was stored at picker-change time).
            if provider == selectedProvider {
                AIProvider.setActive(provider)
            }

            // Trigger Gemini model fetch after saving a Gemini key
            if provider == .gemini {
                fetchGeminiModels()
            }
        } catch {
            saveError = "Unable to save your API key to the Keychain. Please try again."
            Self.logger.error("Failed to save \(provider.displayName, privacy: .public) API key: \(error, privacy: .public)")
        }
    }

    private func deleteKey(for provider: AIProvider) {
        do {
            try keychainService.deleteAPIKey(for: provider)
            keyPresence[provider] = false
            keyInputs[provider] = ""
            if provider == .gemini {
                geminiModels = []
            }
            Self.logger.notice("\(provider.displayName, privacy: .public) API key removed from Keychain")
        } catch {
            deleteError = "Unable to remove your API key from the Keychain. Please try again."
            Self.logger.error("Failed to delete \(provider.displayName, privacy: .public) API key: \(error, privacy: .public)")
        }
    }

    // MARK: - Model persistence

    private func saveModelIdentifier(_ value: String, for provider: AIProvider) {
        switch provider {
        case .claude:
            switch ModelValidation.validate(value) {
            case .empty:
                UserDefaults.standard.removeObject(forKey: provider.modelDefaultsKey)
                Self.logger.notice("Claude model identifier cleared, will use default")
            case .valid(let validated):
                UserDefaults.standard.set(validated, forKey: provider.modelDefaultsKey)
                Self.logger.notice("Claude model identifier saved: \(validated, privacy: .public)")
            case .invalid(let reason):
                Self.logger.debug("Claude model identifier input rejected: \(reason, privacy: .public)")
            }
        case .gemini:
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                UserDefaults.standard.removeObject(forKey: provider.modelDefaultsKey)
                Self.logger.notice("Gemini model identifier cleared, will use default")
            } else {
                UserDefaults.standard.set(trimmed, forKey: provider.modelDefaultsKey)
                Self.logger.notice("Gemini model identifier saved: \(trimmed, privacy: .public)")
            }
        }
    }

    private func saveMaxTokens(_ value: String, for provider: AIProvider) {
        switch MaxTokensValidation.validate(value) {
        case .empty:
            UserDefaults.standard.removeObject(forKey: provider.maxTokensDefaultsKey)
            Self.logger.notice("\(provider.displayName, privacy: .public) max tokens cleared, will use default")
        case .valid(let validated):
            UserDefaults.standard.set(validated, forKey: provider.maxTokensDefaultsKey)
            Self.logger.notice("\(provider.displayName, privacy: .public) max tokens saved: \(validated, privacy: .public)")
        case .invalid(let reason):
            Self.logger.debug("\(provider.displayName, privacy: .public) max tokens input rejected: \(reason, privacy: .public)")
        }
    }

    // MARK: - Gemini model fetching

    private func fetchGeminiModels() {
        let key: String
        do {
            guard let loaded = try keychainService.loadAPIKey(for: .gemini), !loaded.isEmpty else {
                Self.logger.debug("Skipping Gemini model fetch: no API key stored")
                return
            }
            key = loaded
        } catch {
            Self.logger.warning("Skipping Gemini model fetch: Keychain read failed: \(error, privacy: .public)")
            return
        }

        isFetchingGeminiModels = true
        Task {
            defer { isFetchingGeminiModels = false }
            do {
                let models = try await geminiModelService.fetchModels(apiKey: key)
                if models.isEmpty {
                    Self.logger.warning("Gemini model list empty, using fallback")
                    geminiModels = [GeminiModel(id: AIProvider.gemini.defaultModel, displayName: "Gemini 2.5 Flash")]
                } else {
                    geminiModels = models
                }
                // Preserve stored selection if it's in the list, otherwise default
                let stored = AIProvider.gemini.currentModel()
                if geminiModels.contains(where: { $0.id == stored }) {
                    selectedGeminiModel = stored
                } else {
                    selectedGeminiModel = geminiModels.first?.id ?? AIProvider.gemini.defaultModel
                }
            } catch {
                Self.logger.error("Failed to fetch Gemini model list: \(error, privacy: .public)")
                // Fall back to a single known-good model so the UI remains usable
                geminiModels = [GeminiModel(id: AIProvider.gemini.defaultModel, displayName: "Gemini 2.5 Flash")]
                selectedGeminiModel = AIProvider.gemini.currentModel()
                loadError = "Unable to fetch Gemini model list. Check your API key and try again."
            }
        }
    }
}
