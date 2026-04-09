import Foundation

extension URL {

    /// Derives a site root URL by stripping the path, query, and fragment
    /// (e.g. `https://example.com/feed/rss` -> `https://example.com`).
    /// Returns `nil` when the receiver has no host component.
    var siteRoot: URL? {
        guard let host = host(percentEncoded: false), !host.isEmpty else { return nil }
        return URL(string: "\(scheme ?? "https")://\(host)")
    }
}
