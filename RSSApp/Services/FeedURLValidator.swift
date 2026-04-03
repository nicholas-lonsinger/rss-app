import Foundation
import os

enum FeedURLValidationError: Error {
    case invalidURL
}

enum FeedURLValidator {

    private static let logger = Logger(category: "FeedURLValidator")

    /// Normalizes and validates a raw URL input string for feed subscription.
    /// Trims whitespace, prepends `https://` if no scheme is present, then validates
    /// that the URL has an HTTP/HTTPS scheme and a host.
    static func validate(_ input: String) -> Result<URL, FeedURLValidationError> {
        var trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty && !trimmed.contains("://") {
            trimmed = "https://" + trimmed
            logger.debug("Prepended https:// scheme: '\(trimmed)'")
        }

        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil else {
            return .failure(.invalidURL)
        }

        return .success(url)
    }
}
