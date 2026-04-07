import SwiftUI

struct FeedIconView: View {

    enum Style {
        /// 32pt square (at default Dynamic Type) with a tertiary-fill background and globe
        /// placeholder while loading. Scales relative to `.headline` so it tracks the adjacent
        /// feed title in `FeedRowView`. Used by `FeedRowView` (the row used in `FeedListView`).
        case standard
        /// 14pt square (at default Dynamic Type) with no background and no placeholder — when
        /// no cached icon is available the view still occupies its frame but renders no visible
        /// chrome, so surrounding text sits flush against an empty slot rather than a globe
        /// glyph. Scales relative to `.caption` so it tracks the adjacent feed name in
        /// cross-feed article rows.
        case inline

        fileprivate var showsPlaceholder: Bool {
            switch self {
            case .standard: return true
            case .inline: return false
            }
        }
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
            // RATIONALE: Color.clear is an always-present base so the ZStack has concrete
            // content even in the .inline style when no icon is cached. Without it, SwiftUI
            // can resolve the subtree to EmptyView and `.task(id:)` fails to attach to the
            // view lifecycle, leaving the icon permanently blank. Only `.inline` needs this —
            // `.standard` always renders the RoundedRectangle base so its ZStack is never empty.
            Color.clear

            if style.showsPlaceholder {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color(.tertiarySystemFill))
            }

            if let iconImage {
                Image(uiImage: iconImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            } else if style.showsPlaceholder {
                Image(systemName: "globe")
                    .foregroundStyle(.secondary)
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
