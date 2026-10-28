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

    /// An end whose ink only seems to touch a line, 2.5 points short of it at an ink of 1.5,
    /// ends on it (`touchFloor`); one 4 points short stays where it was drawn.
    @Test func thePenJoinsALineItsInkSeemsToTouch() throws {
        let frame = RefineGestures.snapLines(
            drawing: [], canvas: Self.screen.canvas, pending: [(.draw(points: [SIMD2(10, 100), SIMD2(180, 100)]), nil)])
        func end(short points: Float) throws -> SIMD2<Float>? {
            let samples = (0...20).map { Self.p(50, 60 + Float($0) * (40 - points / 5) / 20) }
            let edit = try #require(RefineGestures.pen(RefineGestures.trace(samples, on: Self.screen), on: Self.screen, snapping: frame))
            guard case .draw(let line, false, nil) = edit else { return nil }
            return line.last
        }
        #expect(try end(short: 2.5).map { abs($0.y - 100) < 1e-3 } == true)
        #expect(try end(short: 4).map { abs($0.y - 99.2) < 0.1 } == true)
    }

    /// The Pen's smoothing at 0 leaves its line as it was. At 1 a wobble of 1 to 4 points across a
    /// long stroke hardly reaches the line (`steadyString`): it strays under a point from the
    /// stroke's line where at 0 it strays over two, on a tenth of the points, from the same start
    /// to the same end. The line shown while the finger moves (`steadied`) is steadied alike.
    @Test func thePensSmoothingSteadiesItsLine() throws {
        let joining = RefineGestures.trace((0...20).map { Self.p(20 + Float($0) * 0.1, 50 + Float($0) * 1.09) }, on: Self.screen)
        #expect(RefineGestures.pen(joining, on: Self.screen, snapping: Self.lines, smoothing: 0)
            == RefineGestures.pen(joining, on: Self.screen, snapping: Self.lines))

        var rng = SplitMix64(seed: 143)
        let samples = RefineGestures.trace((0...375).map { k -> SIMD2<Float> in
            let wobble = 0.2 + 0.6 * rng.nextFloat()  // canvas units, 5 points each
            return Self.p(20 + 0.4 * Float(k), k == 0 ? 30 : 30 + (k % 2 == 0 ? wobble : -wobble))
        }, on: Self.screen)
        #expect(RefineGestures.pen(samples, on: Self.screen, snapping: nil, smoothing: 0)
            == RefineGestures.pen(samples, on: Self.screen, snapping: nil))
        func line(_ smoothing: CGFloat) throws -> [SIMD2<Float>] {
            let edit = try #require(RefineGestures.pen(samples, on: Self.screen, snapping: nil, smoothing: smoothing))
            guard case .draw(let points, false, nil) = edit else { Issue.record("\(edit)"); return [] }
            return points
        }
        /// How far a line strays from y = 30 between its ends (the last string's catch-up left out).
        func strays(_ points: [SIMD2<Float>]) -> Float { points.filter { $0.x > 25 && $0.x < 160 }.map { abs($0.y - 30) }.max() ?? 0 }
        let shaky = try line(0), steady = try line(1)
        #expect(strays(steady) < 0.2 && strays(shaky) > 0.4, "\(strays(steady)) and \(strays(shaky)) units")
        #expect(steady.count * 10 < shaky.count)
        let start = SIMD2<Float>(20, 30), end = SIMD2(samples[samples.count - 1].x * 192, samples[samples.count - 1].y * 144)
        #expect(simdLength(steady[0] - start) < 1e-3 && simdLength(steady[steady.count - 1] - end) < 1e-3)
        #expect(try line(3) == steady, "smoothing tops out at 1")

        #expect(RefineGestures.steadied(samples, smoothing: 0, on: Self.screen) == samples)
        let live = RefineGestures.steadied(samples, smoothing: 1, on: Self.screen)
        #expect(live.first == samples.first && live.last == samples.last && live.count < samples.count)
        #expect(live.dropFirst().dropLast().allSatisfy { abs($0.y * 144 - 30) < 0.2 })
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

    /// A polygon and a star are drawn as closed lines across the drag's box; too small, none.
    @Test func polygonsAndStarsAreClosedLines() throws {
        for shape in [RefineShape.polygon, .star] {
            let edit = try #require(RefineGestures.shape(shape, from: Self.p(90, 12), to: Self.p(112, 28), on: Self.screen, snapping: nil))
            guard case .draw(let ring, true, nil) = edit else { Issue.record("\(edit)"); return }
            #expect(ring.count == (shape == .polygon ? 6 : 10) && ring.first != ring.last)
            #expect(abs(ring.map(\.x).min()! - 90) < 1e-3 && abs(ring.map(\.y).max()! - 28) < 1e-3)
            let laid = try TemplateEditor.apply(edit, to: Self.scene)
            #expect(laid.outcome.declined == nil && laid.outcome.regionsSplit == 1)
            #expect(RefineGestures.shape(shape, from: Self.p(90, 12), to: Self.p(95, 30), on: Self.screen, snapping: nil) == nil)
        }
    }

    /// The eraser reaches a thirtieth of the view's short side, between 10 and 20 points.
    @Test func theEraserReachesItsSizeOnScreen() throws {
        #expect(abs(Self.screen.eraserRadius - 20 / 960) < 1e-6)
        let edit = try #require(RefineGestures.eraser([Self.p(50, 72)], on: Self.screen))
        guard case .erase(let path, let radius) = edit else { Issue.record("\(edit)"); return }
        #expect(path == [SIMD2(50, 72)] && abs(radius - 4) < 1e-4, "20 points at 5 to a unit")
    }

    /// An eraser given its Size reaches that many points on screen: size / the picture's long
    /// side × the canvas's, half as far on the canvas zoomed in twice. Without one it reaches as
    /// it always has.
    @Test func theEraserReachesTheSizeItIsGiven() throws {
        let dab = [Self.p(50, 72)]
        #expect(RefineGestures.eraser(dab, on: Self.screen, size: nil) == RefineGestures.eraser(dab, on: Self.screen))
        #expect(abs(Self.screen.eraserRadius(size: 30) - 30 / 960) < 1e-7)
        let edit = try #require(RefineGestures.eraser(dab, on: Self.screen, size: 30))
        guard case .erase(let path, let radius) = edit else { Issue.record("\(edit)"); return }
        #expect(path == [SIMD2(50, 72)] && abs(radius - 30 / 960 * 192) < 1e-4, "30 points at 5 to a unit")
        var zoomed = Self.screen
        zoomed.picture = CGSize(width: 1920, height: 1440)
        guard case .erase(_, let finer)? = RefineGestures.eraser(dab, on: zoomed, size: 30) else { Issue.record("no erase"); return }
        #expect(abs(finer - 3) < 1e-4, "30 points at 10 to a unit")
    }

    /// A tap of the Line Eraser beside a line takes it out from junction to junction, within a
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
        guard case .reshape(let from, let to, let reach, let target) = edit else { Issue.record("\(edit)"); return }
        #expect(abs(from.y - 74) < 1e-3 && abs(to.y - 62) < 1e-3 && abs(reach - 3.2) < 1e-4 && target == .any)
        let laid = try TemplateEditor.apply(edit, to: Self.scene)
        #expect(laid.outcome.reshaped == 1 && laid.outcome.declined == nil)
        #expect(RefineGestures.reshape(from: Self.p(104, 74), to: Self.p(104.1, 74), on: Self.screen) == nil)
    }

    /// Bend Line's drag grabs ink alone and Move Edge's boundaries alone: the target goes into the
    /// edit as given, and the ground's detail stroke under the drag is nothing to Move Edge.
    @Test func aReshapeDragCarriesItsTarget() throws {
        for target in [TemplateEditor.ReshapeTarget.ink, .edge] {
            let edit = try #require(RefineGestures.reshape(from: Self.p(104, 74), to: Self.p(104, 62), on: Self.screen, target: target))
            guard case .reshape(_, _, let reach, let sent) = edit else { Issue.record("\(edit)"); return }
            #expect(sent == target && abs(reach - 3.2) < 1e-4)
            #expect(try TemplateEditor.apply(edit, to: Self.scene).outcome.reshaped == 1, "the horizon is inked and a boundary")
        }
        let onStroke = try #require(RefineGestures.reshape(from: Self.p(96, 120.3), to: Self.p(96, 126), on: Self.screen, target: .edge))
        #expect(try TemplateEditor.apply(onStroke, to: Self.scene).outcome.declined != nil)
        let inked = try #require(RefineGestures.reshape(from: Self.p(96, 120.3), to: Self.p(96, 126), on: Self.screen, target: .ink))
        #expect(try TemplateEditor.apply(inked, to: Self.scene).outcome.reshaped == 1)
    }

    /// A drag of Move Number moves the number under its start to where it ended, in canvas units,
    /// grabbing it within a finger's reach on screen.
    @Test func aMoveNumberDragMovesTheNumber() throws {
        let sky = try #require(Self.scene.region(at: SIMD2(104, 30)))
        let label = try #require(Self.scene.labels(ofRegion: sky).first)
        let start = SIMD2(label.position.x / 192, label.position.y / 144)
        let edit = try #require(RefineGestures.moveLabel(from: start, to: Self.p(30, 30), on: Self.screen))
        guard case .moveLabel(let from, let to, let reach) = edit else { Issue.record("\(edit)"); return }
        #expect(simdLength(from - label.position) < 1e-3 && simdLength(to - SIMD2(30, 30)) < 1e-3)
        #expect(abs(reach - 3.2) < 1e-4, "a finger's reach, 16 points at 5 to a unit")
        let laid = try TemplateEditor.apply(edit, to: Self.scene)
        #expect(laid.outcome.labelsMoved == 1 && laid.outcome.declined == nil)
        #expect(RefineGestures.moveLabel(from: start, to: start + SIMD2(0.0001, 0), on: Self.screen) == nil)
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

    /// A drawn line's ends may join the drawing's lines but never its writing, which the editor
    /// never joins a line to (an end snapped onto a letter would hang there and close nothing);
    /// the drawing itself still has the letters.
    @Test func aLinesEndsMayJoinTheDrawingButNotItsWriting() throws {
        let t = try WritingTests.book().template
        let art = try #require(t.lineArt)
        let letters = art.writingStrokes.map { k in
            let s = art.strokes[Int(k)]
            return art.strokePoints[Int(s.pointStart)..<Int(s.pointStart + s.pointCount)].map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)) }
        }
        try #require(!letters.isEmpty)
        let all = RefineGestures.drawingLines(of: t), joinable = RefineGestures.drawingLines(of: t, writing: false)
        #expect(letters.allSatisfy { all.contains($0) })
        #expect(!letters.contains { joinable.contains($0) })
        #expect(joinable.count + letters.count == all.count)
    }

}
