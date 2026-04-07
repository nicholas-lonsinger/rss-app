import os
import SwiftUI

struct FeedIconView: View {

    enum Style {
        /// 32pt square with a tertiary-fill background and globe placeholder while loading.
        /// Used by `FeedListView` feed rows.
        case standard
        /// 14pt square with no background and no placeholder — renders nothing visible when
        /// no cached icon is available, so surrounding text collapses cleanly next to it.
        /// Used inline with `.caption`-sized text in cross-feed article rows.
        case inline

        var iconSize: CGFloat {
            switch self {
            case .standard: return 32
            case .inline: return 14
            }
        }

        var cornerRadius: CGFloat {
            switch self {
            case .standard: return 6
            case .inline: return 3
            }
        }

        var showsPlaceholder: Bool {
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
            // view lifecycle, leaving the icon permanently blank.
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
            guard let fileURL = iconService.cachedIconFileURL(for: feedID) else {
                feedIconLogger.debug("No cached icon for feed \(feedID.uuidString, privacy: .public) — awaiting next refresh")
                iconImage = nil
                return
            }
            // RATIONALE: Calls FeedIconService.hasVisibleContent directly rather than through
            // the FeedIconResolving protocol because it is a pure static utility with no I/O
            // or state — protocol abstraction would add complexity with no testability benefit.
            let image = await Task.detached(priority: .userInitiated) { [iconService] () -> UIImage? in
                guard let img = UIImage(contentsOfFile: fileURL.path(percentEncoded: false)) else {
                    feedIconLogger.warning("Cached icon file unreadable for feed \(feedID.uuidString, privacy: .public) at \(fileURL.path, privacy: .public) — deleting")
                    iconService.deleteCachedIcon(for: feedID)
                    return nil
                }
                guard FeedIconService.hasVisibleContent(img) else {
                    feedIconLogger.warning("Cached icon for feed \(feedID.uuidString, privacy: .public) has no visible content — deleting")
                    iconService.deleteCachedIcon(for: feedID)
                    return nil
                }
                return img
            }.value
            iconImage = image
        }
    }
}

// RATIONALE: File-private module-level logger so it can be accessed from inside
// `Task.detached` closures without crossing the `View`'s `@MainActor` isolation,
// matching the pattern used by `downloadRetryLogger` in ThumbnailPrefetchService.
private let feedIconLogger = Logger(category: "FeedIconView")
