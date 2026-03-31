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
        hasKey: Bool = true
    ) -> DiscussionViewModel {
        let claudeMock = MockClaudeAPIService()
        claudeMock.chunks = chunks
        claudeMock.errorToThrow = error

        let keychainMock = MockKeychainService()
        if hasKey {
            try? keychainMock.save("sk-test", for: "anthropic-api-key")
        }

        return DiscussionViewModel(
            article: TestFixtures.makeArticle(),
            content: makeContent(),
            claudeService: claudeMock,
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

    @Test("sendMessage sets error content when claude service throws")
    func sendHandlesError() async {
        let vm = makeVM(error: ClaudeAPIError.httpError(statusCode: 401))
        vm.currentInput = "A question"
        await vm.sendMessage()
        #expect(vm.messages[1].content.hasPrefix("Error:"))
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
}
