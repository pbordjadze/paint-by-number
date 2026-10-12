import CoreGraphics
import Foundation
import PaintCore
import Testing
@testable import PaintByNumber

/// Refine's geometry: the pen's line smoothed and thinned, its ends on the lines they touch, the
/// shapes, the line a tap of the eraser takes, and what a tap of Fill does.
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

    // MARK: - The pen's help and the shapes

    static func near(_ p: CGPoint?, _ q: CGPoint, within tolerance: CGFloat = 1e-6) -> Bool {
        p.map { PenPath.distance($0, q) <= tolerance } ?? false
    }

    /// A straight line whose ink touches a line ends on it, still straight; its other end, near
    /// nothing, stays.
    @Test func aStraightLineEndsOnTheLineItTouches() {
        let lines = SnapLines([[CGPoint(x: 100, y: 0), CGPoint(x: 100, y: 200)]])
        let joined = PenAssist.joined([CGPoint(x: 10, y: 50), CGPoint(x: 98.5, y: 54)], to: lines, reach: 2, straight: true)
        #expect(joined.count == 2 && joined.first == CGPoint(x: 10, y: 50))
        #expect(Self.near(joined.last, CGPoint(x: 100, y: 54)))
    }

    /// A curve's end moved onto a line it overshot eases in over the reach: the end lands on the
    /// line, the line before the reach keeps every point, and nothing folds back.
    @Test func aCurvesEndEasesOntoTheLine() throws {
        let lines = SnapLines([[CGPoint(x: 110, y: -50), CGPoint(x: 110, y: 50)]])
        let curve = (0...12).map { CGPoint(x: CGFloat($0) * 10, y: CGFloat($0 * $0) / 10) }
        let joined = PenAssist.joined(curve, to: lines, reach: 16, straight: false)
        let end = try #require(joined.last)
        #expect(Self.near(end, CGPoint(x: 110, y: 14.4)), "\(end)")
        for p in curve where p.x <= 100 { #expect(joined.contains(p), "\(p) moved") }
        #expect(zip(joined, joined.dropFirst()).allSatisfy { $0.x <= $1.x }, "\(joined)")
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

    /// The Pencil's double tap switches between drawing (the Pen or Shapes) and the Eraser; Fill
    /// has no partner.
    @Test func thePencilSwitchesPenAndEraser() {
        #expect(RefineTool.pen.pencilPartner == .eraser && RefineTool.eraser.pencilPartner == .pen)
        #expect(RefineTool.shape.pencilPartner == .eraser && RefineTool.smartEraser.pencilPartner == .pen)
        #expect(RefineTool.more.pencilPartner == nil && RefineTool.text.pencilPartner == nil)
        #expect(RefineTool.fill.pencilPartner == nil && !RefineTool.fill.erases)
    }

    /// A tap anywhere in the detail area a fill made takes out the fills made there (not those
    /// elsewhere); a tap in another area, or in a detail area no fill made, is a new fill. On three
    /// stripes 20 units wide, the middle one a detail area.
    @Test func aTapInAFilledAreaClearsItsFills() {
        var t = Fixtures.stripes(count: 3, stripeWidth: 20, height: 40)
        t.detailRegions = [1]
        let color = SIMD3<Float>(0.6, 0.05, 0.05)
        let inMiddle = TemplateEditor.Edit.fill(at: SIMD2(30, 20), color: color)
        let again = TemplateEditor.Edit.fill(at: SIMD2(27, 8), color: color)
        let onLeft = TemplateEditor.Edit.fill(at: SIMD2(6, 20), color: color)
        let drawn = TemplateEditor.Edit.draw(points: [SIMD2(1, 1), SIMD2(5, 5)])
        let edits = [inMiddle, onLeft, drawn, again]
        #expect(EditFills.cleared(by: SIMD2(36, 36), edits: edits, on: t) == [0, 3])
        #expect(EditFills.cleared(by: SIMD2(10, 20), edits: edits, on: t).isEmpty)
        #expect(EditFills.cleared(by: SIMD2(36, 36), edits: [onLeft, drawn], on: t).isEmpty)
        #expect(EditFills.cleared(by: SIMD2(-5, 99), edits: edits, on: t).isEmpty)
    }
}
