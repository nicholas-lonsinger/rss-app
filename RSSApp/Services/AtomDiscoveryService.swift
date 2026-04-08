import Foundation
import os

/// HTTP data fetcher signature used by `AtomDiscoveryService`. Matches
/// `URLSession.data(from:)`, making the default wiring a one-liner while keeping
/// tests off the network without needing a URLProtocol subclass.
typealias AtomDiscoveryDataFetcher = @Sendable (URL) async throws -> (Data, URLResponse)

protocol AtomDiscovering: Sendable {
    /// Given an RSS feed URL, returns the URL of an Atom alternate feed advertised
    /// by the site's HTML `<link rel="alternate" type="application/atom+xml">`
    /// tag, or nil if none is found.
    ///
    /// Discovery is best-effort: any network, decoding, or parsing failure is
    /// treated as "no alternate available" and returns nil. Callers use this to
    /// *offer* a switch — they must proceed normally when nil is returned.
    ///
    /// Lookup strategy: the feed URL's containing directory is checked first
    /// (many sites publish category-specific Atom feeds under a subpath), then
    /// the site root as a fallback.
    func discoverAtomAlternate(forFeedAt feedURL: URL) async -> URL?
}

struct AtomDiscoveryService: AtomDiscovering {

    private static let logger = Logger(category: "AtomDiscoveryService")

    private let fetchData: AtomDiscoveryDataFetcher

    init(fetchData: @escaping AtomDiscoveryDataFetcher = { url in
        try await URLSession.shared.data(from: url)
    }) {
        self.fetchData = fetchData
    }

    func discoverAtomAlternate(forFeedAt feedURL: URL) async -> URL? {
        Self.logger.debug("discoverAtomAlternate() called for \(feedURL.absoluteString, privacy: .public)")

        let subfolder = Self.subfolderURL(for: feedURL)
        let root = Self.rootURL(for: feedURL)

        // Try the feed's own containing directory first — sites that publish
        // category-specific feeds often advertise the matching Atom alternate
        // on the same page the RSS feed lives under.
        if let subfolder,
           let candidate = await tryFetchAtom(at: subfolder, originalFeedURL: feedURL) {
            return candidate
        }

        // Fall back to the site root. Skip this step if root == subfolder —
        // we already tried that URL and don't want to pay for a duplicate fetch.
        if let root, root != subfolder,
           let candidate = await tryFetchAtom(at: root, originalFeedURL: feedURL) {
            return candidate
        }

        Self.logger.debug("No Atom alternate found for \(feedURL.absoluteString, privacy: .public)")
        return nil
    }

    private func tryFetchAtom(at pageURL: URL, originalFeedURL: URL) async -> URL? {
        // RATIONALE: Discovery is best-effort per the feature spec — any failure
        // (non-2xx status, decode error, network error, task cancellation)
        // returns nil so the caller proceeds with the RSS feed as-is. Expected
        // failure paths (HTTP 4xx from subfolder probes, URLError from flaky
        // networks, cancellation from sheet dismissal) log at `.debug` so they
        // do not spam the persisted warning tier.
        do {
            let (data, response) = try await fetchData(pageURL)

            guard let http = response as? HTTPURLResponse else {
                Self.logger.warning("Response is not HTTPURLResponse for \(pageURL.absoluteString, privacy: .public)")
                return nil
            }
            guard (200..<300).contains(http.statusCode) else {
                Self.logger.debug("HTTP \(http.statusCode, privacy: .public) for \(pageURL.absoluteString, privacy: .public)")
                return nil
            }

            // HTML pages in the wild frequently declare non-UTF-8 encodings, but
            // the `<link rel="alternate">` tags we care about are ASCII-safe. Fall
            // back to ISO-Latin-1 so we still find the tag even if the page body
            // contains bytes that aren't valid UTF-8.
            guard let html = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1) else {
                Self.logger.warning("Unable to decode HTML for \(pageURL.absoluteString, privacy: .public)")
                return nil
            }

            guard let candidate = HTMLUtilities.extractAtomAlternateURL(from: html, baseURL: pageURL) else {
                return nil
            }

            // If the discovered URL is the same one the user already entered,
            // there is nothing to switch to — treat as "no alternate".
            if candidate == originalFeedURL {
                Self.logger.debug("Discovered Atom URL matches feed URL — no switch to offer")
                return nil
            }

            Self.logger.notice("Discovered Atom alternate \(candidate.absoluteString, privacy: .public) via \(pageURL.absoluteString, privacy: .public)")
            return candidate
        } catch is CancellationError {
            Self.logger.debug("Atom discovery cancelled for \(pageURL.absoluteString, privacy: .public)")
            return nil
        } catch let urlError as URLError where urlError.code == .cancelled {
            Self.logger.debug("Atom discovery cancelled for \(pageURL.absoluteString, privacy: .public)")
            return nil
        } catch {
            Self.logger.debug("Atom discovery fetch failed for \(pageURL.absoluteString, privacy: .public): \(error, privacy: .public)")
            return nil
        }
    }

    // MARK: - URL Utilities

    /// Returns the HTML-page URL to probe for `<link rel="alternate">` tags,
    /// derived from a feed URL. Preserves scheme/host and strips query/fragment.
    ///
    /// If the feed URL already represents a directory (path ends with `/`),
    /// it is kept as-is on the assumption that it points at an HTML listing.
    /// Otherwise, the last path component is stripped so we land on the
    /// containing directory — for file-style feed URLs the file itself
    /// serves XML, not HTML, so we need its parent to find `<link>` tags.
    ///
    /// Examples:
    /// - `https://example.com/blog/feed.xml` → `https://example.com/blog/`
    /// - `https://example.com/feed` → `https://example.com/`
    /// - `https://example.com/blog/` → `https://example.com/blog/`
    /// - `https://example.com/` → `https://example.com/`
    static func subfolderURL(for url: URL) -> URL? {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.query = nil
        components?.fragment = nil
        guard let path = components?.path, !path.isEmpty else {
            return rootURL(for: url)
        }

        // Directory paths (trailing slash) are already the target — leave
        // them alone. Only file-style paths need the last component stripped.
        if !path.hasSuffix("/") {
            if let lastSlash = path.lastIndex(of: "/") {
                components?.path = String(path[path.startIndex...lastSlash])
            } else {
                components?.path = "/"
            }
        }
        return components?.url
    }

    /// Returns the site root — same scheme/host with path `/` and no query/fragment.
    static func rootURL(for url: URL) -> URL? {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.path = "/"
        components?.query = nil
        components?.fragment = nil
        return components?.url
    }
}
