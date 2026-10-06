import Foundation
import SwiftUI

/// Before/after: the photo on the leading side of a draggable divider, the template layer
/// on the trailing side. New template layers crossfade in. Pinch or double-tap zooms both
/// layers alike (up to `maxZoom`) to check an eye or a line of writing, and the zoom holds
/// while the sliders change the template; zoomed in, a drag pans and the divider moves by its
/// handle.
struct CompareView: View {
    let photo: CGImage
    let after: CGImage?
    /// Identity of `after`; a change crossfades.
    let afterID: String
    /// Names the template layer on the trailing side (already localized).
    let afterLabel: String
    let aspectRatio: CGFloat
    /// Fraction of the width showing the photo; purely presentational, so owned here.
    @State private var split: CGFloat = 0.5
    /// The layers' zoom (1 fits the frame) and offset from the frame's centre, as committed and
    /// as a gesture in progress shows them.
    @State private var zoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var liveZoom: CGFloat?
    @State private var liveOffset: CGSize?
    @State private var frameSize: CGSize = .zero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let maxZoom: CGFloat = 4
    /// Where a double tap zooms to.
    static let tapZoom: CGFloat = 2.5

    var body: some View {
        GeometryReader { geo in
            let width = max(0, geo.size.width)
            let x = min(max(width * (after == nil ? 1 : split), 0), width)
            ZStack(alignment: .topLeading) {
                ZStack {
                    if let after {
                        layer(after, size: geo.size)
                            .id(afterID)
                            .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: afterID)

                layer(photo, size: geo.size)
                    .mask(alignment: .leading) {
                        Rectangle().frame(width: x)
                    }

                if after != nil {
                    divider(at: x, height: geo.size.height, width: width)
                }
            }
            .frame(width: width, height: geo.size.height)
            .coordinateSpace(.named(Self.space))
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in
                        // A pinch's first finger isn't a drag.
                        guard liveZoom == nil else { return }
                        if shownZoom > 1 {
                            liveOffset = clamped(
                                CGSize(width: offset.width + value.translation.width, height: offset.height + value.translation.height),
                                zoom: shownZoom, in: geo.size)
                        } else {
                            moveDivider(to: value.location.x, width: width)
                        }
                    }
                    .onEnded { _ in
                        if let liveOffset { offset = liveOffset }
                        liveOffset = nil
                    }
            )
            .simultaneousGesture(
                MagnifyGesture()
                    .onChanged { value in
                        let z = min(max(zoom * value.magnification, 1), Self.maxZoom)
                        liveZoom = z
                        liveOffset = clamped(zoomedOffset(about: value.startLocation, to: z, in: geo.size), zoom: z, in: geo.size)
                    }
                    .onEnded { _ in
                        if let liveZoom { zoom = liveZoom }
                        if let liveOffset { offset = liveOffset }
                        liveZoom = nil
                        liveOffset = nil
                    }
            )
            .onTapGesture(count: 2, coordinateSpace: .local) { location in
                withAnimation(reduceMotion ? nil : .snappy) {
                    if zoom > 1 {
                        zoom = 1
                        offset = .zero
                    } else {
                        offset = clamped(zoomedOffset(about: location, to: Self.tapZoom, in: geo.size), zoom: Self.tapZoom, in: geo.size)
                        zoom = Self.tapZoom
                    }
                }
            }
            .overlay(alignment: .top) { labels(split: after == nil ? 1 : split) }
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { frameSize = $0 }
        .aspectRatio(aspectRatio, contentMode: .fit)
        .background(Theme.surface)
        .clipShape(.rect(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.12), radius: 20, x: 0, y: 10)
        // Another photo starts fitted.
        .onChange(of: ObjectIdentifier(photo)) {
            zoom = 1
            offset = .zero
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Comparison of photo and template")
        .accessibilityValue(accessibilityValue)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: split = min(1, split + 0.1)
            case .decrement: split = max(0, split - 0.1)
            @unknown default: break
            }
        }
        .accessibilityZoomAction { action in
            let z = action.direction == .zoomIn ? min(zoom * 1.5, Self.maxZoom) : max(zoom / 1.5, 1)
            offset = clamped(CGSize(width: offset.width * z / zoom, height: offset.height * z / zoom), zoom: z, in: frameSize)
            zoom = z
        }
        .accessibilityIdentifier("compare")
    }

    private var shownZoom: CGFloat { liveZoom ?? zoom }
    private var shownOffset: CGSize { liveOffset ?? offset }

    private var accessibilityValue: String {
        guard zoom > 1 else {
            return String(
                localized: "create.compare.value", defaultValue: "\(Int((split * 100).rounded())) percent photo",
                comment: "VoiceOver value of the before/after comparison: the whole percentage of the width showing the photo")
        }
        let photo = Double(split).formatted(.percent.precision(.fractionLength(0)))
        let zoomed = Double(zoom).formatted(.percent.precision(.fractionLength(0)))
        return String(
            localized: "create.compare.zoomedValue", defaultValue: "\(photo) photo, zoomed to \(zoomed)",
            comment: "VoiceOver value of the before/after comparison while zoomed in: the share of the width showing the photo and the zoom, both as percentages, e.g. 50% photo, zoomed to 250%")
    }

    private func moveDivider(to x: CGFloat, width: CGFloat) {
        guard after != nil, width > 0 else { return }
        split = min(max(x / width, 0), 1)
    }

    /// The offset that keeps the content under `location` (in the frame) where it is while the
    /// zoom goes to `z`.
    private func zoomedOffset(about location: CGPoint, to z: CGFloat, in size: CGSize) -> CGSize {
        let p = CGPoint(x: location.x - size.width / 2, y: location.y - size.height / 2)
        let ratio = z / max(zoom, 1)
        return CGSize(width: p.x - (p.x - offset.width) * ratio, height: p.y - (p.y - offset.height) * ratio)
    }

    /// `offset` limited so the zoomed layers still cover the frame.
    private func clamped(_ offset: CGSize, zoom z: CGFloat, in size: CGSize) -> CGSize {
        let x = (z - 1) * size.width / 2, y = (z - 1) * size.height / 2
        return CGSize(width: min(max(offset.width, -x), x), height: min(max(offset.height, -y), y))
    }

    /// Fills exactly `size`, so masks line up with the container, zoomed and moved as shown.
    private func layer(_ image: CGImage, size: CGSize) -> some View {
        Image(decorative: image, scale: 1)
            .resizable()
            .interpolation(.high)
            .scaledToFill()
            .frame(width: size.width, height: size.height)
            .scaleEffect(shownZoom)
            .offset(shownOffset)
            .frame(width: size.width, height: size.height)
            .clipped()
    }

    /// The divider's handle drags it whatever the zoom.
    private func divider(at x: CGFloat, height: CGFloat, width: CGFloat) -> some View {
        ZStack {
            Rectangle()
                .fill(.white)
                .frame(width: 2.5, height: height)
                .shadow(color: .black.opacity(0.3), radius: 3)
                .allowsHitTesting(false)
            Image(systemName: "arrow.left.and.right")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .glassEffect(.regular.interactive(), in: .circle)
                .highPriorityGesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
                        .onChanged { value in moveDivider(to: value.location.x, width: width) }
                )
        }
        .position(x: x, y: height / 2)
    }

    private static let space = "compare"

    private func labels(split: CGFloat) -> some View {
        HStack {
            caption(String(localized: "Photo")).opacity(split > 0.16 ? 1 : 0)
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
    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.black.opacity(0.62), in: .capsule)
    }
}
