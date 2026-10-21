import Foundation
import Testing
@testable import PaintCore

/// What Refine makes of a gesture (`RefineGestures`), as the app's screen and `pbn refine` both
/// make it: on the editor's scene (`TemplateEditorTests`, 192 × 144 canvas units) shown 960 points
/// wide, 5 points to a unit.
struct RefineGesturesTests {
    static let scene = TemplateEditorTests.scene
    static let screen = RefineScreen(
        canvas: CGSize(width: 192, height: 144), picture: CGSize(width: 960, height: 720), view: CGSize(width: 1000, height: 800),
        lineWidth: 1.5)
    static var lines: SnapLines {
        RefineGestures.snapLines(drawing: RefineGestures.drawingLines(of: scene), canvas: screen.canvas, pending: [])
    }

    /// Picture points of canvas units.
    static func p(_ x: Float, _ y: Float) -> SIMD2<Float> { SIMD2(x / 192, y / 144) }

    @Test func theDrawingIsItsDrawnEdgesAndStrokes() {
        let t = Self.scene, art = t.lineArt!
        let drawn = t.edges.indices.filter { t.edges[$0].right != BoundaryEdge.outside && art.edgeLayers[$0] < LineLayer.color.rawValue }
        let strokes = art.strokes.filter { $0.layer < LineLayer.color.rawValue }
        #expect(RefineGestures.drawingLines(of: t).count == drawn.count + strokes.count)
    }

    /// Every layer before `color` is drawn; `color` and any layer past it (a newer app's) are not.
    @Test func theDrawnLayersAreThoseBeforeColor() {
        #expect([LineLayer.outline, .detail, .texture].allSatisfy { LineLayer.isDrawn($0.rawValue) })
        #expect(!LineLayer.isDrawn(LineLayer.color.rawValue) && !LineLayer.isDrawn(4) && !LineLayer.isDrawn(255))
    }

    /// Samples closer than a point on screen to the last kept add nothing; the last is kept.
    @Test func aTraceKeepsSamplesAPointApart() {
        let samples = (0...10).map { SIMD2(Float($0) * 0.0005, 0.5) }  // 0.48 points apart
        let kept = RefineGestures.trace(samples, on: Self.screen)
        #expect(kept == [0, 3, 6, 9, 10].map { samples[$0] }, "every third is a point on, and the last")
    }

    /// A pen line whose end comes within its ink of a line ends on it; one shorter than a
    /// fingertip's slip is no line.
    @Test func thePenEndsOnTheLineItTouches() throws {
        // The horizon runs at y ≈ 72 left of the disc; a line from the sky down to 0.2 above it.
        let samples = (0...20).map { Self.p(20 + Float($0) * 0.1, 50 + Float($0) * 1.09) }
        let edit = try #require(RefineGestures.pen(RefineGestures.trace(samples, on: Self.screen), on: Self.screen, snapping: Self.lines))
        guard case .draw(let points, false, nil) = edit else { Issue.record("\(edit)"); return }
        let end = try #require(points.last)
        #expect(abs(end.y - 72) < 1 && abs(points[0].y - 50) < 1e-3, "\(points)")
        #expect(RefineGestures.pen([Self.p(20, 50), Self.p(21, 51)], on: Self.screen, snapping: Self.lines) == nil)
        let laid = try TemplateEditor.apply(edit, to: Self.scene)
        #expect(laid.outcome.joins >= 1 && laid.outcome.declined == nil)
    }

    /// The Color Splitter's stroke is the Pen's line, as a split.
    @Test func theSplitterIsThePensLineAsASplit() throws {
        let samples = RefineGestures.trace((0...20).map { Self.p(20 + Float($0) * 0.1, 50 + Float($0) * 1.09) }, on: Self.screen)
        let pen = try #require(RefineGestures.pen(samples, on: Self.screen, snapping: Self.lines))
        let split = try #require(RefineGestures.splitter(samples, on: Self.screen, snapping: Self.lines))
        guard case .draw(let line, false, nil) = pen else { Issue.record("\(pen)"); return }
        #expect(split == .split(points: line))
        #expect(RefineGestures.splitter([Self.p(20, 50), Self.p(21, 51)], on: Self.screen, snapping: Self.lines) == nil)
    }

    /// The Cell Edge's stroke is the Pen's line, as a cell edge.
    @Test func theCellEdgeIsThePensLineAsACellEdge() throws {
        let samples = RefineGestures.trace((0...20).map { Self.p(20 + Float($0) * 0.1, 50 + Float($0) * 1.09) }, on: Self.screen)
        let pen = try #require(RefineGestures.pen(samples, on: Self.screen, snapping: Self.lines))
        let edge = try #require(RefineGestures.cellEdge(samples, on: Self.screen, snapping: Self.lines))
        guard case .draw(let line, false, nil) = pen else { Issue.record("\(pen)"); return }
        #expect(edge == .cellEdge(points: line))
        #expect(RefineGestures.cellEdge([Self.p(20, 50), Self.p(21, 51)], on: Self.screen, snapping: Self.lines) == nil)
    }

    /// Shapes: a rectangle is a closed line through its corners, an oval closed too, a curve takes
    /// its ends from one drag and its bend from the next; one too small to draw is none.
    @Test func shapesMakeTheirLines() throws {
        let rect = try #require(RefineGestures.shape(.rectangle, from: Self.p(90, 12), to: Self.p(112, 28), on: Self.screen, snapping: Self.lines))
        guard case .draw(let corners, true, nil) = rect else { Issue.record("\(rect)"); return }
        #expect(corners.count == 4 && abs(corners[2].x - 112) < 1e-3 && abs(corners[2].y - 28) < 1e-3)
        let oval = try #require(RefineGestures.shape(.oval, from: Self.p(90, 12), to: Self.p(112, 28), on: Self.screen, snapping: nil))
        guard case .draw(let ring, true, nil) = oval else { Issue.record("\(oval)"); return }
        #expect(ring.count >= 16 && ring.first != ring.last)
        #expect(RefineGestures.shape(.rectangle, from: Self.p(90, 12), to: Self.p(95, 30), on: Self.screen, snapping: nil) == nil)

        let ends = try #require(RefineGestures.curveEnds(from: Self.p(80, 20), to: Self.p(120, 20), on: Self.screen, snapping: Self.lines))
        let bent = try #require(RefineGestures.shape(.curve, from: Self.p(100, 10), to: Self.p(100, 10), curve: ends, on: Self.screen, snapping: nil))
        guard case .draw(let curve, false, nil) = bent else { Issue.record("\(bent)"); return }
        #expect(curve.contains { simdLength($0 - SIMD2(100, 10)) < 0.5 })
        #expect(RefineGestures.straightCurve(from: ends.from, to: ends.to, on: Self.screen) == .draw(points: [SIMD2(80, 20), SIMD2(120, 20)]))
    }

    /// The eraser reaches a thirtieth of the view's short side, between 10 and 20 points.
    @Test func theEraserReachesItsSizeOnScreen() throws {
        #expect(abs(Self.screen.eraserRadius - 20 / 960) < 1e-6)
        let edit = try #require(RefineGestures.eraser([Self.p(50, 72)], on: Self.screen))
        guard case .erase(let path, let radius) = edit else { Issue.record("\(edit)"); return }
        #expect(path == [SIMD2(50, 72)] && abs(radius - 4) < 1e-4, "20 points at 5 to a unit")
    }

    /// A tap of the Smart Eraser beside a line takes it out from junction to junction, within a
    /// finger's reach (16 points, 3.2 units); farther off it takes nothing.
    @Test func theSmartEraserTakesTheLineUnderATap() throws {
        let chains = LineChains(lines: RefineGestures.drawingLines(of: Self.scene))
        let erased = try #require(RefineGestures.lineEraser(at: Self.p(60, 101), on: Self.screen, chains: chains))
        guard case .eraseLine(let at, let reach) = erased.edit else { Issue.record("\(erased.edit)"); return }
        #expect(at == SIMD2(60, 101) && abs(reach - 3.2) < 1e-4 && erased.chain.count >= 2)
        #expect(RefineGestures.lineEraser(at: Self.p(100, 30), on: Self.screen, chains: chains) == nil)
    }

    /// A drag of Bend Line or Move Edge moves the line within a finger's reach (16 points, 3.2
    /// units) of where it started to where it ended; a drag under a point on screen is none.
    @Test func aReshapeDragMovesTheLineUnderIt() throws {
        let edit = try #require(RefineGestures.reshape(from: Self.p(104, 74), to: Self.p(104, 62), on: Self.screen))
        guard case .reshape(let from, let to, let reach) = edit else { Issue.record("\(edit)"); return }
        #expect(abs(from.y - 74) < 1e-3 && abs(to.y - 62) < 1e-3 && abs(reach - 3.2) < 1e-4)
        let laid = try TemplateEditor.apply(edit, to: Self.scene)
        #expect(laid.outcome.reshaped == 1 && laid.outcome.declined == nil)
        #expect(RefineGestures.reshape(from: Self.p(104, 74), to: Self.p(104.1, 74), on: Self.screen) == nil)
    }

    /// The lines a pen may meet follow the edits sent: a line drawn is one, an erased stretch is
    /// none.
    @Test func snapLinesFollowThePendingEdits() {
        let drawn = TemplateEditor.Edit.draw(points: [SIMD2(100, 10), SIMD2(100, 40)])
        let withLine = RefineGestures.snapLines(drawing: [], canvas: Self.screen.canvas, pending: [(drawn, nil)])
        #expect(withLine.nearestPoint(to: CGPoint(x: 101, y: 20), within: 2) != nil)
        let erased = RefineGestures.snapLines(
            drawing: [], canvas: Self.screen.canvas, pending: [(drawn, nil), (.erase(path: [SIMD2(100, 20)], radius: 5), nil)])
        #expect(erased.nearestPoint(to: CGPoint(x: 101, y: 20), within: 2) == nil)
    }
}
