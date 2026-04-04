import Foundation
import Observation
import os

@MainActor
@Observable
final class DiscussionViewModel {

    private static let logger = Logger(category: "DiscussionViewModel")

    var messages: [ChatMessage] = []
    var currentInput: String = ""
    var isGenerating: Bool = false
    var errorMessage: String?
    private(set) var hasAPIKey: Bool = false
    private(set) var keychainError: String?

    private let article: Article
    private let content: ArticleContent
    private let claudeService: any ClaudeAPIServicing
    private let keychainService: any KeychainServicing

    init(
        article: Article,
        content: ArticleContent,
        claudeService: (any ClaudeAPIServicing)? = nil,
        keychainService: (any KeychainServicing)? = nil
    ) {
        self.article = article
        self.content = content
        self.claudeService = claudeService ?? ClaudeAPIService()
        self.keychainService = keychainService ?? KeychainService()
        updateAPIKeyState()
        Self.logger.debug("Initialized with hasAPIKey=\(self.hasAPIKey, privacy: .public)")
    }

    /// Refreshes the cached API key presence from the Keychain.
    ///
    /// Call after the user may have added or removed their API key (e.g., on
    /// sheet dismiss from API key settings).
    func refreshAPIKeyState() {
        updateAPIKeyState()
    }

    func sendMessage() async {
        let input = currentInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty, !isGenerating else { return }

        let apiKey: String
        do {
            guard let key = try keychainService.loadAPIKey(), !key.isEmpty else {
                errorMessage = "No API key configured."
                return
            }
            apiKey = key
        } catch {
            errorMessage = "Unable to read your API key from the Keychain."
            Self.logger.error("Keychain load failed during sendMessage: \(error, privacy: .public)")
            updateAPIKeyState()
            return
        }

        currentInput = ""
        errorMessage = nil
        messages.append(ChatMessage(role: .user, content: input))

        let assistantIndex = messages.count
        messages.append(ChatMessage(role: .assistant, content: ""))
        isGenerating = true
        defer { isGenerating = false }

        Self.logger.debug("sendMessage() — \(self.messages.count, privacy: .public) messages total")

        do {
            let stream = try await claudeService.sendMessage(
                systemPrompt: buildSystemPrompt(),
                messages: Array(messages.dropLast()),  // exclude the empty assistant placeholder
                apiKey: apiKey
            )
            for try await chunk in stream {
                messages[assistantIndex].content += chunk
            }
            Self.logger.info("Assistant response complete (\(self.messages[assistantIndex].content.count, privacy: .public) chars)")
        } catch {
            // RATIONALE: API streaming errors are surfaced inline in the chat bubble rather than
            // via the errorMessage alert. Validation errors (missing/unreadable API key) block
            // sending entirely and use an alert because no message was dispatched. Streaming errors
            // occur mid-conversation and are contextual to the assistant turn, so displaying them
            // inline preserves the conversational flow and lets the user see which response failed.
            messages[assistantIndex].content = "Error: \(error.localizedDescription)"
            Self.logger.error("Claude API error: \(error, privacy: .public)")
        }
    }

    // MARK: - Private

    private func updateAPIKeyState() {
        do {
            hasAPIKey = try keychainService.hasAPIKey()
            keychainError = nil
        } catch {
            hasAPIKey = false
            keychainError = "Unable to read your API key from the Keychain."
            Self.logger.error("Keychain read error: \(error, privacy: .public)")
        }
    }

    private func buildSystemPrompt() -> String {
        var prompt = "You are a helpful reading assistant. The user is reading the following article:\n\n"
        prompt += "Title: \(content.title)\n"
        if let byline = content.byline {
            prompt += "Author: \(byline)\n"
        }
        prompt += "\n---\n\(content.textContent)\n---\n\n"
        prompt += "Answer questions about this article concisely and accurately. "
        prompt += "If asked about something not covered in the article, say so."
        return prompt
    }
}
