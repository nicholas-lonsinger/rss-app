import Foundation
import os

enum HTMLUtilities {

    private static let logger = Logger(category: "HTMLUtilities")

    /// Decodes HTML character references (numeric and named) in a string.
    ///
    /// Uses a single-pass approach so that decoded output is never re-examined,
    /// preventing over-decoding of sequences like `&#38;lt;` → `&lt;` (not `<`).
    /// Handles decimal (`&#8217;`), hexadecimal (`&#x2019;`), and common named
    /// entities (`&amp;`, `&lt;`, `&gt;`, `&quot;`, `&apos;`, `&nbsp;`).
    static func decodeHTMLEntities(_ string: String) -> String {
        guard string.contains("&") else { return string }

        return string.replacing(#/&(#x[0-9A-Fa-f]+|#[0-9]+|[A-Za-z0-9]+);/#) { match in
            let ref = String(match.1)
            if ref.hasPrefix("#x") || ref.hasPrefix("#X") {
                if let codePoint = UInt32(ref.dropFirst(2), radix: 16),
                   let scalar = Unicode.Scalar(codePoint) {
                    return String(Character(scalar))
                }
                // RATIONALE: Invalid Unicode scalars (surrogates, out-of-range) have no valid
                // character — pass through the raw entity so the user sees the publisher's original text.
                logger.warning("Invalid hex entity '\(String(match.0), privacy: .public)' — passing through unchanged")
            } else if ref.hasPrefix("#") {
                if let codePoint = UInt32(ref.dropFirst()),
                   let scalar = Unicode.Scalar(codePoint) {
                    return String(Character(scalar))
                }
                logger.warning("Invalid decimal entity '\(String(match.0), privacy: .public)' — passing through unchanged")
            } else {
                switch ref {
                case "amp": return "&"
                case "lt": return "<"
                case "gt": return ">"
                case "quot": return "\""
                case "apos": return "'"
                case "nbsp": return " "
                default: break
                }
            }
            return String(match.0)
        }
    }

    /// Strips HTML tags and decodes entities, returning plain text.
    static func stripHTML(_ html: String) -> String {
        var result = html

        // Remove HTML tags
        result = result.replacing(#/<[^>]+>/#, with: "")

        // Decode HTML entities
        result = decodeHTMLEntities(result)

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

    /// Extracts the `og:image` URL from an HTML page's `<meta>` tags.
    static func extractOGImageURL(from html: String) -> URL? {
        // Match <meta property="og:image" content="..."> with either attribute order
        let pattern1 = ##/<meta\s[^>]*?property=["']og:image["'][^>]*?content=["']([^"']+)["']/##
            .ignoresCase()
        let pattern2 = ##/<meta\s[^>]*?content=["']([^"']+)["'][^>]*?property=["']og:image["']/##
            .ignoresCase()

        if let match = html.firstMatch(of: pattern1) {
            return URL(string: String(match.1))
        }
        if let match = html.firstMatch(of: pattern2) {
            return URL(string: String(match.1))
        }
        return nil
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
        let decoded = decodeHTMLEntities(href)

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
