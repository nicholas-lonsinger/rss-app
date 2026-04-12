import SwiftUI

extension Binding {
    /// Returns a `Binding<Bool>` that is `true` when the wrapped optional is
    /// non-nil, and sets it to `nil` when assigned `false`. Assigning `true`
    /// has no effect; set the underlying optional to a non-nil value to trigger
    /// presentation.
    ///
    /// Use this to drive `isPresented:` parameters on alerts, sheets, and
    /// other SwiftUI modifiers from an optional state value:
    ///
    /// ```swift
    /// .alert("Error", isPresented: $errorMessage.isPresented()) { … }
    /// ```
    func isPresented<Wrapped>() -> Binding<Bool> where Value == Wrapped? {
        Binding<Bool>(
            get: { wrappedValue != nil },
            set: { if !$0 { wrappedValue = nil } }
        )
    }
}
