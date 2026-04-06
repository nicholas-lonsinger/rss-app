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

    /// Provides a non-optional `Int` binding for use while a full-screen cover is presented,
    /// where a nil value should never occur. In debug builds, a nil read triggers an assertion
    /// failure; in release builds, it logs at fault level and falls back to 0.
    var nonOptionalIndex: Binding<Int> {
        Binding<Int>(
            get: {
                guard let index = wrappedValue else {
                    Self.logger.fault("nonOptionalIndex read while underlying value is nil")
                    assertionFailure("nonOptionalIndex read while underlying value is nil")
                    // RATIONALE: This path is unreachable during normal operation because
                    // fullScreenCover(item:) only presents when the underlying Int? is non-nil.
                    // If reached, 0 is always a valid index for a non-empty articles array, and
                    // ArticleReaderView.article has its own bounds check as defense-in-depth.
                    return 0
                }
                return index
            },
            set: { wrappedValue = $0 }
        )
    }
}
