import os
import SwiftUI

struct FeedIconView: View {

    enum Style {
        /// 32pt square (at default Dynamic Type). Scales relative to `.headline` so it
        /// tracks the adjacent feed title in `FeedRowView`. Used by `FeedRowView`
        /// (the row rendered in `FeedListView`).
        case standard
        /// 14pt square (at default Dynamic Type). Scales relative to `.caption` so it
        /// tracks the adjacent feed name in the metadata footer of `ArticleRowView`.
        case inline
    }

    let feedID: UUID
    /// The feed's XML URL, used to derive the site root for icon candidate
    /// resolution when on-view fallback is triggered. Callers that only
    /// display already-cached icons (none today — kept for safety) may pass
    /// `nil`, but on-view resolution will be skipped.
    let feedURL: URL?
    /// Drives `.task(id:)` so the icon load re-runs after the feed's icon URL is
    /// resolved and cached. The value itself isn't used for rendering.
    let iconURL: URL?
    let iconService: FeedIconResolving
    var style: Style = .standard

    @State private var iconImage: UIImage?

    private static let logger = Logger(category: "FeedIconView")

    // RATIONALE: @ScaledMetric must live on the view (not the Style enum) because property
    // wrappers require stored properties on a DynamicProperty-conforming type. Both sizes are
    // declared up front and the body selects one based on `style` — unused metrics are cheap
    // and this keeps the declarations co-located with their `relativeTo:` text styles.
    @ScaledMetric(relativeTo: .headline) private var standardIconSize: CGFloat = 32
    @ScaledMetric(relativeTo: .caption) private var inlineIconSize: CGFloat = 14

    private var iconSize: CGFloat {
        switch style {
        case .standard: return standardIconSize
        case .inline: return inlineIconSize
        }
    }

    /// Corner radius scales with the icon so the rounded-rect proportions hold at all
    /// Dynamic Type sizes (standard: 32pt → 6pt radius, inline: 14pt → 3pt radius).
    private var cornerRadius: CGFloat {
        switch style {
        case .standard: return iconSize * (6.0 / 32.0)
        case .inline: return iconSize * (3.0 / 14.0)
        }
    }

    var body: some View {
        ZStack {
            // Solid black tile behind every icon so favicons without their own
            // background (e.g. Apple Insider's transparent-edge logo) sit on a
            // consistent chrome that matches the larger `.standard` rows in
            // `FeedListView`. Icons with their own opaque background paint over
            // this tile, so the black is only visible where the icon itself
            // has transparency.
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color.black)

            if let iconImage {
                Image(uiImage: iconImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            } else {
                // Placeholder globe while the icon resolves (or if the feed
                // has no icon at all). Sized relative to the frame so it
                // tracks Dynamic Type scaling at both style sizes.
                Image(systemName: "globe")
                    .font(.system(size: iconSize * 0.6))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .frame(width: iconSize, height: iconSize)
        .task(id: iconURL) {
            await loadIcon()
        }
    }

    // MARK: - Loading

    // RATIONALE: On-view resolution mirrors the ArticleThumbnailView pattern where
    // the view always attempts to load the image when shown, regardless of WiFi-only
    // background download settings. The Settings screen explicitly states "Images
    // loaded while browsing are always fetched." On-view loads are user-initiated
    // browsing, so they must not be gated by isBackgroundDownloadAllowed().
    private func loadIcon() async {
        // Step 1: Try loading from cache (delegates decode + visibility validation
        // + delete-on-corrupt to FeedIconResolving).
        if let cached = await iconService.loadValidatedIcon(for: feedID) {
            iconImage = cached
            return
        }

        // Step 2: No cached icon — attempt on-view resolution if we have a feed URL.
        guard let feedURL else {
            Self.logger.debug("No feedURL for feed \(feedID.uuidString, privacy: .public) — cannot resolve icon on-view")
            return
        }

        let backoffKey = feedID.uuidString
        guard !ImageLoadBackoffTracker.feedIcons.shouldSuppress(backoffKey) else {
            return
        }

        // Derive site URL from feed URL the same way FeedRefreshService does.
        let feedSiteURL = Self.siteURL(from: feedURL)
        if feedSiteURL == nil {
            Self.logger.debug("Could not derive site URL from feedURL for feed \(feedID.uuidString, privacy: .public)")
        }

        // Both resolution inputs are nil — skip the service call to avoid
        // triggering backoff escalation for a permanently unresolvable condition.
        guard feedSiteURL != nil || iconURL != nil else {
            Self.logger.debug("No site URL or icon URL available for feed \(feedID.uuidString, privacy: .public) — skipping on-view resolution")
            return
        }

        let resolvedURL = await iconService.resolveAndCacheIcon(
            feedSiteURL: feedSiteURL,
            feedImageURL: iconURL,
            feedID: feedID
        )

        guard resolvedURL != nil else {
            ImageLoadBackoffTracker.feedIcons.recordFailure(for: backoffKey)
            iconImage = nil
            return
        }

        // Successfully resolved — clear any prior backoff and reload from cache.
        ImageLoadBackoffTracker.feedIcons.clearFailure(for: backoffKey)
        Self.logger.notice("Resolved icon on-view for feed \(feedID.uuidString, privacy: .public)")
        let validated = await iconService.loadValidatedIcon(for: feedID)
        if validated == nil {
            Self.logger.warning("Icon resolved for feed \(feedID.uuidString, privacy: .public) but failed post-cache validation")
        }
        iconImage = validated
    }

    /// Derives a site root URL from a feed URL (e.g., https://example.com/feed → https://example.com).
    /// Returns nil if the feed URL has no host.
    private static func siteURL(from feedURL: URL) -> URL? {
        guard let host = feedURL.host(percentEncoded: false), !host.isEmpty else { return nil }
        return URL(string: "\(feedURL.scheme ?? "https")://\(host)")
    }
}
