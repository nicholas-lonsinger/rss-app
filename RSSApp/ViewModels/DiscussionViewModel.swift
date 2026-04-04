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
        self.hasAPIKey = self.keychainService.hasAPIKey
    }

    /// Re-checks the Keychain for API key presence and updates the cached state.
    func refreshHasAPIKey() {
        hasAPIKey = keychainService.hasAPIKey
    }

    func sendMessage() async {
        let input = currentInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty, !isGenerating else { return }
        guard let apiKey = keychainService.loadAPIKey(), !apiKey.isEmpty else {
            errorMessage = "No API key configured."
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
            messages[assistantIndex].content = "Error: \(error.localizedDescription)"
            Self.logger.error("Claude API error: \(error, privacy: .public)")
        }
    }

    // MARK: - Private

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
