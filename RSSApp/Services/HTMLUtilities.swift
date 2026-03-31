import Foundation

enum HTMLUtilities {

    /// Strips HTML tags and decodes common entities, returning plain text.
    static func stripHTML(_ html: String) -> String {
        var result = html

        // Remove HTML tags
        result = result.replacing(#/<[^>]+>/#, with: "")

        // Decode common HTML entities
        let entities: [(String, String)] = [
            ("&amp;", "&"),
            ("&lt;", "<"),
            ("&gt;", ">"),
            ("&quot;", "\""),
            ("&#39;", "'"),
            ("&apos;", "'"),
            ("&nbsp;", " "),
        ]
        for (entity, replacement) in entities {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }

        // Collapse multiple whitespace characters into a single space
        result = result.replacing(#/\s+/#, with: " ")

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Extracts the first `<img src="...">` URL from HTML content.
    static func extractFirstImageURL(from html: String) -> URL? {
        guard let match = html.firstMatch(of: ##/<img[^>]+src=["']([^"']+)["']/##) else {
            return nil
        }
        return URL(string: String(match.1))
    }
}
