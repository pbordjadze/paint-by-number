#if UNRELEASED
import Foundation
import SwiftUI

/// Opening a painting from the gallery as stepping through an arch (painting-company row 332; the
/// mockups' transition, `factory/pieces/doors/`): the card's picture becomes an arch, which grows
/// into the room while the gallery falls back into the dark behind it; at the end its top flattens
/// and you're standing in the painting. Only on the way in from a card: the way back is the zoom
/// to the card, as before. SideStore and Debug builds until Paul has seen it.
///
/// The arch is the app shell's overlay. Once it fills the screen the shell pushes the painting
/// under it as Start Painting does under the create flow's cover (`StartHandoff`): the usual push,
/// unseen, the painting mounting without its fades. When the canvas reports where its page is, the
/// picture settles there and the arch fades, leaving the canvas's identical page; a painting that
/// hasn't drawn in time (`StartHandoffPlan.fallback`) is faded to all the same. Reduce Motion
/// cross-fades. The overlay takes no touches and VoiceOver doesn't see it.
nonisolated struct ArchOpening: Equatable, Sendable {
    let artwork: Artwork
    /// The card's picture, in the window's coordinates.
    let from: CGRect
    let id = UUID()
}

/// The cards' pictures' places in the window, kept for the arch to start from. Written as the
/// gallery scrolls, read only on a tap: not observed, so nothing renders again for it.
final class CardPlaces {
    private(set) var rects: [UUID: CGRect] = [:]

    func set(_ rect: CGRect, for id: UUID) { rects[id] = rect }
}

struct ArchOpeningView: View {
    let opening: ArchOpening
    let handoff: StartHandoff
    /// The arch fills the screen: the shell pushes the painting under it.
    let onCovered: () -> Void
    /// The arch has faded: the shell takes it away.
    let onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage(SettingsKey.paletteRows) private var paletteRows = PaletteRows.default
    @State private var grown = false
    @State private var flat = false
    @State private var landed: CGRect?
    @State private var faded = false
    /// The arch filled the screen and the painting was pushed under it.
    @State private var covered = false

    /// How long the arch takes to fill the screen.
    static let growth: Double = 0.5
    /// The flattening of its top, at the end of the growth.
    static let flattening: Double = 0.18
    static let settle: Double = 0.18
    static let fade: Double = 0.25
    /// How dark the gallery falls behind the arch.
    static let dusk: Double = 0.72

    var body: some View {
        GeometryReader { geo in
            let screen = CGRect(
                x: 0, y: 0, width: geo.size.width + geo.safeAreaInsets.leading + geo.safeAreaInsets.trailing,
                height: geo.size.height + geo.safeAreaInsets.top + geo.safeAreaInsets.bottom)
            let origin = geo.frame(in: .global).origin
            let window = CGPoint(x: origin.x - geo.safeAreaInsets.leading, y: origin.y - geo.safeAreaInsets.top)
            let start = startArch(from: opening.from.offsetBy(dx: -window.x, dy: -window.y))
            let arch = grown || reduceMotion ? screen : start
            let page = landed?.offsetBy(dx: -window.x, dy: -window.y) ?? expectedPage(geo: geo, screen: screen)
            let picture = grown || reduceMotion ? page : filling(start)
            ZStack(alignment: .topLeading) {
                Color(red: 0.07, green: 0.04, blue: 0.09)
                    .opacity(grown && !reduceMotion ? Self.dusk : 0)
                ZStack(alignment: .topLeading) {
                    Theme.paper
                    ArtworkThumbnail(artwork: opening.artwork, contentMode: .fill)
                        .frame(width: picture.width, height: picture.height)
                        .clipped()
                        .offset(x: picture.minX, y: picture.minY)
                }
                .frame(width: screen.width, height: screen.height)
                .mask(alignment: .topLeading) {
                    ArchShape(roundness: flat || reduceMotion ? 0 : 1, footRadius: flat || reduceMotion ? 0 : 10)
                        .frame(width: arch.width, height: arch.height)
                        .offset(x: arch.minX, y: arch.minY)
                }
                // The moonlight around the doorway as it opens.
                ArchShape(roundness: flat ? 0 : 1, footRadius: flat ? 0 : 10)
                    .stroke(Color(red: 1, green: 0.965, blue: 0.88).opacity(flat || reduceMotion ? 0 : 0.6), lineWidth: 3)
                    .shadow(color: Color(red: 1, green: 0.94, blue: 0.82).opacity(0.5), radius: 18)
                    .frame(width: arch.width, height: arch.height)
                    .offset(x: arch.minX, y: arch.minY)
            }
            .frame(width: screen.width, height: screen.height, alignment: .topLeading)
            .opacity(faded ? 0 : (reduceMotion && !grown ? 0 : 1))
            .ignoresSafeArea()
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear(perform: grow)
        .onChange(of: handoff.phase) { _, phase in arrive(phase) }
    }

    private func grow() {
        let growth = reduceMotion ? Self.fade : Self.growth
        withAnimation(reduceMotion ? .easeOut(duration: growth) : .timingCurve(0.65, 0, 0.35, 1, duration: growth)) {
            grown = true
        } completion: {
            covered = true
            onCovered()
        }
        if !reduceMotion {
            withAnimation(.easeIn(duration: Self.flattening).delay(Self.growth - Self.flattening)) { flat = true }
        }
    }

    /// The painting has drawn (its page at the rect, in the window's coordinates), or won't in time.
    private func arrive(_ phase: StartHandoffLogic.Phase) {
        switch phase {
        case .ready(let id, let rect) where id == opening.artwork.id && !faded:
            withAnimation(reduceMotion ? nil : .easeOut(duration: Self.settle)) {
                landed = rect
            } completion: {
                dissolve()
            }
        case .timedOut(let id) where id == opening.artwork.id && !faded:
            dissolve()
        case .idle where covered && !faded:
            // The hand-off was called off under the arch (a file opened from another app): the arch
            // goes with it, completing nothing.
            dissolve(completes: false)
        default:
            break
        }
    }

    private func dissolve(completes: Bool = true) {
        guard !faded else { return }
        withAnimation(.easeOut(duration: Self.fade)) {
            faded = true
        } completion: {
            if completes { handoff.complete() }
            onFinished()
        }
    }

    /// The card's picture, a little taller with a round top: the doorway it becomes.
    private func startArch(from card: CGRect) -> CGRect {
        let rise = card.width * 0.18
        return CGRect(x: card.minX, y: card.minY - rise, width: card.width, height: card.height + rise)
    }

    /// The painting's picture filling the arch, as the card's does.
    private func filling(_ arch: CGRect) -> CGRect {
        let ratio = max(opening.artwork.aspectRatio, 0.01)
        let size = arch.width / arch.height > ratio
            ? CGSize(width: arch.width, height: arch.width / ratio)
            : CGSize(width: arch.height * ratio, height: arch.height)
        return CGRect(x: arch.midX - size.width / 2, y: arch.midY - size.height / 2, width: size.width, height: size.height)
    }

    /// Where the painting screen will put the page (`PaintingLayout`), until the canvas says.
    private func expectedPage(geo: GeometryProxy, screen: CGRect) -> CGRect {
        let inputs = PaintingLayout.Inputs(
            size: geo.size, safe: geo.safeAreaInsets, regularWidth: sizeClass == .regular,
            dynamicTypeSize: dynamicTypeSize, rows: paletteRows, colors: max(1, opening.artwork.colorCount),
            isComplete: opening.artwork.isComplete,
            completionHeight: opening.artwork.isComplete ? expectedPanel(geo: geo) : nil)
        let page = PaintingLayout(inputs).page(
            of: CGSize(width: opening.artwork.width, height: opening.artwork.height), inputs: inputs, rightToLeft: false)
        return page.isPlace ? page : screen.insetBy(dx: 20, dy: screen.height * 0.2)
    }

    /// A finished painting's Finished panel with its doors, as `PaintView` will lay it.
    private func expectedPanel(geo: GeometryProxy) -> CGFloat? {
        let width = min(CompletionBar.panelWidth, geo.size.width - 2 * PaintingLayout.edge) - 2 * CompletionBar.doorsInset
        let room = geo.size.height * PaintingLayout.doorsShare(compactHeight: verticalSizeClass == .compact)
        let size = min(dynamicTypeSize, .xxLarge)
        guard let doors = DoorMetrics.fitting(
            count: FinishedDoor.allCases.count, width: width,
            height: room - CompletionBar.height - CompletionBar.doorsInset, dynamicTypeSize: size)
        else { return nil }
        let rows = CGFloat(doors.rows)
        return CompletionBar.height + CompletionBar.doorsInset
            + rows * (doors.arch.height + DoorMetrics.labelGap + DoorMetrics.labelHeight(size))
            + (rows - 1) * DoorMetrics.rowGap
    }
}
#endif
