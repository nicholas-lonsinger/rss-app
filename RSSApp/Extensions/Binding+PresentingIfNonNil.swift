import SwiftUI

extension Binding where Value == Bool {

    /// Creates a `Binding<Bool>` that is `true` when `optional` holds a non-nil value,
    /// and sets the optional to `nil` when the binding is set to `false`.
    ///
    /// Use this to adapt an `Optional` state property to SwiftUI's
    /// `.alert(isPresented:)` modifier:
    ///
    /// ```swift
    /// .alert("Error", isPresented: Binding(presentingIfNonNil: $errorMessage)) {
    ///     Button("OK", role: .cancel) {}
    /// } message: {
    ///     Text(errorMessage ?? "")
    /// }
    /// ```
    ///
    /// Writing `true` through this binding is a no-op — the optional is never
    /// populated from the outside. Alert buttons that only need to dismiss the
    /// alert require no explicit action: the binding's `set` closure clears the
    /// optional automatically when SwiftUI sets the binding to `false` on
    /// dismissal.
    init<Wrapped>(presentingIfNonNil optional: Binding<Wrapped?>) {
        self.init(
            get: { optional.wrappedValue != nil },
            set: { if !$0 { optional.wrappedValue = nil } }
        )
    }
}
