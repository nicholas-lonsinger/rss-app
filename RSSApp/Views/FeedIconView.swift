import SwiftUI

struct FeedIconView: View {

    enum Style {
        /// 32pt square with a tertiary-fill background and globe placeholder while loading.
        /// Used by `FeedRowView` (the row used in `FeedListView`).
        case standard
        /// 14pt square with no background and no placeholder — when no cached icon is available
        /// the view still occupies its 14pt frame but renders no visible chrome, so surrounding
        /// text sits flush against an empty slot rather than a globe glyph. Used inline with
        /// `.caption`-sized text in cross-feed article rows.
        case inline

        fileprivate var iconSize: CGFloat {
            switch self {
            case .standard: return 32
            case .inline: return 14
            }
        }

        fileprivate var cornerRadius: CGFloat {
            switch self {
            case .standard: return 6
            case .inline: return 3
            }
        }

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

    var body: some View {
        ZStack {
            // RATIONALE: Color.clear is an always-present base so the ZStack has concrete
            // content even in the .inline style when no icon is cached. Without it, SwiftUI
            // can resolve the subtree to EmptyView and `.task(id:)` fails to attach to the
            // view lifecycle, leaving the icon permanently blank. Only `.inline` needs this —
            // `.standard` always renders the RoundedRectangle base so its ZStack is never empty.
            Color.clear

            if style.showsPlaceholder {
                RoundedRectangle(cornerRadius: style.cornerRadius)
                    .fill(Color(.tertiarySystemFill))
            }

            if let iconImage {
                Image(uiImage: iconImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: style.cornerRadius))
            } else if style.showsPlaceholder {
                Image(systemName: "globe")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: style.iconSize, height: style.iconSize)
        .task(id: iconURL) {
            // RATIONALE: Delegates decode + visibility validation + delete-on-corrupt
            // to FeedIconResolving so the cache-validity invariant is enforced once at
            // the service boundary. Keeps this view to a single async call.
            iconImage = await iconService.loadValidatedIcon(for: feedID)
        }
    }
}
