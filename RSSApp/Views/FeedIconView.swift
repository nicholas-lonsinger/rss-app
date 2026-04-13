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
    /// The image URL declared in the feed's XML (`<image><url>` in RSS,
    /// `<logo>` / `<icon>` in Atom). Passed to icon resolution as a
    /// `.feedXML` candidate. `nil` when the feed XML declares no image.
    let feedImageURL: URL?
    /// Drives `.task(id:)` so the icon load re-runs after the feed's icon URL is
    /// resolved and cached. The value itself isn't used for rendering.
    let iconURL: URL?
    /// The feed's persisted icon-background classification. `nil` falls back
    /// to the legacy black tile for feeds that predate the classifier
    /// (issue #342); they back-fill on the next successful refresh.
    let iconBackgroundStyle: FeedIconBackgroundStyle?
    let iconService: FeedIconResolving
    var style: Style = .standard
    /// Called after successful on-view icon resolution so the caller can
    /// persist the background style to the model. Both paths ultimately mutate
    /// `PersistentFeed.iconBackgroundStyle`; the view reads only from
    /// `iconBackgroundStyle` (the model parameter), eliminating the ephemeral
    /// `@State` bridge that caused backgrounds to revert to black on
    /// scroll-back (issue #411).
    var onBackgroundStyleResolved: ((FeedIconBackgroundStyle) -> Void)? = nil

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

    /// The tile color that best contrasts against a loaded icon (issue #342).
    /// Only applied when `iconImage` is non-nil; the placeholder always
    /// uses a white tile (see `body`). `nil` → legacy black for feeds
    /// that predate the classifier.
    private var backgroundColor: Color {
        switch iconBackgroundStyle {
        case .light: return .white
        case .dark, .none: return .black
        }
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(iconImage != nil ? backgroundColor : .white)

            if let iconImage {
                Image(uiImage: iconImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            } else {
                // Placeholder globe while the icon resolves (or if the feed
                // has no icon at all). Always on a white tile so the dark
                // globe is legible and visually consistent. Sized at 60%
                // of the icon frame so it scales with Dynamic Type.
                Image(systemName: "globe")
                    .font(.system(size: iconSize * 0.6))
                    .foregroundStyle(.black.opacity(0.4))
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
            Self.logger.debug("On-view icon resolution suppressed by backoff for feed \(feedID.uuidString, privacy: .public)")
            return
        }

        // Derive site URL from feed URL.
        let feedSiteURL = feedURL.siteRoot
        if feedSiteURL == nil {
            Self.logger.debug("Could not derive site URL from feedURL for feed \(feedID.uuidString, privacy: .public)")
        }

        // Both resolution inputs are nil — skip the service call to avoid
        // triggering backoff escalation for a permanently unresolvable condition.
        guard feedSiteURL != nil || feedImageURL != nil else {
            Self.logger.debug("No site URL or feed image URL available for feed \(feedID.uuidString, privacy: .public) — skipping on-view resolution")
            return
        }

        let resolved = await iconService.resolveAndCacheIcon(
            feedSiteURL: feedSiteURL,
            feedImageURL: feedImageURL,
            feedID: feedID
        )

        guard let resolved else {
            // Do not record a backoff failure for cancellation — cancelled tasks
            // are not genuine resolution failures and should not suppress future
            // icon load attempts (e.g. during rapid scrolling, which triggers many
            // cancellations via .task(id:) teardown).
            guard !Task.isCancelled else {
                Self.logger.debug("Skipping backoff recording for feed \(feedID.uuidString, privacy: .public) — caller task cancelled")
                return
            }
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

        // Persist the background style to the model so it survives view
        // destruction across scroll cycles. The refresh path persists via
        // applyIconResolution(); this is the on-view equivalent. Image is
        // set first so the view's local state is consistent before the
        // caller persists the background style to the model.
        onBackgroundStyleResolved?(resolved.backgroundStyle)
    }
}
