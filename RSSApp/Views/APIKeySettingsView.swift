import SwiftUI

struct APIKeySettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var keyInput: String = ""
    @State private var isSaved: Bool = false

    private let keychainService = KeychainService()
    private static let account = "anthropic-api-key"

    var body: some View {
        NavigationStack {
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
                        Image(systemName: keychainService.load(for: Self.account) != nil ? "checkmark.circle.fill" : "xmark.circle")
                            .foregroundStyle(keychainService.load(for: Self.account) != nil ? .green : .secondary)
                        Text(keychainService.load(for: Self.account) != nil ? "API key configured" : "No API key configured")
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
                    .disabled(keychainService.load(for: Self.account) == nil)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                if let existing = keychainService.load(for: Self.account) {
                    // Show a placeholder so the user knows a key is set, without revealing it.
                    keyInput = String(repeating: "•", count: min(existing.count, 20))
                }
            }
            .alert("Key Saved", isPresented: $isSaved) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Your Anthropic API key has been saved to the Keychain.")
            }
        }
    }

    private func saveKey() {
        let trimmed = keyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.allSatisfy({ $0 == "•" }) else { return }
        try? keychainService.save(trimmed, for: Self.account)
        isSaved = true
    }
}
