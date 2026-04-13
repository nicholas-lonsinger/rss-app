import Foundation
import os
import UIKit

// MARK: - Result Types

/// The background tile color that best contrasts against a cached icon's opaque
/// pixels. Persisted per-feed on `PersistentFeed` (via `iconBackgroundStyleRaw`)
/// so `FeedIconView` can render the right tile without re-analyzing the image
/// on every display (issue #342).
///
/// - `light`: icon is predominantly dark — render a light (white) tile so the
///   icon's dark strokes stay visible where the PNG has transparency.
/// - `dark`: icon is predominantly light — render a dark (black) tile so
///   white-on-transparent icons (e.g. Apple Insider) stay visible.
enum FeedIconBackgroundStyle: String, Sendable, Equatable {
    case light
    case dark
}

/// The source type of an icon candidate, used to apply a type-specific bonus
/// during suitability scoring. Apple-touch-icon and feed XML icons are designed
/// for small-size display and receive a higher bonus than generic HTML link icons
/// or social share banners (og:image).
enum IconCandidateType: Sendable, Equatable {
    /// Image URL from the feed's own XML `<image>` element.
    case feedXML
    /// `<meta property="og:image">` from the site homepage — often a social share
    /// banner (1200×630) rather than a compact logo.
    case ogImage
    /// `<link rel="apple-touch-icon">` — designed for home-screen display;
    /// strongly prefer these when available.
    case appleTouchIcon
    /// `<link rel="icon">` or `<link rel="shortcut icon">` from the site HTML.
    case linkIcon
    /// `/favicon.ico` fallback (original host or redirected host).
    case faviconICO
}

// MARK: - Protocol

protocol FeedIconResolving: Sendable {

    /// Returns candidate icon URLs from multiple sources in priority order:
    /// feed XML image → og:image → site HTML link tags → original-host /favicon.ico →
    /// redirected-host /favicon.ico (when a cross-domain redirect occurred).
    /// Callers should try each URL until one successfully downloads.
    func resolveIconCandidates(feedSiteURL: URL?, feedImageURL: URL?) async -> [URL]

    /// Downloads the image at `remoteURL`, normalizes it to PNG, and caches it
    /// to disk under the feed's UUID. Returns the background-style
    /// classification on success, or `nil` on failure (download error, decode
    /// failure, or no visible content). When luminance analysis could not run
    /// (e.g. CGContext allocation failure) the image is still cached and a
    /// neutral default (`.dark` → black tile) is returned so callers don't
    /// drop an otherwise-valid icon.
    func cacheIcon(from remoteURL: URL, feedID: UUID) async -> FeedIconBackgroundStyle?

    /// Returns the local file URL for a cached icon, or `nil` if not cached.
    func cachedIconFileURL(for feedID: UUID) -> URL?

    /// Loads the cached icon for `feedID` off the main actor, decoding the PNG on disk,
    /// verifying it has visible content, and deleting the file (with a warning log)
    /// if it is unreadable or fully transparent. Returns `nil` when no cached icon
    /// exists, or when the cached file failed validation and was removed.
    ///
    /// This is the preferred entry point for UI layers that need to display a cached
    /// icon — it centralizes the decode + validity gate + delete-on-corrupt pipeline
    /// so the invariant is enforced once, at the service boundary.
    func loadValidatedIcon(for feedID: UUID) async -> UIImage?

    /// Resolves candidate icon URLs, downloads them concurrently, scores each by
    /// suitability for small-size display (aspect ratio, dimensions, source type),
    /// and caches the highest-scoring candidate.
    ///
    /// **Fast path:** if the feed XML image downloads and passes a minimum quality
    /// threshold (square-ish aspect ratio, not oversized), it is used immediately
    /// without evaluating the remaining candidates.
    ///
    /// Returns the remote URL of the cached icon along with the luminance-based
    /// background-style classification, or `nil` when no candidate could be cached.
    func resolveAndCacheIcon(feedSiteURL: URL?, feedImageURL: URL?, feedID: UUID) async -> (url: URL, backgroundStyle: FeedIconBackgroundStyle)?

    /// Classifies the background style of an already-cached icon without
    /// touching the network. Used to back-fill `FeedIconBackgroundStyle` for
    /// feeds that were cached before the classifier existed (issue #342).
    /// Returns `nil` when no cached icon exists or the file cannot be decoded.
    func classifyCachedIconBackgroundStyle(for feedID: UUID) async -> FeedIconBackgroundStyle?

    /// Deletes the cached icon file for the given feed.
    func deleteCachedIcon(for feedID: UUID)
}

// MARK: - Miss Tracker

/// Tracks consecutive icon-resolution misses per feed so `FeedIconService` can
/// escalate log level to `.warning` (persisted to disk) after a feed
/// chronically fails to resolve an icon. The counter resets to zero whenever a
/// feed successfully caches an icon, so transient failures (network blip,
/// temporary CDN 403) don't accumulate toward the threshold.
///
/// State is in-memory only — it resets on app launch, which is acceptable
/// because the failure conditions are typically transient across sessions and
/// the persisted `.warning` logs are sufficient for post-mortem diagnosis.
actor FeedIconMissTracker {

    /// Number of consecutive resolution misses after which a `.warning` log is
    /// emitted instead of `.debug`. Three misses covers roughly one day of
    /// background refreshes (every ~6–8 hours) before logging persistently.
    static let missThreshold = 3

    /// Shared instance used by all production `FeedIconService` instances.
    static let shared = FeedIconMissTracker()

    private var missCounters: [UUID: Int] = [:]

    /// Increments the miss counter for `feedID` and returns the new count.
    func recordMiss(for feedID: UUID) -> Int {
        let count = (missCounters[feedID] ?? 0) + 1
        missCounters[feedID] = count
        return count
    }

    /// Resets the miss counter for `feedID` after a successful icon cache.
    func recordSuccess(for feedID: UUID) {
        missCounters.removeValue(forKey: feedID)
    }
}

// MARK: - Resolution Coordinator

/// Coalesces concurrent `resolveAndCacheIcon` requests for the same feed.
/// The first caller for a given `feedID` creates the actual resolution task;
/// subsequent callers await the same task instead of starting redundant network
/// requests. The entry is removed once the task completes, so future requests
/// (after cache invalidation, icon deletion, etc.) resolve fresh.
actor FeedIconResolutionCoordinator {

    static let shared = FeedIconResolutionCoordinator()

    private static let logger = Logger(category: "FeedIconResolutionCoordinator")

    private var inFlight: [UUID: Task<(url: URL, backgroundStyle: FeedIconBackgroundStyle)?, Never>] = [:]

    /// If a resolution for `feedID` is already in progress, awaits and returns
    /// its result. Otherwise starts `work` and shares the result with all
    /// concurrent callers for the same `feedID`.
    ///
    /// When multiple callers arrive concurrently, only the first caller's `work`
    /// closure is executed; subsequent callers' `work` closures are never called —
    /// they receive the result from the first caller's closure instead.
    ///
    /// This works because `await task.value` suspends the actor, allowing
    /// subsequent callers to enter `coalesce` and find the existing in-flight
    /// entry before the first task completes. Callers that arrive after the task
    /// finishes (and the entry is removed) start a fresh resolution.
    func coalesce(
        feedID: UUID,
        work: @Sendable @escaping () async -> (url: URL, backgroundStyle: FeedIconBackgroundStyle)?
    ) async -> (url: URL, backgroundStyle: FeedIconBackgroundStyle)? {
        if let existing = inFlight[feedID] {
            Self.logger.debug(
                "Coalescing icon resolution for feed \(feedID.uuidString, privacy: .public) — awaiting in-flight task"
            )
            return await existing.value
        }

        let task = Task<(url: URL, backgroundStyle: FeedIconBackgroundStyle)?, Never> {
            await work()
        }
        inFlight[feedID] = task
        let result = await task.value
        inFlight.removeValue(forKey: feedID)
        return result
    }
}

// MARK: - Implementation

struct FeedIconService: FeedIconResolving {

    private static let logger = Logger(category: "FeedIconService")

    private static let iconCacheDirectoryName = "feed-icons"
    private static let htmlFetchTimeout: TimeInterval = 10
    private static let iconFetchTimeout: TimeInterval = 15

    /// Safety cap for the HTML `<head>` read. We stream bytes until we find
    /// `</head>` (case-insensitive), but stop at this limit if the closing tag
    /// is absent or the head is abnormally large.
    private static let htmlHeadMaxBytes = 512_000 // 500 KB
    private static let maxIconDimension: CGFloat = 128

    /// Maximum number of candidates downloaded concurrently and scored for suitability.
    /// Limits network activity when many link icons are present while still covering the
    /// most likely good sources (feed XML, og:image, apple-touch-icon, link icon, favicon).
    static let maxCandidatesForScoring = 5

    /// Optional override for the on-disk cache directory. When `nil`, the service writes to
    /// `<Caches>/feed-icons` (production default). Tests can pass a unique temporary directory
    /// to isolate cache files and avoid leaking fixture data into the real user caches directory
    /// on crash. See `FeedIconServiceTests` for the test-side helper.
    private let cacheDirectoryOverride: URL?

    /// Tracks consecutive resolution misses per feed to decide when to escalate
    /// from `.debug` to `.warning` logging. Defaults to the shared app-wide
    /// instance; tests inject a dedicated instance for isolation.
    private let missTracker: FeedIconMissTracker

    /// Coalesces concurrent `resolveAndCacheIcon` requests for the same feed so
    /// multiple concurrent callers (e.g. several `FeedIconView`s for the same feed)
    /// share one in-flight network request instead of each starting their own.
    /// Defaults to a shared app-wide instance; tests inject a dedicated instance
    /// for isolation.
    private let resolutionCoordinator: FeedIconResolutionCoordinator

    init(
        cacheDirectoryOverride: URL? = nil,
        missTracker: FeedIconMissTracker = .shared,
        resolutionCoordinator: FeedIconResolutionCoordinator = .shared
    ) {
        self.cacheDirectoryOverride = cacheDirectoryOverride
        self.missTracker = missTracker
        self.resolutionCoordinator = resolutionCoordinator
    }

    // MARK: - FeedIconResolving

    func resolveIconCandidates(feedSiteURL: URL?, feedImageURL: URL?) async -> [URL] {
        Self.logger.debug("resolveIconCandidates() feedImageURL=\(feedImageURL?.absoluteString ?? "nil", privacy: .public) siteURL=\(feedSiteURL?.absoluteString ?? "nil", privacy: .public)")

        // Fetch site homepage HTML and extract icon sources
        var htmlResult: HTMLIconResult?
        if let siteURL = feedSiteURL {
            htmlResult = await resolveFromHTML(siteURL: siteURL)
        }

        let candidates = Self.assembleCandidates(
            feedSiteURL: feedSiteURL,
            feedImageURL: feedImageURL,
            htmlResult: htmlResult
        )

        Self.logger.debug("Found \(candidates.count, privacy: .public) icon candidates")
        return candidates
    }

    func cacheIcon(from remoteURL: URL, feedID: UUID) async -> FeedIconBackgroundStyle? {
        Self.logger.debug("cacheIcon() from \(remoteURL.absoluteString, privacy: .public) for feed \(feedID.uuidString, privacy: .public)")

        guard let (image, stats) = await downloadAndAnalyze(url: remoteURL, feedID: feedID) else {
            return nil
        }
        return await writeNormalizedIcon(image: image, stats: stats, from: remoteURL, feedID: feedID)
    }

    func cachedIconFileURL(for feedID: UUID) -> URL? {
        let fileURL = iconFileURL(for: feedID)
        return FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) ? fileURL : nil
    }

    func loadValidatedIcon(for feedID: UUID) async -> UIImage? {
        guard let fileURL = cachedIconFileURL(for: feedID) else {
            Self.logger.debug("No cached icon for feed \(feedID.uuidString, privacy: .public) — awaiting next refresh")
            return nil
        }
        return await Task.detached(priority: .userInitiated) { () -> UIImage? in
            guard let image = UIImage(contentsOfFile: fileURL.path(percentEncoded: false)) else {
                Self.logger.warning("Cached icon file unreadable for feed \(feedID.uuidString, privacy: .public) at \(fileURL.path, privacy: .public) — deleting")
                self.deleteCachedIcon(for: feedID)
                return nil
            }
            guard Self.hasVisibleContent(image) else {
                Self.logger.warning("Cached icon for feed \(feedID.uuidString, privacy: .public) has no visible content — deleting")
                self.deleteCachedIcon(for: feedID)
                return nil
            }
            return image
        }.value
    }

    func resolveAndCacheIcon(feedSiteURL: URL?, feedImageURL: URL?, feedID: UUID) async -> (url: URL, backgroundStyle: FeedIconBackgroundStyle)? {
        await resolutionCoordinator.coalesce(feedID: feedID) { [self] in
            await self.performResolveAndCacheIcon(
                feedSiteURL: feedSiteURL,
                feedImageURL: feedImageURL,
                feedID: feedID
            )
        }
    }

    private func performResolveAndCacheIcon(feedSiteURL: URL?, feedImageURL: URL?, feedID: UUID) async -> (url: URL, backgroundStyle: FeedIconBackgroundStyle)? {
        Self.logger.debug("resolveAndCacheIcon() for feed \(feedID.uuidString, privacy: .public)")

        // Fetch site HTML to discover link icons
        var htmlResult: HTMLIconResult?
        if let siteURL = feedSiteURL {
            htmlResult = await resolveFromHTML(siteURL: siteURL)
        }

        let typedCandidates = Self.assembleTypedCandidates(
            feedSiteURL: feedSiteURL,
            feedImageURL: feedImageURL,
            htmlResult: htmlResult
        )

        guard !typedCandidates.isEmpty else {
            Self.logger.debug("No icon candidates for feed \(feedID.uuidString, privacy: .public)")
            return nil
        }

        // Fast path: if a feed XML image candidate exists and passes the quality threshold,
        // use it immediately without evaluating remaining candidates. Feed XML icons are
        // purpose-built for the feed (compact logo, square, not a social share banner)
        // and the quality gate rejects obvious mismatches (extreme aspect ratios, oversized).
        if let feedXMLCandidate = typedCandidates.first(where: { $0.type == .feedXML }),
           let (image, stats) = await downloadAndAnalyze(url: feedXMLCandidate.url, feedID: feedID),
           Self.passesFastPathThreshold(image: image) {
            Self.logger.info("Fast-path: feed XML icon passed quality threshold for feed \(feedID.uuidString, privacy: .public) — using \(feedXMLCandidate.url.absoluteString, privacy: .public)")
            if let backgroundStyle = await writeNormalizedIcon(image: image, stats: stats, from: feedXMLCandidate.url, feedID: feedID) {
                await missTracker.recordSuccess(for: feedID)
                return (feedXMLCandidate.url, backgroundStyle)
            }
            Self.logger.warning("Fast-path write failed for feed \(feedID.uuidString, privacy: .public) — falling through to full scoring pass")
        }

        // General path: download all candidates concurrently (up to the cap), score each
        // by suitability for small-size display, and cache the highest-scoring one.
        let candidatesToScore = Array(typedCandidates.prefix(Self.maxCandidatesForScoring))

        // Download all candidates concurrently and collect (candidate, priorityIndex, image, stats) tuples.
        // The priority index (position in candidatesToScore) is preserved so that equal-scored
        // candidates resolve deterministically to the highest-priority source rather than whichever
        // download finished first (TaskGroup yields results in completion order, which is jitter-dependent).
        let downloadedCandidates: [(IconCandidate, Int, UIImage, IconPixelStats)] = await withTaskGroup(
            of: (IconCandidate, Int, UIImage, IconPixelStats)?.self
        ) { group in
            for (index, candidate) in candidatesToScore.enumerated() {
                group.addTask {
                    guard let (image, stats) = await self.downloadAndAnalyze(url: candidate.url, feedID: feedID) else {
                        return nil
                    }
                    return (candidate, index, image, stats)
                }
            }
            var results: [(IconCandidate, Int, UIImage, IconPixelStats)] = []
            for await result in group {
                if let result {
                    results.append(result)
                }
            }
            return results
        }

        guard !downloadedCandidates.isEmpty else {
            let missCount = await missTracker.recordMiss(for: feedID)
            if missCount == FeedIconMissTracker.missThreshold {
                Self.logger.warning(
                    "Icon resolution chronically failing for feed \(feedID.uuidString, privacy: .public) (\(feedSiteURL?.absoluteString ?? "no site URL", privacy: .public)) after \(missCount, privacy: .public) consecutive misses"
                )
            } else {
                Self.logger.debug(
                    "No icon candidates downloaded for feed \(feedID.uuidString, privacy: .public) (\(candidatesToScore.count, privacy: .public) tried, miss #\(missCount, privacy: .public))"
                )
            }
            return nil
        }

        // Score each downloaded candidate and pick the best.
        // Tie-breaking uses the original priority index (lower index = higher priority source),
        // making selection deterministic regardless of download completion order.
        let scored = downloadedCandidates.map { (candidate, priorityIndex, image, stats) in
            let score = Self.scoreIconCandidate(image: image, type: candidate.type)
            Self.logger.debug("Candidate \(candidate.url.absoluteString, privacy: .public) type=\(String(describing: candidate.type), privacy: .public) score=\(score, privacy: .public) size=\(image.size.width, privacy: .public)x\(image.size.height, privacy: .public) priorityIndex=\(priorityIndex, privacy: .public)")
            return (candidate: candidate, priorityIndex: priorityIndex, image: image, stats: stats, score: score)
        }

        guard let best = scored.max(by: {
            // Primary: higher score wins. Tie-break: lower priority index wins (higher-priority source).
            $0.score != $1.score ? $0.score < $1.score : $0.priorityIndex > $1.priorityIndex
        }) else {
            Self.logger.fault("scored array is empty despite non-empty downloadedCandidates — logic error in resolveAndCacheIcon")
            assertionFailure("scored.max() returned nil with \(scored.count) elements")
            return nil
        }

        Self.logger.info("Best icon candidate for feed \(feedID.uuidString, privacy: .public): \(best.candidate.url.absoluteString, privacy: .public) (score=\(best.score, privacy: .public))")

        if let backgroundStyle = await writeNormalizedIcon(image: best.image, stats: best.stats, from: best.candidate.url, feedID: feedID) {
            await missTracker.recordSuccess(for: feedID)
            return (best.candidate.url, backgroundStyle)
        }

        // Fallback: if writing the best candidate failed, try the remaining ones in score order.
        // Apply the same deterministic tie-breaking (lower priority index wins) used when selecting best.
        let fallbacks = scored
            .filter { $0.candidate.url != best.candidate.url }
            .sorted { lhs, rhs in
                lhs.score != rhs.score ? lhs.score > rhs.score : lhs.priorityIndex < rhs.priorityIndex
            }
        for fallback in fallbacks {
            if let backgroundStyle = await writeNormalizedIcon(image: fallback.image, stats: fallback.stats, from: fallback.candidate.url, feedID: feedID) {
                Self.logger.notice("Fell back to candidate \(fallback.candidate.url.absoluteString, privacy: .public) for feed \(feedID.uuidString, privacy: .public)")
                await missTracker.recordSuccess(for: feedID)
                return (fallback.candidate.url, backgroundStyle)
            }
        }

        let missCount = await missTracker.recordMiss(for: feedID)
        if missCount == FeedIconMissTracker.missThreshold {
            Self.logger.warning(
                "Icon resolution chronically failing for feed \(feedID.uuidString, privacy: .public) (\(feedSiteURL?.absoluteString ?? "no site URL", privacy: .public)) after \(missCount, privacy: .public) consecutive misses"
            )
        } else {
            Self.logger.debug(
                "No icon cached for feed \(feedID.uuidString, privacy: .public) after scoring \(downloadedCandidates.count, privacy: .public) candidates, miss #\(missCount, privacy: .public)"
            )
        }
        return nil
    }

    func classifyCachedIconBackgroundStyle(for feedID: UUID) async -> FeedIconBackgroundStyle? {
        guard let fileURL = cachedIconFileURL(for: feedID) else {
            return nil
        }
        return await Task.detached(priority: .utility) { () -> FeedIconBackgroundStyle? in
            guard let image = UIImage(contentsOfFile: fileURL.path(percentEncoded: false)) else {
                Self.logger.warning("classifyCachedIconBackgroundStyle: cached icon file unreadable for feed \(feedID.uuidString, privacy: .public)")
                return nil
            }
            let stats = Self.analyzeIconPixels(image, feedID: feedID)
            // Respect the same visibility gate as cacheIcon so a transparent
            // cached file doesn't get misclassified as `.dark` by the sentinel
            // fallback. An invisible cached icon is treated as unclassifiable.
            guard stats.isVisible else {
                Self.logger.debug("classifyCachedIconBackgroundStyle: cached icon for feed \(feedID.uuidString, privacy: .public) is not visible — skipping classification")
                return nil
            }
            let backgroundStyle = Self.classifyBackgroundStyle(averageLuminance: stats.averageLuminance)
            Self.logger.debug("Reclassified cached icon for feed \(feedID.uuidString, privacy: .public) as \(backgroundStyle.rawValue, privacy: .public) (luminance=\(stats.averageLuminance, privacy: .public))")
            return backgroundStyle
        }.value
    }

    // RATIONALE: Uses removeItem (permanent delete) rather than trashItem because these are
    // ephemeral cache files in the Caches directory that the system can already purge at will.
    func deleteCachedIcon(for feedID: UUID) {
        let fileURL = iconFileURL(for: feedID)
        do {
            try FileManager.default.removeItem(at: fileURL)
            Self.logger.debug("Deleted cached icon for feed \(feedID.uuidString, privacy: .public)")
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            // File already absent — nothing to clean up
        } catch {
            Self.logger.warning("Failed to delete cached icon for feed \(feedID.uuidString, privacy: .public): \(error, privacy: .public)")
        }
    }

    // MARK: - Internal (visible to tests)

    /// Result of parsing a site's homepage HTML for icon-related URLs.
    struct HTMLIconResult {
        /// Icon URLs extracted from `<link>` tags, ordered by priority: apple-touch-icon first, then rel="icon".
        let linkIcons: [URL]
        /// The subset of `linkIcons` that came from `<link rel="apple-touch-icon">` tags.
        /// Used by `assembleTypedCandidates` to assign `.appleTouchIcon` source type so the
        /// scorer can apply the appropriate suitability bonus.
        let appleTouchIconURLs: [URL]
        /// The `og:image` URL from `<meta property="og:image">`, if present.
        /// Resolved against the page's base URL to handle protocol-relative and relative URLs.
        let ogImageURL: URL?
        /// The host of the final URL after redirects, if it differs from the
        /// requested host (indicates a platform-hosted blog like Medium/Substack).
        let redirectedHost: String?
    }

    /// Assembles icon candidate URLs in priority order from the given inputs.
    /// Pure function — no I/O — enabling direct unit testing of the ordering logic.
    static func assembleCandidates(
        feedSiteURL: URL?,
        feedImageURL: URL?,
        htmlResult: HTMLIconResult?
    ) -> [URL] {
        assembleTypedCandidates(feedSiteURL: feedSiteURL, feedImageURL: feedImageURL, htmlResult: htmlResult)
            .map(\.url)
    }

    /// A typed icon candidate that pairs a URL with its source type.
    struct IconCandidate: Sendable, Equatable {
        let url: URL
        let type: IconCandidateType
    }

    /// Assembles typed icon candidates in priority order from the given inputs.
    /// Pure function — no I/O — enabling direct unit testing of ordering and scoring logic.
    static func assembleTypedCandidates(
        feedSiteURL: URL?,
        feedImageURL: URL?,
        htmlResult: HTMLIconResult?
    ) -> [IconCandidate] {
        var candidates: [IconCandidate] = []

        // Priority 1: Image URL from feed XML
        if let feedImageURL, feedImageURL.scheme == "http" || feedImageURL.scheme == "https" {
            candidates.append(IconCandidate(url: normalizeIconURL(feedImageURL), type: .feedXML))
        }

        let siteHost = feedSiteURL?.host(percentEncoded: false)

        if let htmlResult {
            // When the site URL redirected to a different platform domain (e.g.,
            // bothsidesofthetable.com → medium.com), the HTML icons extracted from
            // the redirect destination belong to the platform (Medium's "M" logo,
            // Medium's generic og:image), not the publication. Skip them entirely —
            // the feed XML image and the original-host /favicon.ico (Priority 4)
            // are better sources for platform-hosted blogs.
            let platformRedirectDetected = htmlResult.redirectedHost != nil

            if !platformRedirectDetected {
                // Priority 2: og:image from homepage.
                // When the site URL is served at its own domain (including CNAME-based
                // platform hosting like Medium custom domains), the og:image is
                // publication-specific branding and is worth trying as a candidate.
                // CNAME hosting doesn't trigger an HTTP redirect, so redirectedHost
                // stays nil and we land here (unlike an HTTP redirect to medium.com).
                if let ogImageURL = htmlResult.ogImageURL {
                    candidates.append(IconCandidate(url: ogImageURL, type: .ogImage))
                }

                // Priority 3: HTML link icons (apple-touch-icon first, then rel="icon").
                // HTMLUtilities.extractIconURLs already orders apple-touch-icons before rel="icon".
                // We determine the candidate type by checking whether the URL also appears in the
                // apple-touch-icon URL set produced by extractIconURLs' priority partition.
                //
                // Cross-domain apple-touch-icons (e.g., Medium CDN URLs served from
                // miro.medium.com for a netflixtechblog.com publication) are downgraded to
                // .linkIcon type — they carry the platform's branding, not the blog's,
                // and the reduced type bonus lets a publication-specific og:image win.
                let appleTouchIconURLs = Set(htmlResult.appleTouchIconURLs)
                for linkURL in htmlResult.linkIcons {
                    // Normalize hosts by stripping www. so that icons served from
                    // www.example.com are treated as same-host for example.com.
                    // When siteHost is nil (no feed site URL), default to cross-domain
                    // (the conservative choice) rather than granting same-host status.
                    let iconHost = linkURL.host(percentEncoded: false)
                    let iconIsFromSameHost = siteHost != nil &&
                        iconHost?.strippingWWWPrefix() == siteHost?.strippingWWWPrefix()
                    let isAppleTouchIcon = appleTouchIconURLs.contains(linkURL)
                    // Cross-domain apple-touch-icons (e.g., Medium CDN URLs for a
                    // CNAME-hosted blog) are downgraded to .linkIcon — they carry
                    // platform branding, not the blog's own.
                    let candidateType: IconCandidateType = isAppleTouchIcon && iconIsFromSameHost
                        ? .appleTouchIcon
                        : .linkIcon
                    candidates.append(IconCandidate(url: linkURL, type: candidateType))
                }
            }
        }

        // Priority 4: /favicon.ico fallback from the original site host.
        // When a platform redirect is detected and all HTML icons are skipped, this
        // becomes the first non-feed-XML candidate tried, since it targets the original
        // domain rather than the redirect destination.
        if let siteURL = feedSiteURL,
           let host = siteHost,
           !host.isEmpty,
           let faviconURL = URL(string: "\(siteURL.scheme ?? "https")://\(host)/favicon.ico") {
            candidates.append(IconCandidate(url: faviconURL, type: .faviconICO))
        }

        // Priority 5: When a cross-domain redirect occurred (e.g., bothsidesofthetable.com
        // → medium.com), also try the redirected host's /favicon.ico as a last resort.
        // RATIONALE: The host inequality check is redundant with HTMLIconResult's own guard,
        // but kept as a defensive safety net in case the struct's construction logic changes.
        if let redirectedHost = htmlResult?.redirectedHost,
           let siteURL = feedSiteURL,
           redirectedHost != siteHost,
           let faviconURL = URL(string: "\(siteURL.scheme ?? "https")://\(redirectedHost)/favicon.ico") {
            candidates.append(IconCandidate(url: faviconURL, type: .faviconICO))
        }

        return candidates
    }

    // MARK: - Private

    private func resolveFromHTML(siteURL: URL) async -> HTMLIconResult? {
        do {
            var request = URLRequest(url: siteURL, timeoutInterval: Self.htmlFetchTimeout)
            request.setBrowserUserAgent()
            let (bytes, response) = try await URLSession.shared.bytes(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                Self.logger.warning("Site HTML fetch returned HTTP \(code, privacy: .public) for \(siteURL.absoluteString, privacy: .public)")
                return nil
            }

            // Use the final URL (after redirects) as the base for resolving relative hrefs
            let baseURL = httpResponse.url ?? siteURL

            // Read until </head> — icon metadata is in <head>, no need for the full body.
            // Some sites (e.g. TechCrunch) pack >100 KB of inline CSS/preloads before
            // their icon <link> tags, so a small fixed cutoff misses them. We stream
            // bytes and check for the closing tag in a trailing window to avoid
            // downloading the entire page. A safety cap prevents runaway reads on
            // pages that lack a closing </head>.
            var collected = Data()
            collected.reserveCapacity(min(Self.htmlHeadMaxBytes, 65_536))
            let closingTag: [UInt8] = Array("</head>".utf8)
            // Ring buffer for the trailing bytes to match against </head>.
            // Sized to closingTag.count so it always holds exactly the last 7 bytes for comparison.
            var tailBuffer = [UInt8](repeating: 0, count: closingTag.count)
            var tailIndex = 0
            var foundClosingTag = false
            for try await byte in bytes {
                collected.append(byte)
                let lowerByte = byte | 0x20 // ASCII-lowercase letters; safe for </head> match
                tailBuffer[tailIndex % closingTag.count] = lowerByte
                tailIndex += 1
                // Only check for a full match when the current byte could be '>'
                // (the final character of </head>), skipping the inner loop for ~99% of bytes.
                if lowerByte == 0x3E && tailIndex >= closingTag.count {
                    var match = true
                    for j in 0..<closingTag.count {
                        if tailBuffer[(tailIndex - closingTag.count + j) % closingTag.count] != closingTag[j] {
                            match = false
                            break
                        }
                    }
                    if match {
                        foundClosingTag = true
                        break
                    }
                }
                if collected.count >= Self.htmlHeadMaxBytes { break }
            }
            if !foundClosingTag {
                if collected.count >= Self.htmlHeadMaxBytes {
                    Self.logger.debug("resolveFromHTML: safety cap (\(Self.htmlHeadMaxBytes, privacy: .public) bytes) reached without </head> for \(siteURL.absoluteString, privacy: .public) — parsing what was collected")
                } else {
                    Self.logger.debug("resolveFromHTML: stream ended at \(collected.count, privacy: .public) bytes without </head> for \(siteURL.absoluteString, privacy: .public) — parsing what was collected")
                }
            }

            guard let html = String(data: collected, encoding: .utf8) else {
                let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "unknown"
                Self.logger.warning("Failed to decode site HTML as UTF-8 (\(contentType, privacy: .public), \(collected.count, privacy: .public) bytes) from \(siteURL.absoluteString, privacy: .public)")
                return nil
            }

            let extractedIcons = HTMLUtilities.extractIconURLsSeparated(from: html, baseURL: baseURL)
            let linkIcons = extractedIcons.appleTouchIcons + extractedIcons.linkIcons
            let ogImageURL = HTMLUtilities.extractOGImageURL(from: html, baseURL: baseURL)

            // Detect cross-domain redirects (e.g., bothsidesofthetable.com → medium.com).
            // Normalize hosts by stripping the www. prefix before comparing so that a common
            // www-redirect (example.com → www.example.com) is not treated as a platform redirect.
            let originalHost = siteURL.host(percentEncoded: false)
            let finalHost = baseURL.host(percentEncoded: false)
            let redirectedHost: String?
            if let originalHost, let finalHost,
               originalHost.strippingWWWPrefix() != finalHost.strippingWWWPrefix() {
                Self.logger.info("Cross-domain redirect detected: \(originalHost, privacy: .public) → \(finalHost, privacy: .public)")
                redirectedHost = finalHost
            } else {
                redirectedHost = nil
            }

            return HTMLIconResult(
                linkIcons: linkIcons,
                appleTouchIconURLs: extractedIcons.appleTouchIcons,
                ogImageURL: ogImageURL,
                redirectedHost: redirectedHost
            )
        } catch {
            Self.logger.warning("Failed to fetch site HTML from \(siteURL.absoluteString, privacy: .public): \(error, privacy: .public)")
            return nil
        }
    }

    /// Strips trailing slashes from icon URLs that some feeds incorrectly append
    /// (e.g., `icon.png/` → `icon.png`).
    private static func normalizeIconURL(_ url: URL) -> URL {
        var path = url.path(percentEncoded: false)
        while path.hasSuffix("/") && path != "/" {
            path = String(path.dropLast())
        }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: true)
        components?.path = path
        return components?.url ?? url
    }

    /// Decodes an ICO file by extracting the largest embedded image.
    /// ICO files contain a directory of images (PNG or BMP) at various sizes.
    static func decodeICO(_ data: Data) -> UIImage? {
        // ICO header: 2 bytes reserved (0), 2 bytes type (1 = icon), 2 bytes image count
        guard data.count >= 6 else { return nil }
        let reserved = UInt16(data[0]) | UInt16(data[1]) << 8
        let type = UInt16(data[2]) | UInt16(data[3]) << 8
        let count = UInt16(data[4]) | UInt16(data[5]) << 8
        guard reserved == 0, type == 1, count > 0 else { return nil }

        // Each directory entry is 16 bytes, starting at offset 6
        let headerSize = 6
        let entrySize = 16
        guard data.count >= headerSize + Int(count) * entrySize else { return nil }

        // Find the largest image entry by pixel area
        var bestArea = 0
        var bestOffset: UInt32 = 0
        var bestSize: UInt32 = 0

        for i in 0..<Int(count) {
            let base = headerSize + i * entrySize
            // Width/height of 0 means 256
            let w = data[base] == 0 ? 256 : Int(data[base])
            let h = data[base + 1] == 0 ? 256 : Int(data[base + 1])
            let area = w * h

            let bytesInRes = UInt32(data[base + 8])
                | UInt32(data[base + 9]) << 8
                | UInt32(data[base + 10]) << 16
                | UInt32(data[base + 11]) << 24
            let imageOffset = UInt32(data[base + 12])
                | UInt32(data[base + 13]) << 8
                | UInt32(data[base + 14]) << 16
                | UInt32(data[base + 15]) << 24

            if area > bestArea {
                bestArea = area
                bestOffset = imageOffset
                bestSize = bytesInRes
            }
        }

        guard bestSize > 0,
              Int(bestOffset) + Int(bestSize) <= data.count else { return nil }

        let imageData = data[Int(bestOffset)..<Int(bestOffset) + Int(bestSize)]

        // Try PNG first (many modern ICOs embed PNG), then fall back to raw data
        if let image = UIImage(data: Data(imageData)) {
            logger.debug("Decoded ICO image (PNG-embedded, \(bestArea)px area)")
            return image
        }

        // BMP in ICO: starts with BITMAPINFOHEADER (40 bytes).
        // Wrap it in a proper BMP file so UIImage can decode it.
        if imageData.count > 40 {
            if let image = decodeBMPFromICO(Data(imageData), width: Int(sqrt(Double(bestArea)))) {
                logger.debug("Decoded ICO image (BMP, \(bestArea)px area)")
                return image
            }
        }

        return nil
    }

    /// Decodes a BMP image entry from an ICO file.
    /// ICO BMP entries omit the 14-byte BITMAPFILEHEADER and use doubled height
    /// (to account for the AND mask). This method prepends the file header and
    /// fixes the height before decoding via `UIImage(data:)`.
    private static func decodeBMPFromICO(_ bmpData: Data, width: Int) -> UIImage? {
        guard bmpData.count >= 40 else { return nil }

        // Read BITMAPINFOHEADER fields
        var header = bmpData.prefix(40)
        let biHeight = Int32(bitPattern:
            UInt32(header[8]) | UInt32(header[9]) << 8
            | UInt32(header[10]) << 16 | UInt32(header[11]) << 24
        )

        // ICO doubles the height to include the AND mask — halve it
        let realHeight = abs(biHeight) / 2
        let correctedHeight = UInt32(bitPattern: Int32(realHeight))
        header[8] = UInt8(correctedHeight & 0xFF)
        header[9] = UInt8((correctedHeight >> 8) & 0xFF)
        header[10] = UInt8((correctedHeight >> 16) & 0xFF)
        header[11] = UInt8((correctedHeight >> 24) & 0xFF)

        // Build a full BMP file: 14-byte file header + corrected BITMAPINFOHEADER + pixel data
        let pixelDataOffset: UInt32 = 14 + 40
        let fileSize = UInt32(14 + bmpData.count)
        var bmpFile = Data(capacity: Int(fileSize))
        // BITMAPFILEHEADER (14 bytes)
        bmpFile.append(contentsOf: [0x42, 0x4D]) // "BM"
        bmpFile.append(contentsOf: withUnsafeBytes(of: fileSize.littleEndian) { Array($0) })
        bmpFile.append(contentsOf: [0, 0, 0, 0]) // reserved
        bmpFile.append(contentsOf: withUnsafeBytes(of: pixelDataOffset.littleEndian) { Array($0) })
        // Corrected header + rest of pixel data
        bmpFile.append(header)
        bmpFile.append(bmpData.dropFirst(40))

        return UIImage(data: bmpFile)
    }

    /// Result of a single-pass bitmap walk: whether the image has visible
    /// opaque content and the average luminance of its opaque pixels.
    ///
    /// `averageLuminance` is meaningful only when `isVisible == true`. When the
    /// image is fully transparent, the walk produces `averageLuminance == 0`
    /// and the caller should ignore it. Values are in `[0, 1]`, computed over
    /// premultiplied-alpha-adjusted RGB using ITU-R BT.601 coefficients.
    struct IconPixelStats: Equatable {
        let isVisible: Bool
        let averageLuminance: Double
    }

    /// Returns `false` if the image is fully or mostly transparent (e.g., a tracking pixel
    /// or placeholder favicon). Pixels with alpha > 25 (out of 255) are considered visible;
    /// at least 1% of pixels must be visible for the image to pass.
    /// Returns `true` when CGContext inspection fails — accept-on-failure matches the
    /// legacy semantic so bitmap-inspection glitches don't drop otherwise-valid icons.
    static func hasVisibleContent(_ image: UIImage) -> Bool {
        analyzeIconPixels(image).isVisible
    }

    /// Walks the image bitmap once to compute visibility and the average
    /// luminance of opaque pixels.
    ///
    /// Combines the visibility gate and luminance analysis in a single pass
    /// so `cacheIcon` doesn't need to allocate a second bitmap to classify
    /// the icon's background style (issue #342).
    ///
    /// RATIONALE: On CGContext-allocation failure (rare — memory pressure or
    /// CIImage-backed UIImage with no CGImage) this returns a sentinel
    /// `IconPixelStats(isVisible: true, averageLuminance: 1.0)` rather than
    /// signalling failure. The accept-on-failure stance preserves the pre-PR
    /// `hasVisibleContent` semantic: a transient inspection failure should not
    /// drop an image that decoded successfully. Sentinel luminance 1.0 sits
    /// above `iconLightBackgroundLuminanceThreshold` so `classifyBackgroundStyle`
    /// returns `.dark` → black tile, matching the pre-classifier rendering
    /// for feeds that existed before this feature shipped.
    static func analyzeIconPixels(_ image: UIImage, feedID: UUID? = nil) -> IconPixelStats {
        let feedIDDesc = feedID?.uuidString ?? "unknown"
        guard let cgImage = image.cgImage else {
            logger.warning("analyzeIconPixels: image has no CGImage backing for feed \(feedIDDesc, privacy: .public) — defaulting to neutral stats")
            return IconPixelStats(isVisible: true, averageLuminance: 1.0)
        }
        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0 else {
            return IconPixelStats(isVisible: false, averageLuminance: 0)
        }

        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixelData = [UInt8](repeating: 0, count: height * bytesPerRow)

        return pixelData.withUnsafeMutableBytes { ptr -> IconPixelStats in
            guard let context = CGContext(
                data: ptr.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                logger.warning("analyzeIconPixels: CGContext creation failed for \(width)x\(height) image (feed \(feedIDDesc, privacy: .public)) — defaulting to neutral stats")
                return IconPixelStats(isVisible: true, averageLuminance: 1.0)
            }

            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

            let totalPixels = width * height
            var opaquePixels = 0
            var luminanceSum: Double = 0
            let alphaThreshold: UInt8 = 25
            // ITU-R BT.601 luminance coefficients
            let redWeight = 0.299
            let greenWeight = 0.587
            let blueWeight = 0.114

            for i in stride(from: 0, to: ptr.count, by: bytesPerPixel) {
                let alpha = ptr[i + 3]
                guard alpha > alphaThreshold else { continue }
                opaquePixels += 1
                // Context is premultipliedLast — divide by alpha to recover the
                // original color so dark-on-semitransparent strokes contribute
                // their true color, not a washed-out value. Clamp to [0, 1] to
                // match the doc comment's guarantee — bitmap roundtrip rounding
                // can leave channel/alpha values fractionally out of range.
                let alphaFraction = Double(alpha) / 255.0
                let r = min(1.0, Double(ptr[i]) / 255.0 / alphaFraction)
                let g = min(1.0, Double(ptr[i + 1]) / 255.0 / alphaFraction)
                let b = min(1.0, Double(ptr[i + 2]) / 255.0 / alphaFraction)
                luminanceSum += redWeight * r + greenWeight * g + blueWeight * b
            }

            let isVisible = Double(opaquePixels) / Double(totalPixels) >= 0.01
            let averageLuminance = opaquePixels > 0 ? luminanceSum / Double(opaquePixels) : 0
            return IconPixelStats(isVisible: isVisible, averageLuminance: averageLuminance)
        }
    }

    /// Luminance threshold above which an icon is considered "light enough"
    /// to need a dark (black) background behind it. Icons at or below the
    /// threshold get a light (white) background so their dark strokes stay
    /// visible where the PNG has transparency. 0.7 separates Apple-Insider-
    /// style white-on-transparent logos (≈1.0 average) from dark flat icons
    /// (≈0.2–0.4) in issue #342 test data.
    static let iconLightBackgroundLuminanceThreshold: Double = 0.7

    /// Maps an average luminance value to a `FeedIconBackgroundStyle`.
    /// Centralized so the threshold and the classification rule live in one
    /// place and tests can pin the boundary without reaching into `cacheIcon`.
    static func classifyBackgroundStyle(averageLuminance: Double) -> FeedIconBackgroundStyle {
        averageLuminance > iconLightBackgroundLuminanceThreshold ? .dark : .light
    }

    // MARK: - Icon Suitability Scoring

    /// Scores an icon candidate's suitability for display at small size (~32pt).
    ///
    /// The score is a value in `[0, 1]` computed from three factors:
    /// - **Aspect ratio** (weight 0.5): `min(w,h) / max(w,h)`. Square = 1.0; 1200×630 ≈ 0.53.
    /// - **Dimension** (weight 0.3): peaks at the sweet spot (~96px), decays for very
    ///   small (<16px) or very large (>512px) images. The decay curves reflect that
    ///   huge images lose detail when downscaled to 32pt, and tiny images are already
    ///   pixelated.
    /// - **Source type bonus** (weight 0.2): `.appleTouchIcon` and `.feedXML` receive the
    ///   full bonus (1.0); `.faviconICO` receives a partial bonus (0.6); `.ogImage`
    ///   receives no bonus (0.0) because og:image is designed for social sharing
    ///   (wide banners) rather than compact display. `.linkIcon` receives a small bonus (0.4).
    ///
    /// Pure function — no I/O.
    static func scoreIconCandidate(image: UIImage, type: IconCandidateType) -> Double {
        let width = image.size.width
        let height = image.size.height
        guard width > 0, height > 0 else { return 0 }

        // Aspect ratio score: 1.0 for square, lower for elongated images
        let aspectRatio = min(width, height) / max(width, height)

        // Dimension score: peaks near the icon sweet spot (~96px), penalizes extremes.
        // Uses a piecewise function: linearly ramps from 0 at 1px to 1.0 at sweetSpot,
        // then decays from 1.0 at sweetSpot toward 0 at penaltyStart.
        let maxDim = max(width, height)
        let sweetSpot: Double = 96
        let penaltyStart: Double = 256  // starts penalizing above this
        let penaltyEnd: Double = 1024   // zero score at this size

        let dimensionScore: Double
        if maxDim <= sweetSpot {
            // Ramp from 0 at 1px to 1.0 at sweetSpot — small but crisp icons are good
            dimensionScore = maxDim / sweetSpot
        } else if maxDim <= penaltyStart {
            dimensionScore = 1.0
        } else {
            // Linear decay from 1.0 at penaltyStart toward 0 at penaltyEnd
            let decay = (maxDim - penaltyStart) / (penaltyEnd - penaltyStart)
            dimensionScore = max(0, 1.0 - decay)
        }

        // Source type bonus
        let typeBonus: Double
        switch type {
        case .feedXML:        typeBonus = 1.0
        case .appleTouchIcon: typeBonus = 1.0
        case .linkIcon:       typeBonus = 0.4
        case .faviconICO:     typeBonus = 0.6
        case .ogImage:        typeBonus = 0.0
        }

        // Weighted sum
        return 0.5 * aspectRatio + 0.3 * dimensionScore + 0.2 * typeBonus
    }

    /// Minimum score for a feed XML image to qualify for the fast path (skip scoring other candidates).
    /// A score of 0.7 requires the image to be roughly square (aspect ≥ 0.6) and not oversized.
    /// feedXML type bonus (0.2) is already included in the score so a 180×180 feed XML image
    /// scores 0.5 * 1.0 + 0.3 * 1.0 + 0.2 * 1.0 = 1.0 and easily qualifies.
    /// A 512×268 feed XML image scores 0.5 * (268/512) + 0.3 * (1 - (512-256)/(1024-256)) + 0.2 * 1.0
    /// ≈ 0.5 * 0.523 + 0.3 * 0.667 + 0.2 = 0.262 + 0.200 + 0.200 ≈ 0.662 — below threshold.
    static let feedXMLFastPathScoreThreshold: Double = 0.7

    /// Returns `true` if a feed XML image qualifies for the fast path — skip scoring other candidates.
    static func passesFastPathThreshold(image: UIImage) -> Bool {
        scoreIconCandidate(image: image, type: .feedXML) >= feedXMLFastPathScoreThreshold
    }

    // MARK: - Private download helpers

    /// Downloads and decodes the image at `url`, returning the normalized image and its pixel stats.
    /// Returns `nil` when the download fails, the response is not HTTP 2xx, the data is not a
    /// decodable image, or the image has no visible content.
    private func downloadAndAnalyze(url: URL, feedID: UUID) async -> (UIImage, IconPixelStats)? {
        do {
            var request = URLRequest(url: url, timeoutInterval: Self.iconFetchTimeout)
            request.setBrowserUserAgent()
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                Self.logger.warning("downloadAndAnalyze: HTTP \(code, privacy: .public) for \(url.absoluteString, privacy: .public)")
                return nil
            }

            guard let image = UIImage(data: data) ?? Self.decodeICO(data) else {
                Self.logger.warning("downloadAndAnalyze: not a valid image from \(url.absoluteString, privacy: .public)")
                return nil
            }

            let normalized = normalizeImage(image)
            let stats = Self.analyzeIconPixels(normalized, feedID: feedID)
            guard stats.isVisible else {
                Self.logger.warning("downloadAndAnalyze: image has no visible content from \(url.absoluteString, privacy: .public)")
                return nil
            }

            return (normalized, stats)
        } catch let error as URLError where error.code == .cancelled {
            Self.logger.debug("downloadAndAnalyze: download cancelled for \(url.absoluteString, privacy: .public)")
            return nil
        } catch {
            Self.logger.warning("downloadAndAnalyze: download failed for \(url.absoluteString, privacy: .public): \(error, privacy: .public)")
            return nil
        }
    }

    /// Writes a normalized (already downloaded and analyzed) image to the cache.
    /// Returns the background style classification on success, `nil` on PNG-encode or write failure.
    private func writeNormalizedIcon(image: UIImage, stats: IconPixelStats, from remoteURL: URL, feedID: UUID) async -> FeedIconBackgroundStyle? {
        guard let pngData = image.pngData() else {
            Self.logger.warning("writeNormalizedIcon: failed to generate PNG data for \(remoteURL.absoluteString, privacy: .public) (feed \(feedID.uuidString, privacy: .public))")
            return nil
        }
        do {
            let fileURL = iconFileURL(for: feedID)
            try ensureCacheDirectoryExists()
            try pngData.write(to: fileURL, options: .atomic)
            let backgroundStyle = Self.classifyBackgroundStyle(averageLuminance: stats.averageLuminance)
            Self.logger.debug("Cached icon for feed \(feedID.uuidString, privacy: .public) (\(pngData.count, privacy: .public) bytes, luminance=\(stats.averageLuminance, privacy: .public), background=\(backgroundStyle.rawValue, privacy: .public))")
            return backgroundStyle
        } catch {
            Self.logger.error("writeNormalizedIcon: failed to write cache for feed \(feedID.uuidString, privacy: .public): \(error, privacy: .public)")
            return nil
        }
    }

    private func normalizeImage(_ image: UIImage) -> UIImage {
        let maxDim = Self.maxIconDimension
        guard image.size.width > maxDim || image.size.height > maxDim else {
            return image
        }
        let scale = min(maxDim / image.size.width, maxDim / image.size.height)
        let newSize = CGSize(
            width: (image.size.width * scale).rounded(),
            height: (image.size.height * scale).rounded()
        )
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    private func iconFileURL(for feedID: UUID) -> URL {
        cacheDirectory.appendingPathComponent("\(feedID.uuidString).png")
    }

    private var cacheDirectory: URL {
        if let cacheDirectoryOverride {
            return cacheDirectoryOverride
        }
        return FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Self.iconCacheDirectoryName)
    }

    private func ensureCacheDirectoryExists() throws {
        try FileManager.default.createDirectory(
            at: cacheDirectory,
            withIntermediateDirectories: true
        )
    }
}

// MARK: - Private helpers

private extension String {
    /// Returns the string with a leading "www." prefix removed (case-insensitive).
    /// Used to normalize hostnames before comparing them so that a redirect from
    /// "example.com" to "www.example.com" (or vice versa) is not treated as a
    /// cross-domain platform redirect.
    func strippingWWWPrefix() -> String {
        if lowercased().hasPrefix("www.") {
            return String(dropFirst(4))
        }
        return self
    }
}
