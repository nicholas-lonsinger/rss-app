import os
import SwiftUI

/// A lightweight wrapper that makes an integer index `Identifiable`, enabling its use
/// with SwiftUI's `fullScreenCover(item:)` and similar APIs that require `Identifiable` bindings.
struct IdentifiableIndex: Identifiable {
    let value: Int
    var id: Int { value }
}

// MARK: - Binding Helpers

extension Binding where Value == Int? {
    private static let logger = Logger(category: "IdentifiableIndex+Binding")

    /// Wraps an optional `Int` binding as an `IdentifiableIndex?` binding
    /// for use with `fullScreenCover(item:)`.
    var identifiableIndex: Binding<IdentifiableIndex?> {
        Binding<IdentifiableIndex?>(
            get: { wrappedValue.map { IdentifiableIndex(value: $0) } },
            set: { wrappedValue = $0?.value }
        )
    }

    /// Provides a non-optional `Int` binding that defaults to 0 when the underlying
    /// value is nil. Intended for use while a full-screen cover is presented, where
    /// a nil value should never occur.
    var nonOptionalIndex: Binding<Int> {
        Binding<Int>(
            get: {
                guard let index = wrappedValue else {
                    Self.logger.fault("nonOptionalIndex read while underlying value is nil")
                    assertionFailure("nonOptionalIndex read while underlying value is nil")
                    return 0
                }
                return index
            },
            set: { wrappedValue = $0 }
        )
    }
}
