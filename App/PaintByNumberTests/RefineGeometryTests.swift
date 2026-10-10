import CoreGraphics
import Foundation
import Testing
@testable import PaintByNumber

/// Refine's geometry: the pen's line smoothed and thinned, and the line a tap of the eraser takes.
struct RefineGeometryTests {
    /// A shaky line comes out smooth, from its first point to its last, and thinned to fewer
    /// points; a straight one to its two ends.
    @Test func penLinesAreSmoothedAndThinned() {
        let shaky = (0...40).map { CGPoint(x: CGFloat($0) * 5, y: $0 % 2 == 0 ? 0 : 1.5) }
        let smooth = PenPath.smoothed(shaky, spacing: 2)
        #expect(smooth.first == shaky.first && smooth.last == shaky.last)
        // Away from its ends the wobble is averaged out: no point strays as far as the samples did.
        #expect(smooth.filter { $0.x > 20 && $0.x < 180 }.allSatisfy { $0.y > 0.2 && $0.y < 1.3 })
        let thin = PenPath.simplified(smooth, tolerance: 0.5)
        #expect(thin.count < smooth.count && thin.first == smooth.first && thin.last == smooth.last)
        let straight = (0...20).map { CGPoint(x: CGFloat($0) * 3, y: CGFloat($0) * 2) }
        #expect(PenPath.simplified(PenPath.smoothed(straight, spacing: 2), tolerance: 0.3).count == 2)
        #expect(abs(PenPath.length(straight) - hypot(60, 40)) < 1e-6)
    }

    /// A tap takes the line under it on through every joint where just one other line goes on,
    /// and stops where three lines meet or a line ends; a loop comes back to where it started;
    /// nothing is taken where no line is near.
    @Test func tappedLinesRunFromJunctionToJunction() throws {
        func line(_ points: [SIMD2<Float>]) -> LineArtDrawing.Line { LineArtDrawing.Line(points[...])! }
        // Two lines end to end, meeting two more where three meet; one apart.
        let chains = LineChains(lines: [
            line([SIMD2(0, 0), SIMD2(10, 0)]), line([SIMD2(20, 0), SIMD2(10, 0)]),
            line([SIMD2(20, 0), SIMD2(20, 10)]), line([SIMD2(20, 0), SIMD2(30, 0)]),
            line([SIMD2(0, 20), SIMD2(30, 20)]),
        ])
        let joined = try #require(chains.chain(near: CGPoint(x: 5, y: 1), tolerance: 3))
        #expect(joined == [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0), CGPoint(x: 20, y: 0)])
        let branch = try #require(chains.chain(near: CGPoint(x: 21, y: 6), tolerance: 3))
        #expect(branch == [CGPoint(x: 20, y: 0), CGPoint(x: 20, y: 10)])
        let apart = try #require(chains.chain(near: CGPoint(x: 12, y: 19), tolerance: 3))
        #expect(apart == [CGPoint(x: 0, y: 20), CGPoint(x: 30, y: 20)])
        #expect(chains.chain(near: CGPoint(x: 10, y: 10), tolerance: 3) == nil)

        let loop = LineChains(lines: [
            line([SIMD2(0, 0), SIMD2(10, 0), SIMD2(10, 10)]), line([SIMD2(10, 10), SIMD2(0, 10), SIMD2(0, 0)]),
        ])
        let ring = try #require(loop.chain(near: CGPoint(x: 5, y: 0.5), tolerance: 2))
        #expect(ring.count == 5 && ring.first == ring.last)
    }

    // MARK: - The pens' help

    static func near(_ p: CGPoint?, _ q: CGPoint, within tolerance: CGFloat = 1e-6) -> Bool {
        p.map { PenPath.distance($0, q) <= tolerance } ?? false
    }

    /// A hand's straight stroke counts as straight, a gentle arc or a stroke that doubles back
    /// doesn't; a short stroke's wobble is judged by the floor.
    @Test func nearlyStraightLinesAreFound() {
        let wobbly = (0...40).map { CGPoint(x: CGFloat($0) * 5, y: 3 * sin(CGFloat($0) * 0.7)) }
        #expect(PenAssist.isNearlyStraight(wobbly, floor: 2))
        // An arc turning 40°: it bulges by about 9 % of its chord.
        let arc = (0...40).map { k -> CGPoint in
            let a = (CGFloat(k) / 40 - 0.5) * 40 * .pi / 180
            return CGPoint(x: 300 * sin(a), y: 300 * (1 - cos(a)))
        }
        #expect(!PenAssist.isNearlyStraight(arc, floor: 2))
        let doubledBack = [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 1), CGPoint(x: 40, y: 0), CGPoint(x: 120, y: 1)]
        #expect(!PenAssist.isNearlyStraight(doubledBack, floor: 2))
        let short = [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 1.5), CGPoint(x: 20, y: 0)]
        #expect(PenAssist.isNearlyStraight(short, floor: 2) && !PenAssist.isNearlyStraight(short, floor: 1))
        #expect(PenAssist.deviation(short) == 1.5)
    }

    /// The Smart Pen's straight line ending short of a line ends on it, still straight; its other
    /// end, near nothing, stays.
    @Test func aStraightLineJoinsTheLineItStopsShortOf() {
        let lines = SnapLines([[CGPoint(x: 100, y: 0), CGPoint(x: 100, y: 200)]])
        let joined = PenAssist.joined(
            [CGPoint(x: 10, y: 50), CGPoint(x: 92, y: 54)], to: lines, reach: 16, preferringEnds: true, straight: true)
        #expect(joined.line.count == 2 && joined.line.first == CGPoint(x: 10, y: 50))
        #expect(Self.near(joined.line.last, CGPoint(x: 100, y: 54)) && joined.joins.count == 1)
    }

    /// A short stroke across a break in a line joins the break's two ends exactly, though points
    /// along the line lie nearer its ends.
    @Test func aStrokeAcrossABreakJoinsItsEnds() {
        let lines = SnapLines([[CGPoint(x: 0, y: 0), CGPoint(x: 40, y: 0)], [CGPoint(x: 50, y: 0), CGPoint(x: 90, y: 0)]])
        #expect(lines.ends.count == 4)
        let joined = PenAssist.joined(
            [CGPoint(x: 38, y: 3), CGPoint(x: 52, y: -2)], to: lines, reach: 16, preferringEnds: true, straight: true)
        #expect(joined.line == [CGPoint(x: 40, y: 0), CGPoint(x: 50, y: 0)])
        // Lines that meet end to end have no end there.
        let met = SnapLines([[CGPoint(x: 0, y: 0), CGPoint(x: 40, y: 0)], [CGPoint(x: 40, y: 0), CGPoint(x: 40, y: 30)]])
        #expect(met.ends == [CGPoint(x: 0, y: 0), CGPoint(x: 40, y: 30)])
    }

    /// A curve's end moved onto a line it overshot eases in over the reach: the end lands on the
    /// line, the line before the reach keeps every point, and nothing folds back.
    @Test func aCurvesEndEasesOntoTheLine() throws {
        let lines = SnapLines([[CGPoint(x: 110, y: -50), CGPoint(x: 110, y: 50)]])
        let curve = (0...12).map { CGPoint(x: CGFloat($0) * 10, y: CGFloat($0 * $0) / 10) }
        let joined = PenAssist.joined(curve, to: lines, reach: 16, preferringEnds: true, straight: false)
        let end = try #require(joined.line.last)
        #expect(Self.near(end, CGPoint(x: 110, y: 14.4)), "\(end)")
        #expect(joined.joins.count == 1)
        for p in curve where p.x <= 100 { #expect(joined.line.contains(p), "\(p) moved") }
        #expect(zip(joined.line, joined.line.dropFirst()).allSatisfy { $0.x <= $1.x }, "\(joined.line)")
    }

    /// The Pen moves an end only onto a line its ink touches: within the reach it's given, onto
    /// the nearest point, never a line's end farther along.
    @Test func thePenMovesOnlyATouchingEnd() {
        let lines = SnapLines([[CGPoint(x: 100, y: 0), CGPoint(x: 100, y: 200)]])
        let touching = PenAssist.joined(
            [CGPoint(x: 10, y: 50), CGPoint(x: 98.5, y: 50)], to: lines, reach: 2, preferringEnds: false, straight: false)
        #expect(Self.near(touching.line.last, CGPoint(x: 100, y: 50)) && touching.line.first == CGPoint(x: 10, y: 50))
        let apart = PenAssist.joined(
            [CGPoint(x: 10, y: 50), CGPoint(x: 97, y: 50)], to: lines, reach: 2, preferringEnds: false, straight: false)
        #expect(apart.line == [CGPoint(x: 10, y: 50), CGPoint(x: 97, y: 50)] && apart.joins.isEmpty)
        let nearEnd = PenAssist.joined(
            [CGPoint(x: 10, y: 4), CGPoint(x: 99, y: 4)], to: lines, reach: 2, preferringEnds: false, straight: false)
        #expect(Self.near(nearEnd.line.last, CGPoint(x: 100, y: 4)))
    }

    /// A loop drawn round whose end comes back near its start closes on it; a short stroke
    /// doesn't close on itself.
    @Test func aLoopClosesOnItsStart() {
        let loop = (0...30).map { k -> CGPoint in
            let a = CGFloat(k) / 30 * 1.95 * .pi
            return CGPoint(x: 100 + 60 * cos(a), y: 100 + 60 * sin(a))
        }
        let closed = PenAssist.joined(loop, to: SnapLines([]), reach: 16, preferringEnds: true, straight: false)
        #expect(Self.near(closed.line.last, loop[0]) && closed.line.first == loop[0])
        let short = [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 5), CGPoint(x: 2, y: 3)]
        #expect(PenAssist.joined(short, to: SnapLines([]), reach: 16, preferringEnds: true, straight: false).joins.isEmpty)
    }

    /// What was erased since the template was made is no line to join: a dab takes a stretch out
    /// of a line, splitting it, and a line erased whole goes.
    @Test func erasedLinesAreNoTargets() {
        let line = [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0)]
        let dabbed = SnapLines(SnapLines.erasing([line], by: [([CGPoint(x: 50, y: 0)], 10)]))
        #expect(dabbed.lines.count == 2)
        #expect(dabbed.nearestPoint(to: CGPoint(x: 50, y: 4), within: 8) == nil)
        #expect(Self.near(dabbed.nearestPoint(to: CGPoint(x: 30, y: 4), within: 8), CGPoint(x: 30, y: 0)))
        #expect(dabbed.ends.contains { Self.near($0, CGPoint(x: 39, y: 0)) })
        let gone = SnapLines.erasing([line, [CGPoint(x: 0, y: 30), CGPoint(x: 100, y: 30)]], by: [(line, 1.5)])
        #expect(gone == [[CGPoint(x: 0, y: 30), CGPoint(x: 100, y: 30)]])
    }

    /// The Pencil's double tap switches between a kind's pen and eraser.
    @Test func thePencilSwitchesPenAndEraser() {
        #expect(RefineTool.pen.pencilPartner == .eraser && RefineTool.eraser.pencilPartner == .pen)
        #expect(RefineTool.smartPen.pencilPartner == .smartEraser && RefineTool.smartEraser.pencilPartner == .smartPen)
        #expect(RefineTool.more.pencilPartner == nil && RefineTool.text.pencilPartner == nil)
    }
}
