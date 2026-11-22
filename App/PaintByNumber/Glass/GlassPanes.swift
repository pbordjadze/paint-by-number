#if UNRELEASED
import CoreGraphics
import Observation
import PaintCore
import SwiftUI
import UIKit

/// The window's glass as Apple's own Liquid Glass (painting-company row 366; Paul, November 22,
/// 2026: the glass material the star): every framed piece a pane of real glass set in its lead,
/// over the canvas, which keeps the photo, the lead, the numbers and the light (`GlassMode`, its
/// lenses then drawn flat: `lensesCovered`). The panes are grouped, one glass effect per glass and
/// one for the clear lenses, each a shape of many outlines: measured on an iPad Air, 120 panes so
/// grouped stayed smooth where 60 effects of one pane each did not (`GlassRealPanes`). A pane comes
/// as its piece is framed (the clear lens materializing) or poured (its glass materializing, then
/// melting into the panes of the same glass beside it and snapping back to the lead); never under
/// Reduce Motion. Under Reduce Transparency there is no real glass: the canvas's lenses draw whole.
///
/// It lives in the canvas's zooming view (`CanvasView.modeOverlay`), in canvas units, so UIKit's
/// pan and zoom move it with no SwiftUI work.
@MainActor
@Observable
final class GlassPanes {
    /// Each piece's glass, inset half the lead inside its outline, and its neighbours, made off the
    /// main actor (`outlines(of:)`).
    nonisolated struct Outlines: @unchecked Sendable {
        /// Canvas units; nil where the lead covers the piece whole.
        let paths: [CGPath?]
        let neighbours: [[Int]]
        let lead: CGFloat
        let size: CGSize
    }

    /// What a piece holds: nil, no glass (not yet framed); `clear`, the clear lens; g + 1, glass g.
    typealias Hold = Int
    static let clear: Hold = 0

    let outlines: Outlines
    /// The glasses offered, as their panes are tinted.
    let tints: [Color]
    @ObservationIgnored private var holds: [Hold?]
    @ObservationIgnored private var members: [Set<Int>]
    /// One shape per hold, rebuilt only for the holds a change touched.
    private(set) var shapes: [Path]
    /// Panes arriving: each its own effect for a moment, so it can materialize and melt.
    private(set) var arrivals: [Arrival] = []
    @ObservationIgnored private var nextArrival = 0
    /// Real glass is on screen (no Reduce Transparency): the canvas draws its lenses flat under it.
    @ObservationIgnored var onCover: @MainActor (Bool) -> Void = { _ in }

    /// How much of a glass's color its pane carries; the canvas pours the rest into the photo.
    static let tintOpacity = 0.35
    /// How long a pane takes to arrive, materializing and melting, before it joins its glass.
    static let arrivalDuration = 0.9

    struct Arrival: Identifiable {
        let id: Int
        let hold: Hold
        /// The pieces arriving (each its own pane) and those melting with them (shown as they were).
        var pieces: [Int]
        let fresh: Set<Int>
        let melts: Bool
        let start: Date
    }

    init(outlines: Outlines, offered: [PaletteColor], colorSpace: RGBColorSpace) {
        self.outlines = outlines
        tints = offered.map { GlassPicture.color($0.rgb, space: colorSpace).opacity(Self.tintOpacity) }
        holds = Array(repeating: nil, count: outlines.paths.count)
        members = Array(repeating: [], count: offered.count + 1)
        shapes = Array(repeating: Path(), count: offered.count + 1)
    }

    var size: CGSize { outlines.size }

    func glass(_ hold: Hold) -> Glass {
        hold == Self.clear ? .clear : .clear.tint(tints[hold - 1])
    }

    /// Piece `r` now holds `hold`; `arriving`, it comes as a pane of its own (framed or poured on
    /// screen), and a poured one melts into the same glass beside it.
    func show(_ r: Int, hold: Hold?, arriving: Bool) {
        guard r < holds.count else { return }
        let hold = hold.flatMap { $0 < members.count ? $0 : nil }
        var touched = Set<Int>()
        if let before = holds[r] { members[before].remove(r); touched.insert(before) }
        holds[r] = hold
        if let hold { members[hold].insert(r); touched.insert(hold) }
        leaveArrivals(r, touched: &touched)
        if arriving, let hold, outlines.paths[r] != nil { arrive(r, hold: hold, touched: &touched) }
        rebuild(touched)
    }

    /// Every piece as it stands, with no pane arriving.
    func showAll(_ holdOf: (Int) -> Hold?) {
        arrivals = []
        members = members.map { _ in [] }
        for r in holds.indices {
            let hold = holdOf(r).flatMap { $0 < members.count ? $0 : nil }
            holds[r] = hold
            if let hold { members[hold].insert(r) }
        }
        rebuild(Set(members.indices))
    }

    func covers(_ covered: Bool) { onCover(covered) }

    private func leaveArrivals(_ r: Int, touched: inout Set<Int>) {
        for k in arrivals.indices where arrivals[k].pieces.contains(r) {
            arrivals[k].pieces.removeAll { $0 == r }
            touched.insert(arrivals[k].hold)
        }
        arrivals.removeAll { $0.pieces.isEmpty }
    }

    private func arrive(_ r: Int, hold: Hold, touched: inout Set<Int>) {
        let now = Date.now
        let melts = hold != Self.clear
        // Pieces framed by one stroke arrive together.
        if !melts, let last = arrivals.indices.last, arrivals[last].hold == hold, !arrivals[last].melts,
           now.timeIntervalSince(arrivals[last].start) < 0.05 {
            let joined = arrivals[last]
            withAnimation(.smooth(duration: 0.5)) {
                arrivals[last] = Arrival(id: joined.id, hold: hold, pieces: joined.pieces + [r], fresh: joined.fresh.union([r]),
                                         melts: false, start: joined.start)
            }
            return
        }
        let arriving = Set(arrivals.flatMap(\.pieces))
        let beside = melts ? outlines.neighbours[r].filter { holds[$0] == hold && !arriving.contains($0) && outlines.paths[$0] != nil } : []
        nextArrival += 1
        let arrival = Arrival(id: nextArrival, hold: hold, pieces: [r] + beside, fresh: [r], melts: melts, start: now)
        withAnimation(.smooth(duration: 0.5)) { arrivals.append(arrival) }
        touched.insert(hold)
        let id = arrival.id
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.arrivalDuration))
            self?.settle(id)
        }
    }

    /// An arrival over: its panes join their glass's shape, with no transition.
    private func settle(_ id: Int) {
        guard let k = arrivals.firstIndex(where: { $0.id == id }) else { return }
        let hold = arrivals[k].hold
        var quiet = Transaction(animation: nil)
        quiet.disablesAnimations = true
        withTransaction(quiet) {
            arrivals.remove(at: k)
            rebuild([hold])
        }
    }

    private func rebuild(_ touched: Set<Int>) {
        let arriving = Set(arrivals.flatMap(\.pieces))
        for hold in touched where hold < shapes.count {
            let path = CGMutablePath()
            for r in members[hold] where !arriving.contains(r) {
                if let outline = outlines.paths[r] { path.addPath(outline) }
            }
            shapes[hold] = Path(path)
        }
    }

    func path(of r: Int) -> Path {
        outlines.paths[r].map { Path($0) } ?? Path()
    }

    /// How far the panes melt `elapsed` seconds into a pour: the container's spacing grows past
    /// the lead between them, holds, and snaps back before the pane joins its glass.
    func meltSpacing(at date: Date) -> CGFloat {
        let gap = outlines.lead
        var spacing: CGFloat = 0
        for arrival in arrivals where arrival.melts {
            let t = date.timeIntervalSince(arrival.start)
            let rise = min(1, max(0, t / 0.3)), fall = min(1, max(0, (t - 0.55) / 0.3))
            let ease = { (x: Double) in x * x * (3 - 2 * x) }
            spacing = max(spacing, 1.6 * gap * CGFloat(ease(rise) * (1 - ease(fall))))
        }
        return spacing
    }

    var melting: Bool { arrivals.contains { $0.melts } }

    /// The panes of `template`'s pieces: each piece's rings less a band of the lead's width along
    /// them (`lead`, canvas units), so a pane sits in the lead with the came over its edge.
    nonisolated static func outlines(of template: Template, lead: CGFloat) -> Outlines {
        var paths: [CGPath?] = []
        paths.reserveCapacity(template.regions.count)
        for r in template.regions.indices {
            let piece = CGMutablePath()
            for polygon in template.polygons(ofRegion: r) where polygon.count >= 3 {
                piece.addLines(between: polygon.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)) })
                piece.closeSubpath()
            }
            let band = piece.copy(strokingWithWidth: lead, lineCap: .round, lineJoin: .round, miterLimit: 10)
            let pane = piece.subtracting(band, using: .evenOdd)
            let box = pane.boundingBoxOfPath
            paths.append(pane.isEmpty || box.width < 1 || box.height < 1 ? nil : pane)
        }
        var neighbours = Array(repeating: Set<Int>(), count: template.regions.count)
        for edge in template.edges where edge.right != BoundaryEdge.outside {
            let a = Int(edge.left), b = Int(edge.right)
            guard a < neighbours.count, b < neighbours.count, a != b else { continue }
            neighbours[a].insert(b)
            neighbours[b].insert(a)
        }
        return Outlines(paths: paths, neighbours: neighbours.map { $0.sorted() }, lead: lead,
                        size: CGSize(width: template.width, height: template.height))
    }
}

/// The panes, in canvas units, laid in the canvas's zooming view (`CanvasView.modeOverlay`).
struct GlassPanesView: View {
    let panes: GlassPanes
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack(alignment: .topLeading) {
            if !reduceTransparency {
                GlassEffectContainer(spacing: 0) {
                    ZStack(alignment: .topLeading) {
                        ForEach(panes.shapes.indices, id: \.self) { hold in
                            if !panes.shapes[hold].isEmpty {
                                pane(panes.shapes[hold], hold: hold)
                            }
                        }
                    }
                }
                arriving
            }
        }
        .frame(width: panes.size.width, height: panes.size.height, alignment: .topLeading)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: reduceTransparency, initial: true) { _, reduced in panes.covers(!reduced) }
    }

    /// The panes arriving, each its own effect in a container whose spacing melts them together
    /// (frames drawn only while one melts).
    private var arriving: some View {
        TimelineView(.animation(paused: !panes.melting)) { timeline in
            GlassEffectContainer(spacing: panes.meltSpacing(at: timeline.date)) {
                ZStack(alignment: .topLeading) {
                    ForEach(panes.arrivals) { arrival in
                        ForEach(arrival.pieces, id: \.self) { r in
                            pane(panes.path(of: r), hold: arrival.hold)
                                .glassEffectTransition(arrival.fresh.contains(r) ? .materialize : .identity)
                        }
                    }
                }
            }
        }
    }

    private func pane(_ path: Path, hold: GlassPanes.Hold) -> some View {
        Color.clear
            .frame(width: panes.size.width, height: panes.size.height)
            .glassEffect(panes.glass(hold), in: PaneOutline(path: path))
    }
}

/// A shape already laid out in canvas units.
nonisolated private struct PaneOutline: Shape {
    let path: Path

    func path(in rect: CGRect) -> Path { path }
}
#endif
