import Foundation

/// A lightweight wrapper that makes an integer index `Identifiable`, enabling its use
/// with SwiftUI's `fullScreenCover(item:)` and similar APIs that require `Identifiable` bindings.
struct IdentifiableIndex: Identifiable {
    let value: Int
    var id: Int { value }
}
