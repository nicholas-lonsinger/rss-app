import SwiftUI

struct APIKeySettingsView: View {
    @State private var keyInput: String = ""
    @State private var isSaved: Bool = false

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
        }
        .navigationTitle("API Key")
        .navigationBarTitleDisplayMode(.inline)
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

    private func saveKey() {
        let trimmed = keyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.allSatisfy({ $0 == "•" }) else { return }
        try? keychainService.save(trimmed, for: Self.account)
        isSaved = true
    }
}
