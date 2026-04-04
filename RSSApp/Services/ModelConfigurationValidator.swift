import Foundation

enum ModelValidation: Equatable {
    case valid(String)
    case empty
    case invalid(String)

    /// Pattern: lowercase alphanumeric characters, hyphens, and digits.
    private static let validCharacterSet = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-")

    static func validate(_ input: String) -> ModelValidation {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .empty }
        if !trimmed.hasPrefix("claude-") {
            return .invalid("Model ID must start with 'claude-'")
        }
        if trimmed.unicodeScalars.contains(where: { !validCharacterSet.contains($0) }) {
            return .invalid("Only lowercase letters, digits, and hyphens are allowed")
        }
        return .valid(trimmed)
    }
}

enum MaxTokensValidation: Equatable {
    case valid(Int)
    case empty
    case invalid(String)

    static func validate(_ input: String) -> MaxTokensValidation {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .empty }
        guard let value = Int(trimmed) else {
            return .invalid("Must be a whole number")
        }
        if value < 1 {
            return .invalid("Must be at least 1")
        }
        return .valid(value)
    }
}
