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
    /// Drives `.task(id:)` so the icon load re-runs after the feed's icon URL is
    /// resolved and cached. The value itself isn't used for rendering.
    let iconURL: URL?
    let iconService: FeedIconResolving
    var style: Style = .standard

    @State private var iconImage: UIImage?

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
            // RATIONALE: Delegates decode + visibility validation + delete-on-corrupt
            // to FeedIconResolving so the cache-validity invariant is enforced once at
            // the service boundary. Keeps this view to a single async call.
            iconImage = await iconService.loadValidatedIcon(for: feedID)
        }
    }
}
