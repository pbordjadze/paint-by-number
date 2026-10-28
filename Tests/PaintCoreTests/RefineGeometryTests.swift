import Foundation
import Testing
@testable import PaintCore

/// Refine's geometry (`RefineGeometry.swift`): the pen's line smoothed and thinned, its ends on
/// the lines they touch, the shapes, and the line a tap of the eraser takes.
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

    /// A steadied line starts at the first sample, trails the finger by the string once it pulls
    /// it taut and ends where the finger lifted, even a finger that never pulled it; no string
    /// leaves the samples bit for bit.
    @Test func aSteadiedLineTrailsTheFingerByItsString() {
        let stroke = (0...40).map { CGPoint(x: CGFloat($0) * 5, y: 0) }
        let steady = PenPath.steadied(stroke, string: 20)
        #expect(steady.count == 38 && steady.first == stroke.first && steady.last == stroke.last)
        for (k, p) in steady.dropFirst().dropLast().enumerated() { #expect(abs(p.x - CGFloat(5 + 5 * k)) < 1e-9, "\(p)") }

        let tap = [CGPoint(x: 10, y: 10), CGPoint(x: 13, y: 11), CGPoint(x: 12, y: 14)]
        #expect(PenPath.steadied(tap, string: 20) == [tap[0], tap[2]])
        #expect(PenPath.steadied(Array(tap.prefix(1)), string: 20) == Array(tap.prefix(1)))
        let shaky = (0...40).map { CGPoint(x: CGFloat($0) * 5 + 0.1, y: $0 % 2 == 0 ? 0.3 : 1.7) }
        #expect(PenPath.steadied(shaky, string: 0) == shaky && PenPath.steadied(shaky, string: -2) == shaky)
    }

    /// A shaky hand's wobble, a zigzag of 1 to 4 points across a long straight stroke, hardly
    /// reaches a line steadied on a 20-point string: it strays from the stroke's line under a fifth
    /// as far as the samples did, and never a point.
    @Test func aSteadiedLineLeavesTheWobbleOut() {
        var rng = SplitMix64(seed: 143)
        let stroke = (0...200).map { k -> CGPoint in
            let wobble = 1 + 3 * CGFloat(rng.nextFloat())
            return CGPoint(x: CGFloat(k) * 2, y: k == 0 ? 100 : 100 + (k % 2 == 0 ? wobble : -wobble))
        }
        /// How far a line's points stray from y = 100 (root mean square) and at most, its ends left out.
        func strays(_ line: [CGPoint]) -> (typical: CGFloat, most: CGFloat) {
            let off = line.dropFirst().dropLast().map { abs($0.y - 100) }
            return ((off.reduce(0) { $0 + $1 * $1 } / CGFloat(off.count)).squareRoot(), off.max() ?? 0)
        }
        let before = strays(stroke), after = strays(PenPath.steadied(stroke, string: 20))
        #expect(after.typical < before.typical / 5 && after.most < 1, "\(after) from \(before)")
    }

    /// A long smooth curve keeps its shape: steadied on a 20-point string, an arc of radius 200
    /// cuts inside itself by about string² / 2r, a point, and every point of each lies that near
    /// the other.
    @Test func aSteadiedCurveKeepsItsShape() {
        let centre = CGPoint(x: 300, y: 300)
        let arc = (0...600).map { k -> CGPoint in
            let angle = CGFloat(k) / 600 * 1.5 * .pi
            return CGPoint(x: centre.x + 200 * cos(angle), y: centre.y + 200 * sin(angle))
        }
        let steady = PenPath.steadied(arc, string: 20)
        #expect(steady.allSatisfy { abs(PenPath.distance($0, centre) - 200) < 1.5 })
        #expect(arc.allSatisfy { p in zip(steady, steady.dropFirst()).contains { PenPath.segmentDistance(p, $0, $1) < 1.5 } })
    }

    /// A tap takes the line under it on through every joint where just one other line goes on,
    /// and stops where three lines meet or a line ends; a loop comes back to where it started;
    /// nothing is taken where no line is near.
    @Test func tappedLinesRunFromJunctionToJunction() throws {
        func line(_ points: [SIMD2<Float>]) -> [CGPoint] { points.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)) } }
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

    // MARK: - The pen's help and the shapes

    static func near(_ p: CGPoint?, _ q: CGPoint, within tolerance: CGFloat = 1e-6) -> Bool {
        p.map { PenPath.distance($0, q) <= tolerance } ?? false
    }

    /// A straight line whose ink touches a line goes straight on to it, still straight along
    /// its own way; its other end, near nothing, stays.
    @Test func aStraightLineEndsOnTheLineItTouches() {
        let lines = SnapLines([[CGPoint(x: 100, y: 0), CGPoint(x: 100, y: 200)]])
        let joined = PenAssist.joined([CGPoint(x: 10, y: 50), CGPoint(x: 98.5, y: 54)], to: lines, reach: 2, straight: true)
        #expect(joined.count == 2 && joined.first == CGPoint(x: 10, y: 50))
        #expect(Self.near(joined.last, CGPoint(x: 100, y: 50 + 4 * 90 / 88.5), within: 1e-9))
    }

    /// A curve that ran past a line ends where it crossed it: the tail is cut off, every point
    /// before the crossing stays, and nothing folds back.
    @Test func aCurveThatOvershotEndsAtTheCrossing() throws {
        let lines = SnapLines([[CGPoint(x: 110, y: -50), CGPoint(x: 110, y: 50)]])
        let curve = (0...12).map { CGPoint(x: CGFloat($0) * 10, y: CGFloat($0 * $0) / 10) }
        let joined = PenAssist.joined(curve, to: lines, reach: 16, straight: false)
        let end = try #require(joined.last)
        #expect(Self.near(end, CGPoint(x: 110, y: 12.1), within: 1e-9), "\(end)")
        #expect(Array(joined.dropLast()) == Array(curve.prefix(12)))
    }

    /// Paul's wedge (October 18): a stroke meeting another at a slant, its end just short of it.
    /// It goes straight on to the line, where the nearest point would have bent it back into a
    /// hook; an end beside a line it isn't heading at still moves to the nearest point, eased
    /// over several reaches so it bends gently.
    @Test func aSlantedEndMeetsTheLineWithoutAHook() throws {
        let lines = SnapLines([[CGPoint(x: 0, y: 0), CGPoint(x: 200, y: 0)]])
        // Rising at 20° toward the line, stopping 1 short of it (measured straight down).
        let slope = tan(20 * CGFloat.pi / 180)
        let stroke = (0...20).map { k -> CGPoint in
            let x = CGFloat(k) * 5
            return CGPoint(x: x, y: 1 + (100 - x) * slope)
        }
        let joined = PenAssist.joined(stroke, to: lines, reach: 4, straight: false)
        let end = try #require(joined.last)
        #expect(abs(end.y) < 1e-9 && abs(end.x - (100 + 1 / slope)) < 1e-6, "\(end)")
        #expect(zip(joined, joined.dropFirst()).allSatisfy { $0.x <= $1.x && $0.y >= $1.y }, "\(joined)")
        #expect(Array(joined.dropLast()) == stroke)

        // Running alongside, 2 below it: the end can't head at it, so it eases up onto it.
        let alongside = (0...20).map { CGPoint(x: CGFloat($0) * 5, y: 2) }
        let eased = PenAssist.joined(alongside, to: lines, reach: 4, straight: false)
        #expect(Self.near(eased.last, CGPoint(x: 100, y: 0)))
        for (p, q) in zip(eased, eased.dropFirst()) { #expect(abs(q.y - p.y) <= 2 / 16 * PenPath.distance(p, q) + 1e-9) }
    }

    /// The Pen moves an end only onto a line its ink touches: within the reach it's given, onto
    /// the nearest point.
    @Test func thePenMovesOnlyATouchingEnd() {
        let lines = SnapLines([[CGPoint(x: 100, y: 0), CGPoint(x: 100, y: 200)]])
        let touching = PenAssist.joined([CGPoint(x: 10, y: 50), CGPoint(x: 98.5, y: 50)], to: lines, reach: 2, straight: false)
        #expect(Self.near(touching.last, CGPoint(x: 100, y: 50)) && touching.first == CGPoint(x: 10, y: 50))
        let apart = PenAssist.joined([CGPoint(x: 10, y: 50), CGPoint(x: 97, y: 50)], to: lines, reach: 2, straight: false)
        #expect(apart == [CGPoint(x: 10, y: 50), CGPoint(x: 97, y: 50)])
        let nearEnd = PenAssist.joined([CGPoint(x: 10, y: 4), CGPoint(x: 99, y: 4)], to: lines, reach: 2, straight: false)
        #expect(Self.near(nearEnd.last, CGPoint(x: 100, y: 4)))
    }

    /// A loop drawn round whose end comes back near its start closes on it; a short stroke
    /// doesn't close on itself.
    @Test func aLoopClosesOnItsStart() {
        let loop = (0...30).map { k -> CGPoint in
            let a = CGFloat(k) / 30 * 1.98 * .pi
            return CGPoint(x: 100 + 60 * cos(a), y: 100 + 60 * sin(a))
        }
        let closed = PenAssist.joined(loop, to: SnapLines([]), reach: 4, straight: false)
        #expect(Self.near(closed.last, loop[0], within: 1e-9) && closed.first == loop[0])
        let short = [CGPoint(x: 0, y: 0), CGPoint(x: 5, y: 2), CGPoint(x: 1, y: 1)]
        #expect(PenAssist.joined(short, to: SnapLines([]), reach: 4, straight: false) == short)
    }

    /// What was erased since the template was made is no line to meet: a dab takes a stretch out
    /// of a line, splitting it, and a line erased whole goes.
    @Test func erasedLinesAreNoTargets() {
        let line = [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0)]
        let dabbed = SnapLines(SnapLines.erasing([line], by: [([CGPoint(x: 50, y: 0)], 10)]))
        #expect(dabbed.lines.count == 2)
        #expect(dabbed.nearestPoint(to: CGPoint(x: 50, y: 4), within: 8) == nil)
        #expect(Self.near(dabbed.nearestPoint(to: CGPoint(x: 30, y: 4), within: 8), CGPoint(x: 30, y: 0)))
        let gone = SnapLines.erasing([line, [CGPoint(x: 0, y: 30), CGPoint(x: 100, y: 30)]], by: [(line, 1.5)])
        #expect(gone == [[CGPoint(x: 0, y: 30), CGPoint(x: 100, y: 30)]])
    }

    /// A rectangle runs through both corners of the drag and closes; an oval fills the box the
    /// drag spans, touching each side's middle, and closes, its points about the spacing apart;
    /// a curve runs from end to end through its bend.
    @Test func shapesSpanTheDrag() throws {
        let a = CGPoint(x: 10, y: 20), b = CGPoint(x: 110, y: 70)
        let rectangle = ShapePath.rectangle(from: a, to: b)
        #expect(rectangle == [a, CGPoint(x: 110, y: 20), b, CGPoint(x: 10, y: 70), a])

        let oval = ShapePath.oval(from: a, to: b, spacing: 2)
        #expect(oval.first == oval.last)
        for p in oval { #expect(abs(pow((p.x - 60) / 50, 2) + pow((p.y - 45) / 25, 2) - 1) < 1e-9) }
        for side in [CGPoint(x: 10, y: 45), CGPoint(x: 110, y: 45), CGPoint(x: 60, y: 20), CGPoint(x: 60, y: 70)] {
            #expect(oval.contains { PenPath.distance($0, side) < 1.5 }, "The oval misses \(side)")
        }
        let steps = zip(oval, oval.dropFirst()).map { PenPath.distance($0, $1) }
        #expect(steps.allSatisfy { $0 <= 2 }, "\(steps.max() ?? 0)")
        #expect(ShapePath.oval(from: a, to: CGPoint(x: 11, y: 21), spacing: 2).count == 17)

        let bend = CGPoint(x: 60, y: 0)
        let curve = ShapePath.curve(from: a, to: b, through: bend, spacing: 2)
        #expect(curve.first == a && curve.last == b)
        #expect(curve.contains { PenPath.distance($0, bend) <= 1 })
        #expect(zip(curve, curve.dropFirst()).allSatisfy { PenPath.distance($0, $1) <= 2 })
    }


    /// A polygon is a regular hexagon stretched to the box the drag spans, flat sides on top and
    /// bottom, its corners on the box's sides; a star five points, the top one up, its inner
    /// corners 0.4 of the way out, spanning the box. Both close.
    @Test func polygonsAndStarsSpanTheDrag() {
        let a = CGPoint(x: 10, y: 20), b = CGPoint(x: 110, y: 70)
        let hexagon = ShapePath.polygon(from: a, to: b)
        #expect(hexagon.count == 7 && hexagon.first == hexagon.last)
        let xs = hexagon.map(\.x), ys = hexagon.map(\.y)
        #expect(abs(xs.min()! - 10) < 1e-9 && abs(xs.max()! - 110) < 1e-9 && abs(ys.min()! - 20) < 1e-9 && abs(ys.max()! - 70) < 1e-9)
        #expect(hexagon.contains { PenPath.distance($0, CGPoint(x: 10, y: 45)) < 1e-9 })
        #expect(hexagon.contains { PenPath.distance($0, CGPoint(x: 110, y: 45)) < 1e-9 })
        #expect(hexagon.filter { abs($0.y - 20) < 1e-9 }.count == 2, "a flat top")

        let star = ShapePath.star(from: a, to: b)
        #expect(star.count == 11 && star.first == star.last)
        let sx = star.map(\.x), sy = star.map(\.y)
        #expect(abs(sx.min()! - 10) < 1e-9 && abs(sx.max()! - 110) < 1e-9 && abs(sy.min()! - 20) < 1e-9 && abs(sy.max()! - 70) < 1e-9)
        #expect(abs(star[0].x - 60) < 1e-9 && abs(star[0].y - 20) < 1e-9, "the top point first")
        // In a box shaped like the star itself, its points are 1 from its centre and its inner corners 0.4.
        let unit = ShapePath.star(from: CGPoint(x: -sin(0.4 * .pi), y: -1), to: CGPoint(x: sin(0.4 * .pi), y: cos(0.2 * .pi)))
        for (k, p) in unit.dropLast().enumerated() {
            #expect(abs(hypot(p.x, p.y) - (k % 2 == 0 ? 1 : 0.4)) < 1e-9, "\(k): \(p)")
        }
        #expect(RefineShape.allCases.suffix(2) == [.polygon, .star] && RefineShape.polygon.isClosed && RefineShape.star.isClosed)
    }
}
