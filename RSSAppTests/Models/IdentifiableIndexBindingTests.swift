import SwiftUI
import Testing
@testable import RSSApp

@Suite("Binding<Int?> Extension Tests")
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

    // MARK: - isNotNil

    @Test("isNotNil returns false when underlying value is nil")
    @MainActor func isNotNilReturnsFalseWhenNil() {
        let box = Box(nil)
        #expect(box.binding.isNotNil.wrappedValue == false)
    }

    @Test("isNotNil returns true when underlying value is non-nil")
    @MainActor func isNotNilReturnsTrueWhenNonNil() {
        let box = Box(5)
        #expect(box.binding.isNotNil.wrappedValue == true)
    }

    @Test("isNotNil set false clears the underlying value to nil")
    @MainActor func isNotNilSetFalseClearsValue() {
        let box = Box(10)
        box.binding.isNotNil.wrappedValue = false
        #expect(box.value == nil)
    }

    @Test("isNotNil set true when already non-nil preserves the value")
    @MainActor func isNotNilSetTruePreservesValue() {
        let box = Box(7)
        box.binding.isNotNil.wrappedValue = true
        #expect(box.value == 7)
    }

    @Test("isNotNil reflects changes in the underlying backing store")
    @MainActor func isNotNilReflectsChanges() {
        let box = Box(nil)
        let binding = box.binding

        #expect(binding.isNotNil.wrappedValue == false)

        box.value = 42
        #expect(binding.isNotNil.wrappedValue == true)

        box.value = nil
        #expect(binding.isNotNil.wrappedValue == false)
    }

    // MARK: - Combined usage

    @Test("isNotNil integrates with nonOptionalIndex for push navigation pattern")
    @MainActor func isNotNilWithNonOptionalIndex() {
        let box = Box(nil)
        let binding = box.binding

        // Simulate selecting an article
        box.value = 3
        #expect(binding.isNotNil.wrappedValue == true)
        #expect(binding.nonOptionalIndex.wrappedValue == 3)

        // Simulate navigating to next article via nonOptionalIndex
        binding.nonOptionalIndex.wrappedValue = 4
        #expect(box.value == 4)
        #expect(binding.isNotNil.wrappedValue == true)

        // Simulate dismissing the reader (clearing selection)
        binding.isNotNil.wrappedValue = false
        #expect(box.value == nil)
    }

    // isNotNil set true when underlying value is nil triggers assertionFailure (by design
    // per defensive unwrapping guidelines) — not testable in debug builds. The no-op path
    // is only exercised in release builds.
}
