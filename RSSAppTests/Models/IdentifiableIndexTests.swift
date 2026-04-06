import Testing
@testable import RSSApp

@Suite("IdentifiableIndex Tests")
struct IdentifiableIndexTests {

    @Test("id returns the wrapped value")
    func idReturnsValue() {
        let index = IdentifiableIndex(value: 42)
        #expect(index.id == 42)
    }

    @Test("value stores the provided integer")
    func valueStored() {
        let index = IdentifiableIndex(value: 7)
        #expect(index.value == 7)
    }

    @Test("zero index is valid")
    func zeroIndex() {
        let index = IdentifiableIndex(value: 0)
        #expect(index.id == 0)
        #expect(index.value == 0)
    }

    @Test("distinct values produce distinct ids")
    func distinctIds() {
        let a = IdentifiableIndex(value: 1)
        let b = IdentifiableIndex(value: 2)
        #expect(a.id != b.id)
    }

    @Test("same value produces same id")
    func sameValueSameId() {
        let a = IdentifiableIndex(value: 5)
        let b = IdentifiableIndex(value: 5)
        #expect(a.id == b.id)
    }
}
