import os
import SwiftUI

// MARK: - Binding Helpers

extension Binding where Value == Int? {
    private static let logger = Logger(category: "IdentifiableIndex+Binding")

    /// Provides a non-optional `Int` binding for use while an article reader is presented,
    /// where a nil value should never occur. In debug builds, a nil read triggers an assertion
    /// failure; in release builds, it logs at fault level and falls back to 0.
    var nonOptionalIndex: Binding<Int> {
        Binding<Int>(
            get: {
                guard let index = wrappedValue else {
                    Self.logger.fault("nonOptionalIndex read while underlying value is nil")
                    assertionFailure("nonOptionalIndex read while underlying value is nil")
                    // RATIONALE: This path is unreachable during normal operation because
                    // the article reader is only presented when the underlying Int? is non-nil.
                    // During pop-animation teardown, SwiftUI may briefly read this binding
                    // after isNotNil has cleared the value; the fallback to 0 prevents a crash.
                    // ArticleReaderView.article has its own bounds check as defense-in-depth.
                    return 0
                }
                return index
            },
            set: { wrappedValue = $0 }
        )
    }

    /// Provides a `Bool` binding that is `true` when the underlying optional is non-nil.
    /// Setting to `false` clears the underlying value to `nil`; setting to `true` when
    /// already non-nil has no effect (the value is already present). Setting to `true` when
    /// the underlying value is nil is a programming error (the value must be set via a direct
    /// write, not via this binding) and triggers an assertion failure in debug builds.
    /// Used with `navigationDestination(isPresented:)` for push navigation.
    var isNotNil: Binding<Bool> {
        Binding<Bool>(
            get: { wrappedValue != nil },
            set: {
                if !$0 {
                    wrappedValue = nil
                } else if wrappedValue == nil {
                    Self.logger.fault("isNotNil set to true while underlying value is nil — no-op")
                    assertionFailure("isNotNil set to true while underlying value is nil")
                }
            }
        )
    }
}
