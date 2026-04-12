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
    /// Raw value of the feed's persisted `FeedIconBackgroundStyle`. Classifies
    /// the cached icon as "light icon, needs dark tile" (`.dark`) or
    /// "dark icon, needs light tile" (`.light`). `nil` falls back to the
    /// legacy black tile so feeds that predate the classifier render as they
    /// did before issue #342 — they reclassify automatically on the next
    /// successful refresh.
    let iconBackgroundStyleRawValue: String?
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

    /// The tile color that best contrasts against the cached icon. Picked
    /// from the persisted `iconBackgroundStyle` (issue #342): dark icons get
    /// a white tile, light icons get a black tile. Nil falls back to black
    /// for backward compatibility with feeds cached before the classifier
    /// existed — those feeds will reclassify on their next successful
    /// refresh, and the black tile matches their prior rendering in the
    /// meantime so there's no visual regression.
    private var backgroundColor: Color {
        guard let raw = iconBackgroundStyleRawValue,
              let style = FeedIconBackgroundStyle(rawValue: raw) else {
            return .black
        }
        switch style {
        case .light: return .white
        case .dark: return .black
        }
    }

    /// The globe placeholder color is paired with the background so it stays
    /// legible regardless of which tile is rendered. The placeholder never
    /// sits on an icon — it only shows while loading or when no icon exists
    /// — so its color is chosen purely against the tile.
    private var placeholderForegroundColor: Color {
        backgroundColor == .white ? .black.opacity(0.4) : .white.opacity(0.6)
    }

    var body: some View {
        ZStack {
            // Solid background tile behind every icon so favicons without
            // their own background (e.g. Apple Insider's transparent-edge
            // logo) sit on a consistent chrome. The tile color is picked
            // from the feed's persisted luminance classification so dark
            // icons get a white tile and light icons get a black tile
            // (issue #342). Icons with their own opaque background paint
            // over this tile, so the tile color is only visible where the
            // icon itself has transparency.
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(backgroundColor)

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
                    .foregroundStyle(placeholderForegroundColor)
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

        // Derive site URL from feed URL.
        let feedSiteURL = feedURL.siteRoot
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
}
