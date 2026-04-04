import Testing
@testable import RSSApp

@Suite("ModelValidation")
struct ModelValidationTests {

    @Test("valid model identifier passes validation and carries trimmed value")
    func validModel() {
        #expect(ModelValidation.validate("claude-haiku-4-5-20251001") == .valid("claude-haiku-4-5-20251001"))
    }

    @Test("valid model with simple name passes validation")
    func validModelSimple() {
        #expect(ModelValidation.validate("claude-sonnet-4-6") == .valid("claude-sonnet-4-6"))
    }

    @Test("empty string returns .empty")
    func emptyString() {
        #expect(ModelValidation.validate("") == .empty)
    }

    @Test("whitespace-only string returns .empty")
    func whitespaceOnly() {
        #expect(ModelValidation.validate("   ") == .empty)
    }

    @Test("model not starting with claude- is invalid")
    func missingPrefix() {
        let result = ModelValidation.validate("gpt-4")
        #expect(result == .invalid("Model ID must start with 'claude-'"))
    }

    @Test("model with uppercase characters is invalid")
    func uppercaseCharacters() {
        let result = ModelValidation.validate("claude-Sonnet-4")
        #expect(result == .invalid("Only lowercase letters, digits, and hyphens are allowed"))
    }

    @Test("model with spaces is invalid")
    func spacesInModel() {
        let result = ModelValidation.validate("claude- sonnet")
        #expect(result == .invalid("Only lowercase letters, digits, and hyphens are allowed"))
    }

    @Test("model with special characters is invalid")
    func specialCharacters() {
        let result = ModelValidation.validate("claude-sonnet_4")
        #expect(result == .invalid("Only lowercase letters, digits, and hyphens are allowed"))
    }

    @Test("model 'claude-' alone is valid")
    func claudeHyphenAlone() {
        // Technically starts with "claude-" and all characters valid, so passes client-side.
        // The API will reject it at runtime.
        #expect(ModelValidation.validate("claude-") == .valid("claude-"))
    }
}

@Suite("MaxTokensValidation")
struct MaxTokensValidationTests {

    @Test("valid positive integer passes validation and carries parsed value")
    func validNumber() {
        #expect(MaxTokensValidation.validate("4096") == .valid(4096))
    }

    @Test("1 is valid (minimum)")
    func minimumValue() {
        #expect(MaxTokensValidation.validate("1") == .valid(1))
    }

    @Test("large number is valid")
    func largeNumber() {
        #expect(MaxTokensValidation.validate("128000") == .valid(128000))
    }

    @Test("empty string returns .empty")
    func emptyString() {
        #expect(MaxTokensValidation.validate("") == .empty)
    }

    @Test("whitespace-only string returns .empty")
    func whitespaceOnly() {
        #expect(MaxTokensValidation.validate("   ") == .empty)
    }

    @Test("zero is invalid")
    func zeroValue() {
        #expect(MaxTokensValidation.validate("0") == .invalid("Must be at least 1"))
    }

    @Test("negative number is invalid")
    func negativeValue() {
        #expect(MaxTokensValidation.validate("-5") == .invalid("Must be at least 1"))
    }

    @Test("non-numeric string is invalid")
    func nonNumeric() {
        #expect(MaxTokensValidation.validate("abc") == .invalid("Must be a whole number"))
    }

    @Test("decimal number is invalid")
    func decimalNumber() {
        #expect(MaxTokensValidation.validate("40.96") == .invalid("Must be a whole number"))
    }
}
