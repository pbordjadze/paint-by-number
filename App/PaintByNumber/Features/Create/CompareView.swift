import SwiftUI

/// Before/after: the photo on the leading side of a draggable divider, the template layer
/// on the trailing side. New template layers crossfade in.
struct CompareView: View {
    let photo: CGImage?
    let after: CGImage?
    /// Identity of `after`; a change crossfades.
    let afterID: String
    let afterLabel: LocalizedStringKey
    let aspectRatio: CGFloat
    /// Fraction of the width showing the photo; purely presentational, so owned here.
    @State private var split: CGFloat

    init(photo: CGImage?, after: CGImage?, afterID: String, afterLabel: LocalizedStringKey, aspectRatio: CGFloat, initialSplit: CGFloat = 0.5) {
        self.photo = photo
        self.after = after
        self.afterID = afterID
        self.afterLabel = afterLabel
        self.aspectRatio = aspectRatio
        _split = State(initialValue: initialSplit)
    }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let x = width * (after == nil ? 1 : split)
            ZStack(alignment: .topLeading) {
                ZStack {
                    if let after {
                        layer(after, size: geo.size)
                            .id(afterID)
                            .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: afterID)

                if let photo {
                    layer(photo, size: geo.size)
                        .mask(alignment: .leading) {
                            Rectangle().frame(width: x)
                        }
                }

                if after != nil {
                    divider(at: x, height: geo.size.height)
                }
            }
            .frame(width: width, height: geo.size.height)
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard after != nil, width > 0 else { return }
                        split = min(max(value.location.x / width, 0), 1)
                    }
            )
            .overlay(alignment: .top) { labels(split: after == nil ? 1 : split) }
        }
        .aspectRatio(aspectRatio, contentMode: .fit)
        .background(Theme.surface)
        .clipShape(.rect(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.12), radius: 20, x: 0, y: 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Comparison of photo and template")
        .accessibilityValue("\(Int((split * 100).rounded())) percent photo")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: split = min(1, split + 0.1)
            case .decrement: split = max(0, split - 0.1)
            @unknown default: break
            }
        }
    }

    /// Fills exactly `size`, so masks line up with the container.
    private func layer(_ image: CGImage, size: CGSize) -> some View {
        Image(decorative: image, scale: 1)
            .resizable()
            .interpolation(.high)
            .scaledToFill()
            .frame(width: size.width, height: size.height)
            .clipped()
    }

    private func divider(at x: CGFloat, height: CGFloat) -> some View {
        ZStack {
            Rectangle()
                .fill(.white)
                .frame(width: 2.5, height: height)
                .shadow(color: .black.opacity(0.3), radius: 3)
            Image(systemName: "arrow.left.and.right")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .glassEffect(.regular.interactive(), in: .circle)
        }
        .position(x: x, y: height / 2)
    }

    private func labels(split: CGFloat) -> some View {
        HStack {
            caption("Photo").opacity(split > 0.16 ? 1 : 0)
            Spacer()
            caption(afterLabel).opacity(split < 0.84 ? 1 : 0)
        }
        .padding(12)
        .animation(.easeOut(duration: 0.15), value: split > 0.16)
        .animation(.easeOut(duration: 0.15), value: split < 0.84)
        .allowsHitTesting(false)
    }

    // Not named `tag`: that would resolve `tag("Photo")` to `View.tag(_:)` on `self` and nest
    // the whole comparison inside its own overlay, recursing until the stack overflows.
    /// White on a dark scrim: legible over any photo, light or dark.
    private func caption(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.rounded(.caption, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.black.opacity(0.62), in: .capsule)
    }
}
