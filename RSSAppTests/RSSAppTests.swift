import Testing
@testable import RSSApp

@Suite("RSSApp Tests")
struct RSSAppTests {
    @Test("App launches with content view")
    @MainActor
    func contentViewExists() {
        let view = ContentView()
        #expect(view.body is Never == false)
    }
}
