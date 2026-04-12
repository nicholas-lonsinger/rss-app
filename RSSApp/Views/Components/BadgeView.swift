import SwiftUI

/// A blue capsule badge displaying a numeric count.
///
/// Renders nothing when `count` is zero or negative, so call sites can
/// pass the raw count without a guard.
struct BadgeView: View {
    let count: Int

    var body: some View {
        // Negative counts are treated the same as zero and produce no badge.
        if count > 0 {
            Text("\(count)")
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.blue)
                .foregroundStyle(.white)
                .clipShape(Capsule())
        }
    }
}
