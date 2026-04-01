import Foundation

/// Extensibility protocol for per-hostname content extractors.
///
/// Implement this protocol to add site-specific extraction logic for sites
/// where the generic scoring algorithm doesn't work well. Register implementations
/// with `ContentExtractor` — they are checked before the generic algorithm runs.
///
/// Adding support for a new site = one new conforming type.
protocol SiteSpecificExtracting: Sendable {
    /// Returns `true` if this extractor handles the given hostname.
    func canHandle(hostname: String) -> Bool

    /// Extracts content using site-specific logic.
    ///
    /// Return `nil` to fall through to the generic extractor.
    func extract(from dom: SerializedDOM) -> ArticleContent?
}
