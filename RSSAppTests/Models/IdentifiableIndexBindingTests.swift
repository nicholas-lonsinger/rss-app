import SwiftUI
import Testing
@testable import RSSApp

@Suite("IdentifiableIndex Binding Extension Tests")
struct IdentifiableIndexBindingTests {

    /// MainActor-isolated mutable storage for binding-backed tests under Swift 6 strict concurrency.
    @MainActor
    private final class Box {
        var value: Int?

        init(_ value: Int? = nil) {
            self.value = value
        }

        var binding: Binding<Int?> {
            Binding(get: { self.value }, set: { self.value = $0 })
        }
    }

    // MARK: - identifiableIndex

    @Test("identifiableIndex get returns nil when underlying value is nil")
    @MainActor func identifiableIndexGetNil() {
        let box = Box(nil)
        let result = box.binding.identifiableIndex.wrappedValue
        #expect(result == nil)
    }

    @Test("identifiableIndex get wraps non-nil value in IdentifiableIndex")
    @MainActor func identifiableIndexGetNonNil() {
        let box = Box(5)
        let result = box.binding.identifiableIndex.wrappedValue
        #expect(result?.value == 5)
        #expect(result?.id == 5)
    }

    @Test("identifiableIndex set unwraps IdentifiableIndex to Int")
    @MainActor func identifiableIndexSetNonNil() {
        let box = Box(nil)
        box.binding.identifiableIndex.wrappedValue = IdentifiableIndex(value: 3)
        #expect(box.value == 3)
    }

    @Test("identifiableIndex set nil clears the underlying value")
    @MainActor func identifiableIndexSetNil() {
        let box = Box(10)
        box.binding.identifiableIndex.wrappedValue = nil
        #expect(box.value == nil)
    }

    @Test("identifiableIndex roundtrips correctly")
    @MainActor func identifiableIndexRoundtrip() {
        let box = Box(nil)
        let binding = box.binding

        // Set via identifiableIndex
        binding.identifiableIndex.wrappedValue = IdentifiableIndex(value: 7)
        #expect(box.value == 7)

        // Read back via identifiableIndex
        let result = binding.identifiableIndex.wrappedValue
        #expect(result?.value == 7)
    }

    // MARK: - nonOptionalIndex

    @Test("nonOptionalIndex get returns the underlying value when non-nil")
    @MainActor func nonOptionalIndexGetNonNil() {
        let box = Box(42)
        let result = box.binding.nonOptionalIndex.wrappedValue
        #expect(result == 42)
    }

    // nonOptionalIndex get with nil triggers assertionFailure (by design per defensive
    // unwrapping guidelines) — not testable in debug builds. The fallback-to-0 path is
    // only exercised in release builds.

    @Test("nonOptionalIndex set updates the underlying value")
    @MainActor func nonOptionalIndexSet() {
        let box = Box(0)
        box.binding.nonOptionalIndex.wrappedValue = 15
        #expect(box.value == 15)
    }

    @Test("nonOptionalIndex set overwrites existing value")
    @MainActor func nonOptionalIndexSetOverwrite() {
        let box = Box(10)
        box.binding.nonOptionalIndex.wrappedValue = 20
        #expect(box.value == 20)
    }

    @Test("nonOptionalIndex reflects changes in the underlying backing store")
    @MainActor func nonOptionalIndexReflectsChanges() {
        let box = Box(1)
        let binding = box.binding

        #expect(binding.nonOptionalIndex.wrappedValue == 1)

        box.value = 99
        #expect(binding.nonOptionalIndex.wrappedValue == 99)
    }

    // MARK: - Combined usage

    @Test("identifiableIndex and nonOptionalIndex share the same backing value")
    @MainActor func combinedUsage() {
        let box = Box(nil)
        let binding = box.binding

        // Set via identifiableIndex
        binding.identifiableIndex.wrappedValue = IdentifiableIndex(value: 8)
        #expect(binding.nonOptionalIndex.wrappedValue == 8)

        // Set via nonOptionalIndex
        binding.nonOptionalIndex.wrappedValue = 12
        #expect(binding.identifiableIndex.wrappedValue?.value == 12)
    }
}
