import CoreGraphics
import Foundation
import SwiftUI

// Small departures from stock motion and marks that make the app its own (painting-company row
// 351; the mock page `factory/pieces/quirks/`): one house curve that settles, progress as a waxing
// moon, the gallery's paintings coming out like stars, a closed painting set down by hand, Show
// Photo opening as a lantern (`CanvasView.photoIsLantern`) and a color's name rolling into place
// (`CurrentColorLabel`, through `EraSeam.rollsLabels`). SideStore and Debug builds only
// (`UNRELEASED`); the release keeps the stock choices. Each is calm: slower than the default, never
// bigger, and gone under Reduce Motion.

extension Animation {
    /// The house curve: what the app slides in or out of its own panels arrives a little slower
    /// than `.snappy` and settles with about 1% of overshoot, like a sheet of paper laid down.
    nonisolated static var settle: Animation {
        #if UNRELEASED
        .spring(duration: 0.6, bounce: 0.18)
        #else
        .snappy
        #endif
    }
}

#if UNRELEASED
/// Progress as the moon waxing from new to full, lit in the tint: a gallery card's in SideStore and
/// Debug builds, where the release draws a `ProgressRing`.
struct ProgressMoon: View {
    var fraction: Double
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Circle().fill(.tint.opacity(ProgressRing.trackOpacity(for: colorScheme)))
            MoonPhase(fraction: fraction).fill(.tint)
        }
        .accessibilityHidden(true)
    }
}

/// The lit part of a moon `fraction` of the way from new (nothing) to full (the whole disc),
/// waxing from the trailing side as the moon does seen from the north: a crescent, then a half,
/// then gibbous.
nonisolated struct MoonPhase: Shape {
    var fraction: Double

    var animatableData: Double {
        get { fraction }
        set { fraction = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let f = max(0, min(fraction, 1))
        let r = min(rect.width, rect.height) / 2
        let c = CGPoint(x: rect.midX, y: rect.midY)
        var path = Path()
        guard f > 0.001, r > 0 else { return path }
        guard f < 0.999 else {
            path.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
            return path
        }
        // A quarter of an ellipse as one cubic: `k` places its control points.
        let k = 0.552_284_75
        let top = CGPoint(x: c.x, y: c.y - r), bottom = CGPoint(x: c.x, y: c.y + r)
        // The lit limb: the trailing half of the disc, top to bottom.
        path.move(to: top)
        path.addCurve(to: CGPoint(x: c.x + r, y: c.y),
                      control1: CGPoint(x: c.x + r * k, y: c.y - r), control2: CGPoint(x: c.x + r, y: c.y - r * k))
        path.addCurve(to: bottom,
                      control1: CGPoint(x: c.x + r, y: c.y + r * k), control2: CGPoint(x: c.x + r * k, y: c.y + r))
        // The terminator, back to the top: half an ellipse bulging toward the lit side before
        // the half moon (a crescent), away from it after.
        let x = r * (1 - 2 * f)
        path.addCurve(to: CGPoint(x: c.x + x, y: c.y),
                      control1: CGPoint(x: c.x + x * k, y: c.y + r), control2: CGPoint(x: c.x + x, y: c.y + r * k))
        path.addCurve(to: top,
                      control1: CGPoint(x: c.x + x, y: c.y - r * k), control2: CGPoint(x: c.x + x * k, y: c.y - r))
        path.closeSubpath()
        return path
    }
}

/// The gallery's paintings come out one at a time in an uneven order as it first appears after a
/// launch, each rising a few points as it fades in, the way stars come out at dusk. Later
/// appearances, scrolling and the way back from a painting show them at once.
@MainActor
enum StarsComeOut {
    /// Where each card stood in the gallery as it was first laid out, and until when one coming
    /// into being comes out; nil until then.
    private static var positions: [UUID: Int]?
    private static var until = Date.distantPast

    /// The delay after which the card of `id` comes out, or nil: it shows at once. The first call
    /// opens the gallery's moment, with the cards in `ids`' order.
    static func delay(for id: UUID, among ids: @autoclosure () -> [UUID]) -> Double? {
        if positions == nil {
            positions = Dictionary(ids().enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
            until = Date().addingTimeInterval(1.2)
            #if DEBUG
            // Screenshots and UI tests see the gallery as it rests.
            if DemoMode.isActive || DemoMode.isTestHost { until = .distantPast }
            #endif
        }
        guard Date() < until, let position = positions?[id] else { return nil }
        // An uneven order over the first six, the rest after them.
        let order = [2, 0, 4, 1, 5, 3]
        return 0.15 * Double(position < order.count ? order[position] : order.count)
    }
}

private struct ComesOut: ViewModifier {
    /// Decided once, as the card is first made: a card made again later shows at once.
    @State private var delay: Double?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(delay: Double?) {
        _delay = State(initialValue: delay)
    }

    func body(content: Content) -> some View {
        let hidden = delay != nil && !reduceMotion
        content
            .opacity(hidden ? 0 : 1)
            .offset(y: hidden ? 6 : 0)
            .onAppear {
                guard let wait = delay, !reduceMotion else { return }
                withAnimation(.easeOut(duration: 0.8).delay(wait)) { delay = nil }
            }
    }
}

/// A gallery card set back down when its painting closes: it lands tilted a couple of degrees and
/// straightens on the house curve, as a picture put back on a shelf by hand.
private struct SetDown: ViewModifier {
    let isSettling: Bool
    @State private var tilt = 0.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(tilt), anchor: UnitPoint(x: 0.5, y: 0.6))
            .onChange(of: isSettling) { _, settling in
                guard settling, !reduceMotion else { return }
                var still = Transaction()
                still.disablesAnimations = true
                withTransaction(still) { tilt = -2.5 }
                // Once the zoom back has about landed on the card.
                withAnimation(.spring(duration: 0.7, bounce: 0.3).delay(0.3)) { tilt = 0 }
            }
    }
}

extension EnvironmentValues {
    /// The gallery card whose painting is closing, to be set down (`SetDown`); from `AppShellView`.
    @Entry var settlingCard: UUID?
}

extension View {
    /// A gallery card's coming out (`StarsComeOut`); nil shows it at once.
    func comesOut(after delay: Double?) -> some View {
        modifier(ComesOut(delay: delay))
    }

    /// A gallery card set down as its painting closes (`SetDown`).
    func setsDown(_ isSettling: Bool) -> some View {
        modifier(SetDown(isSettling: isSettling))
    }
}
#endif
