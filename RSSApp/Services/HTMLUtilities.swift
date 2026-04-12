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

    /// Extracts the first `<img src="...">` URL from HTML content,
    /// skipping known tracking pixels and analytics beacons.
    static func extractFirstImageURL(from html: String) -> URL? {
        let pattern = ##/<img[^>]+src=["']([^"']+)["']/##
        for match in html.matches(of: pattern) {
            let src = String(match.1)
            if isTrackingPixelURL(src) {
                logger.debug("Skipping suspected tracking pixel URL: \(src, privacy: .public)")
                continue
            }
            return URL(string: src)
        }
        return nil
    }

    /// Returns `true` for URLs that are known tracking pixels or analytics beacons
    /// rather than actual content images. Matches specific path patterns to avoid
    /// false positives on legitimate URLs containing words like "pixel" or "track".
    private static func isTrackingPixelURL(_ urlString: String) -> Bool {
        // Medium read-tracking pixel
        if urlString.contains("/stat?event=") { return true }
        // Tracking pixel endpoints — require query string or file extension delimiter
        // to avoid false positives on paths like "/pixel-art/" or "/racetrack/"
        if urlString.contains("/pixel?") || urlString.contains("/pixel.") { return true }
        if urlString.contains("/track?") || urlString.contains("/track.") { return true }
        return false
    }

    /// Extracts the `og:image` URL from an HTML page's `<meta>` tags.
    /// When `baseURL` is provided, protocol-relative URLs (e.g., `//cdn.example.com/img.jpg`)
    /// are resolved against the base URL's scheme.
    static func extractOGImageURL(from html: String, baseURL: URL? = nil) -> URL? {
        // Match <meta property="og:image" content="..."> with either attribute order
        let pattern1 = ##/<meta\s[^>]*?property=["']og:image["'][^>]*?content=["']([^"']+)["']/##
            .ignoresCase()
        let pattern2 = ##/<meta\s[^>]*?content=["']([^"']+)["'][^>]*?property=["']og:image["']/##
            .ignoresCase()

        let rawValue: String?
        if let match = html.firstMatch(of: pattern1) {
            rawValue = String(match.1)
        } else if let match = html.firstMatch(of: pattern2) {
            rawValue = String(match.1)
        } else {
            rawValue = nil
        }

        guard let rawValue else { return nil }

        if let baseURL {
            return resolveURL(rawValue, base: baseURL)
        }
        return URL(string: rawValue)
    }

    /// Extracts icon URLs from HTML `<link>` tags, ordered by priority:
    /// apple-touch-icon → shortcut icon / icon.
    /// Relative hrefs are resolved against the provided base URL.
    static func extractIconURLs(from html: String, baseURL: URL) -> [URL] {
        let separated = extractIconURLsSeparated(from: html, baseURL: baseURL)
        return separated.appleTouchIcons + separated.linkIcons
    }

    /// The icon URLs extracted from `<link>` tags, split by source type.
    struct ExtractedIconURLs {
        /// URLs from `<link rel="apple-touch-icon">` tags.
        let appleTouchIcons: [URL]
        /// URLs from `<link rel="icon">` and `<link rel="shortcut icon">` tags.
        let linkIcons: [URL]
    }

    /// Extracts icon URLs from HTML `<link>` tags, separated by source type:
    /// `appleTouchIcons` for `rel="apple-touch-icon"`, `linkIcons` for `rel="icon"`.
    /// Relative hrefs are resolved against the provided base URL.
    static func extractIconURLsSeparated(from html: String, baseURL: URL) -> ExtractedIconURLs {
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

        return ExtractedIconURLs(appleTouchIcons: appleTouchIcons, linkIcons: linkIcons)
    }

    /// Extracts the first `<link rel="alternate" type="application/atom+xml" href="...">`
    /// URL from HTML. Relative hrefs are resolved against the provided base URL.
    ///
    /// Attribute order is ignored: the `<link>` tag is matched broadly, then `rel`,
    /// `type`, and `href` are inspected individually. A tag qualifies only when
    /// `rel` contains `alternate` (case-insensitive, whitespace-tolerant for
    /// compound values like `alternate stylesheet`) and `type` is exactly
    /// `application/atom+xml`. RSS alternates (`application/rss+xml`) and non-Atom
    /// `rel="alternate"` links are ignored.
    ///
    /// Returns the first match in document order. If the HTML contains multiple
    /// `<link rel="alternate" type="application/atom+xml">` entries (e.g. one
    /// per category), the first one wins.
    static func extractAtomAlternateURL(from html: String, baseURL: URL) -> URL? {
        let linkTagPattern = ##/<link\s[^>]*\/?>/##.ignoresCase()
        let relPattern = ##/\brel\s*=\s*["']([^"']*)["']/##.ignoresCase()
        let typePattern = ##/\btype\s*=\s*["']([^"']*)["']/##.ignoresCase()
        let hrefPattern = ##/\bhref\s*=\s*["']([^"']*)["']/##.ignoresCase()

        for tagMatch in html.matches(of: linkTagPattern) {
            let tag = String(tagMatch.0)

            guard let relMatch = tag.firstMatch(of: relPattern) else { continue }
            let relTokens = String(relMatch.1).lowercased().split(whereSeparator: { $0.isWhitespace })
            guard relTokens.contains("alternate") else { continue }

            guard let typeMatch = tag.firstMatch(of: typePattern) else { continue }
            guard String(typeMatch.1).lowercased() == "application/atom+xml" else { continue }

            guard let hrefMatch = tag.firstMatch(of: hrefPattern),
                  let url = resolveURL(String(hrefMatch.1), base: baseURL) else { continue }
            return url
        }
        return nil
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
