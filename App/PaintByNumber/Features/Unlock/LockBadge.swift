import SwiftUI

/// The small lock on a tile that waits for Unlimited Paintings (Blank Page; ✎ Change carries its
/// own inside its glass, `GlassIconButton.badge`), shown while it isn't bought, so the purchase it
/// opens is no surprise (QA, painting-company row 237). The control's VoiceOver value says it in
/// words; the lock itself is hidden from VoiceOver.
struct LockBadge: View {
    @ScaledMetric(relativeTo: .caption2) private var side: CGFloat = 18

    var body: some View {
        Image(systemName: "lock.fill")
            .font(.system(size: side * 0.5, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: side, height: side)
            .background(.regularMaterial, in: .circle)
            .accessibilityHidden(true)
    }
}
