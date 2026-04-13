import Foundation
import Testing
@testable import RSSApp

@Suite("DiscussionViewModel")
@MainActor
struct DiscussionViewModelTests {

    private func makeContent() -> ArticleContent {
        ArticleContent(
            title: "Test Article",
            byline: "Author Name",
            htmlContent: "<p>Body</p>",
            textContent: "Body text"
        )
    }

    private func makeVM(
        chunks: [String] = ["Hello", " world"],
        error: Error? = nil,
        hasKey: Bool = true,
        provider: AIProvider = .claude
    ) -> DiscussionViewModel {
        let aiMock = MockAIService()
        aiMock.chunks = chunks
        aiMock.errorToThrow = error

        let keychainMock = MockKeychainService()
        if hasKey {
            // RATIONALE: MockKeychainService.save never throws, so force-try is
            // safe and ensures the test fails loudly if that assumption changes.
            try! keychainMock.saveAPIKey("sk-test", for: provider)
        }
        // Set active provider so DiscussionViewModel reads the right key
        AIProvider.setActive(provider)

        return DiscussionViewModel(
            article: TestFixtures.makeArticle(),
            content: makeContent(),
            aiService: aiMock,
            keychainService: keychainMock
        )
    }

    @Test("hasAPIKey reflects keychain state")
    func hasAPIKey() {
        let withKey = makeVM(hasKey: true)
        let withoutKey = makeVM(hasKey: false)
        #expect(withKey.hasAPIKey == true)
        #expect(withoutKey.hasAPIKey == false)
    }

    @Test("refreshAPIKeyState updates hasAPIKey when keychain changes")
    func refreshAPIKeyState() throws {
        let keychainMock = MockKeychainService()
        AIProvider.setActive(.claude)
        let vm = DiscussionViewModel(
            article: TestFixtures.makeArticle(),
            content: makeContent(),
            aiService: MockAIService(),
            keychainService: keychainMock
        )
        #expect(vm.hasAPIKey == false)

        try keychainMock.saveAPIKey("sk-new", for: .claude)
        // Still false until explicitly refreshed
        #expect(vm.hasAPIKey == false)

        vm.refreshAPIKeyState()
        #expect(vm.hasAPIKey == true)

        try keychainMock.deleteAPIKey(for: .claude)
        vm.refreshAPIKeyState()
        #expect(vm.hasAPIKey == false)
    }

    @Test("keychainError is set when keychain load fails")
    func keychainErrorOnLoadFailure() {
        let keychainMock = MockKeychainService()
        keychainMock.loadErrorToThrow = KeychainError.loadFailed(-25293)
        let vm = DiscussionViewModel(
            article: TestFixtures.makeArticle(),
            content: makeContent(),
            aiService: MockAIService(),
            keychainService: keychainMock
        )
        #expect(vm.hasAPIKey == false)
        #expect(vm.keychainError != nil)
    }

    @Test("keychainError clears when keychain recovers")
    func keychainErrorClearsOnRecovery() throws {
        let keychainMock = MockKeychainService()
        keychainMock.loadErrorToThrow = KeychainError.loadFailed(-25293)
        let vm = DiscussionViewModel(
            article: TestFixtures.makeArticle(),
            content: makeContent(),
            aiService: MockAIService(),
            keychainService: keychainMock
        )
        #expect(vm.keychainError != nil)

        keychainMock.loadErrorToThrow = nil
        try keychainMock.saveAPIKey("sk-test", for: .claude)
        vm.refreshAPIKeyState()
        #expect(vm.keychainError == nil)
        #expect(vm.hasAPIKey == true)
    }

    @Test("sendMessage shows error when keychain load throws")
    func sendMessageKeychainError() async {
        let keychainMock = MockKeychainService()
        try! keychainMock.saveAPIKey("sk-test", for: .claude)
        AIProvider.setActive(.claude)
        let vm = DiscussionViewModel(
            article: TestFixtures.makeArticle(),
            content: makeContent(),
            aiService: MockAIService(),
            keychainService: keychainMock
        )
        // Inject error after init so hasAPIKey is true but load fails during send
        keychainMock.loadErrorToThrow = KeychainError.loadFailed(-25293)
        vm.currentInput = "Hello"
        await vm.sendMessage()
        #expect(vm.errorMessage != nil)
        #expect(vm.messages.isEmpty)
    }

    @Test("sendMessage appends user message then assistant message")
    func sendAppendsMessages() async {
        let vm = makeVM()
        vm.currentInput = "What is this article about?"
        await vm.sendMessage()
        #expect(vm.messages.count == 2)
        #expect(vm.messages[0].role == .user)
        #expect(vm.messages[0].content == "What is this article about?")
        #expect(vm.messages[1].role == .assistant)
    }

    @Test("sendMessage accumulates streamed chunks into assistant message")
    func sendAccumulatesChunks() async {
        let vm = makeVM(chunks: ["Hello", " world"])
        vm.currentInput = "Tell me more"
        await vm.sendMessage()
        #expect(vm.messages[1].content == "Hello world")
    }

    @Test("sendMessage clears currentInput after send")
    func sendClearsInput() async {
        let vm = makeVM()
        vm.currentInput = "A question"
        await vm.sendMessage()
        #expect(vm.currentInput == "")
    }

    @Test("sendMessage sets error content when AI service throws")
    func sendHandlesError() async {
        let vm = makeVM(error: AIServiceError.httpError(statusCode: 401))
        vm.currentInput = "A question"
        await vm.sendMessage()
        #expect(vm.messages[1].content.hasPrefix("Error:"))
    }

    @Test("sendMessage surfaces serverError message in assistant bubble")
    func sendHandlesServerError() async {
        let vm = makeVM(error: AIServiceError.serverError(message: "Rate limit exceeded"))
        vm.currentInput = "A question"
        await vm.sendMessage()
        #expect(vm.messages.count == 2)
        #expect(vm.messages[1].role == .assistant)
        #expect(vm.messages[1].content == "Error: Rate limit exceeded")
    }

    @Test("sendMessage does nothing when input is empty")
    func sendIgnoresEmptyInput() async {
        let vm = makeVM()
        vm.currentInput = "   "
        await vm.sendMessage()
        #expect(vm.messages.isEmpty)
    }

    @Test("sendMessage sets errorMessage when no API key is configured")
    func sendWithoutKey() async {
        let vm = makeVM(hasKey: false)
        vm.currentInput = "Hello"
        await vm.sendMessage()
        #expect(vm.errorMessage != nil)
        #expect(vm.messages.isEmpty)
    }

    @Test("sendMessage clears errorMessage on successful send")
    func sendClearsErrorMessage() async {
        let keychainMock = MockKeychainService()
        let aiMock = MockAIService()
        aiMock.chunks = ["OK"]
        AIProvider.setActive(.claude)

        // Start without a key so sendMessage sets errorMessage
        let vm = DiscussionViewModel(
            article: TestFixtures.makeArticle(),
            content: makeContent(),
            aiService: aiMock,
            keychainService: keychainMock
        )
        vm.currentInput = "Hello"
        await vm.sendMessage()
        #expect(vm.errorMessage != nil)

        // Add a key and retry — errorMessage should clear
        try! keychainMock.saveAPIKey("sk-test", for: .claude)
        vm.refreshAPIKeyState()
        vm.currentInput = "Hello again"
        await vm.sendMessage()
        #expect(vm.errorMessage == nil)
        #expect(vm.messages.count == 2)
    }

    @Test("sendMessage passes correct model and maxTokens to AI service")
    func sendPassesProviderConfig() async {
        let aiMock = MockAIService()
        aiMock.chunks = ["response"]
        let keychainMock = MockKeychainService()

        // Set up a test-specific UserDefaults to control model/maxTokens
        let suiteName = "com.rssapp.test.\(#function)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set("claude-opus-4-20250115", forKey: AIProvider.claude.modelDefaultsKey)
        defaults.set(2048, forKey: AIProvider.claude.maxTokensDefaultsKey)
        // Write through to standard defaults so DiscussionViewModel can read them
        UserDefaults.standard.set("claude-opus-4-20250115", forKey: AIProvider.claude.modelDefaultsKey)
        UserDefaults.standard.set(2048, forKey: AIProvider.claude.maxTokensDefaultsKey)
        defer {
            UserDefaults.standard.removeObject(forKey: AIProvider.claude.modelDefaultsKey)
            UserDefaults.standard.removeObject(forKey: AIProvider.claude.maxTokensDefaultsKey)
        }

        try! keychainMock.saveAPIKey("sk-test", for: .claude)
        AIProvider.setActive(.claude)

        let vm = DiscussionViewModel(
            article: TestFixtures.makeArticle(),
            content: makeContent(),
            aiService: aiMock,
            keychainService: keychainMock
        )
        vm.currentInput = "A question"
        await vm.sendMessage()

        #expect(aiMock.capturedModel == "claude-opus-4-20250115")
        #expect(aiMock.capturedMaxTokens == 2048)
        #expect(aiMock.capturedAPIKey == "sk-test")
    }
}
