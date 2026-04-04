import Foundation
@testable import RSSApp

// RATIONALE: @unchecked Sendable is safe because this mock is only used in
// single-threaded test contexts where properties are set before the async call.
final class MockKeychainService: KeychainServicing, @unchecked Sendable {
    private var store: [String: String] = [:]
    var errorToThrow: (any Error)?

    func save(_ value: String, for account: String) throws {
        if let error = errorToThrow { throw error }
        store[account] = value
    }

    func load(for account: String) -> String? {
        store[account]
    }

    func delete(for account: String) {
        store.removeValue(forKey: account)
    }
}
