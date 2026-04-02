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

    /// Escapes special characters for use in HTML text content.
    static func escapeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    /// Escapes special characters for use in an HTML/XML attribute value.
    static func escapeAttribute(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    /// Extracts the first `<img src="...">` URL from HTML content.
    static func extractFirstImageURL(from html: String) -> URL? {
        guard let match = html.firstMatch(of: ##/<img[^>]+src=["']([^"']+)["']/##) else {
            return nil
        }
        return URL(string: String(match.1))
    }

    /// Extracts icon URLs from HTML `<link>` tags, ordered by priority:
    /// apple-touch-icon → shortcut icon / icon.
    /// Relative hrefs are resolved against the provided base URL.
    static func extractIconURLs(from html: String, baseURL: URL) -> [URL] {
        var appleTouchIcons: [URL] = []
        var linkIcons: [URL] = []

        // Match <link rel="..." href="..."> — case-insensitive, tolerates attribute order
        let linkPattern = ##/<link\s[^>]*?rel=["']([^"']+)["'][^>]*?href=["']([^"']+)["'][^>]*?\/?>/##
            .ignoresCase()
        let linkPatternReversed = ##/<link\s[^>]*?href=["']([^"']+)["'][^>]*?rel=["']([^"']+)["'][^>]*?\/?>/##
            .ignoresCase()

        for match in html.matches(of: linkPattern) {
            let rel = String(match.1).lowercased()
            let href = String(match.2)
            if let url = resolveURL(href, base: baseURL) {
                if rel.contains("apple-touch-icon") {
                    appleTouchIcons.append(url)
                } else if rel.contains("icon") {
                    linkIcons.append(url)
                }
            }
        }

        for match in html.matches(of: linkPatternReversed) {
            let href = String(match.1)
            let rel = String(match.2).lowercased()
            if let url = resolveURL(href, base: baseURL) {
                if rel.contains("apple-touch-icon") {
                    appleTouchIcons.append(url)
                } else if rel.contains("icon") {
                    linkIcons.append(url)
                }
            }
        }

        return appleTouchIcons + linkIcons
    }

    private static func resolveURL(_ href: String, base: URL) -> URL? {
        // Decode HTML entities (e.g., &amp; → &) that appear in attribute values
        let decoded = href
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")

        // Protocol-relative URLs (//cdn.example.com/icon.png)
        if decoded.hasPrefix("//") {
            return URL(string: "\(base.scheme ?? "https"):\(decoded)")
        }
        // Absolute URLs
        if decoded.hasPrefix("http://") || decoded.hasPrefix("https://") {
            return URL(string: decoded)
        }
        // Relative URLs
        return URL(string: decoded, relativeTo: base)?.absoluteURL
    }
}
