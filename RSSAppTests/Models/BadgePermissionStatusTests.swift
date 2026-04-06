import Testing
@testable import RSSApp

@Suite("BadgePermissionStatus Tests")
struct BadgePermissionStatusTests {

    @Test("All three cases are distinct")
    func allCasesDistinct() {
        let authorized = BadgePermissionStatus.authorized
        let denied = BadgePermissionStatus.denied
        let notDetermined = BadgePermissionStatus.notDetermined

        #expect(authorized != denied)
        #expect(authorized != notDetermined)
        #expect(denied != notDetermined)
    }

    @Test("Equatable conformance for same case")
    func sameCase() {
        #expect(BadgePermissionStatus.authorized == .authorized)
        #expect(BadgePermissionStatus.denied == .denied)
        #expect(BadgePermissionStatus.notDetermined == .notDetermined)
    }
}
