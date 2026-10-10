import Foundation
import Testing
@testable import PaintCore

/// The painter's edits to a coloring book's drawing (`LineArtInput.edits`, `LineEdits`), on
/// `LineArtTests`' scene: its canvas is 192 × 144 (1.5 × the photo), the horizon at y = 72, the
/// disc's centre (60, 72) with radius 27, the square over x 120..<168, y 45..<93, and the
/// ground's detail line at y = 120, drawn inside the ground's cell.
@Suite("Line edits")
struct LineEditsTests {
    static let canvas = SIMD2<Float>(192, 144)

    /// Canvas points normalized to the photo.
    static func path(_ points: [SIMD2<Float>]) -> [SIMD2<Float>] { points.map { $0 / canvas } }

    static func draw(_ points: [SIMD2<Float>]) -> LineEdit { LineEdit(kind: .draw, points: path(points)) }

    /// The eraser along `points`, `radius` canvas units either side.
    static func erase(_ points: [SIMD2<Float>], radius: Float) -> LineEdit {
        LineEdit(kind: .erase, points: path(points), radius: radius / canvas.x)
    }

    static func generate(_ edits: [LineEdit], edges: EdgeMap = LineArtTests.edges()) throws -> TemplateGenerator.Output {
        try LineArtTests.generate(LineArtTests.settings(), input: LineArtInput(edges: edges, edits: edits))
    }

    /// The distance from `p` (canvas units) to the nearest drawn line: an edge of a drawn layer
    /// or an interior stroke.
    static func inkDistance(_ t: Template, _ p: SIMD2<Float>) -> Float {
        let art = t.lineArt!
        var best = Float.infinity
        func visit(_ points: ArraySlice<SIMD2<Float>>) {
            for (a, b) in zip(points, points.dropFirst()) {
                let ab = b - a
                let s = min(max(simdDot(p - a, ab) / max(simdLengthSquared(ab), 1e-9), 0), 1)
                best = min(best, simdLength(p - (a + ab * s)))
            }
        }
        for (k, e) in t.edges.enumerated() where e.right != BoundaryEdge.outside && art.edgeLayers[k] != LineLayer.color.rawValue {
            visit(t.points(of: e))
        }
        for s in art.strokes { visit(art.strokePoints[Int(s.pointStart)..<Int(s.pointStart + s.pointCount)]) }
        return best
    }

    /// A line drawn down the sky from the top of the frame across the horizon walls off the
    /// sky's left: two cells of one paint, drawn as an outline. It runs on 10 px past the
    /// horizon, and is drawn there as it was drawn, inside the ground's cell, not trimmed back.
    @Test func aDrawnLineSplitsTheCellItCrosses() throws {
        let plain = try Self.generate([]).template
        let out = try Self.generate([Self.draw([SIMD2(15, -8), SIMD2(15, 82)])])
        let t = out.template
        expectValid(t)
        #expect(out.vectorStats.labelRoomUnmet == 0)
        #expect(out.lineArtStats?.drawnLines == 1)
        #expect(t.regions.count == plain.regions.count + 1)
        let left = try #require(t.region(at: SIMD2<Float>(5, 30))), right = try #require(t.region(at: SIMD2<Float>(25, 30)))
        #expect(left != right && t.regions[left].colorIndex == t.regions[right].colorIndex)
        #expect(Self.inkDistance(t, SIMD2(15.5, 30)) < 1.5)
        #expect(t.region(at: SIMD2<Float>(5, 78)) == t.region(at: SIMD2<Float>(25, 78)), "The tail split the ground")
        let tail = try #require(Self.stroke(in: t, near: SIMD2(15, 79)))
        #expect(abs((tail.map(\.y).max() ?? 0) - 82) < 1, "\(tail)")
    }

    /// An end drawn a little past a line is not trimmed back to it: a line down from the top of
    /// the frame walls off the sky on either side of it and runs on 9 px past the disc's
    /// outline, drawn there inside the disc's cell.
    @Test func anOvershootingEndIsNotTrimmed() throws {
        let plain = try Self.generate([]).template
        let out = try Self.generate([Self.draw([SIMD2(60, -8), SIMD2(60, 54)])])
        let t = out.template
        expectValid(t)
        #expect(out.vectorStats.labelRoomUnmet == 0)
        #expect(t.regions.count == plain.regions.count + 1)
        let tail = try #require(Self.stroke(in: t, near: SIMD2(60, 51)))
        #expect(abs((tail.map(\.y).max() ?? 0) - 54) < 1, "\(tail)")
        #expect(t.region(at: SIMD2<Float>(60, 50)) == t.region(at: SIMD2<Float>(60, 72)))
    }

    /// A line that closes nothing is drawn inside its cell, and the cells stay as they were.
    @Test func aLineThatClosesNothingIsDrawnInsideItsCell() throws {
        let plain = try Self.generate([]).template
        let t = try Self.generate([Self.draw([SIMD2(58, 17), SIMD2(86, 29)])]).template
        expectValid(t)
        #expect(t.regions.count == plain.regions.count)
        let art = try #require(t.lineArt)
        #expect(art.strokes.count == plain.lineArt!.strokes.count + 1)
        let sky = try #require(t.region(at: SIMD2<Float>(72, 23)))
        #expect(art.strokes.contains { $0.region == UInt32(sky) && $0.layer == LineLayer.outline.rawValue })
        #expect(Self.inkDistance(t, SIMD2(72, 23)) < 1.5)
    }

    /// A line drawn inside a cell through its number moves the number off it, within the cell,
    /// as the writing does: the line would cross it out.
    @Test func aDrawnLineMovesTheNumberOffIt() throws {
        let plain = try Self.generate([]).template
        let sky = try #require(plain.region(at: SIMD2<Float>(100, 20)))
        let pole = try #require(plain.labels.first { $0.region == UInt32(sky) }).position
        let a = pole - SIMD2(7, 0), b = pole + SIMD2(7, 0)
        let out = try Self.generate([Self.draw([a, b])])
        let t = out.template
        expectValid(t)
        #expect(out.vectorStats.labelRoomUnmet == 0)
        #expect(t.regions.count == plain.regions.count, "The line closed a cell")
        #expect(t.lineArt!.strokes.count == plain.lineArt!.strokes.count + 1)
        #expect(Self.inkDistance(t, pole) < 1.5)
        for label in t.labels where label.region == UInt32(sky) {
            #expect(t.region(at: label.position) == sky)
            let ab = b - a, s = min(max(simdDot(label.position - a, ab) / simdLengthSquared(ab), 0), 1)
            #expect(simdLength(label.position - (a + ab * s)) >= label.radius, "A number of the sky is on the line")
        }
    }

    /// A line drawn through one of a large area's extra numbers leaves none squeezed beside it:
    /// each keeps most of the room its spot has from the area's outline. On the scene's photo
    /// four times over (a 768 × 576 canvas), whose sky holds a few dozen numbers; the spot
    /// beside the line, spacious by its outline, kept one with a tenth of the others' room.
    @Test func extraNumbersKeepTheirRoomBesideADrawnLine() throws {
        let small = LineArtTests.photo(), k = 4
        let w = small.width * k, h = small.height * k
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        for i in 0..<(w * h) {
            let source = ((i / w / k) * small.width + i % w / k) * 4
            for c in 0..<4 { pixels[i * 4 + c] = small.pixels[source + c] }
        }
        let photo = RGBAImage(width: w, height: h, pixels: pixels)
        let canvas = SIMD2<Float>(768, 576), a = SIMD2<Float>(304.5, 64.5), b = SIMD2<Float>(304.5, 124.5)
        let out = try LineArtTests.generate(
            LineArtTests.settings(), photo: photo,
            input: LineArtInput(edges: LineArtTests.edges(), edits: [LineEdit(kind: .draw, points: [a / canvas, b / canvas])]))
        let t = out.template
        expectValid(t)
        #expect(t.width == 768 && t.height == 576)
        let sky = try #require(t.region(at: SIMD2<Float>(400, 60)))
        let labels = t.labels.filter { $0.region == UInt32(sky) }
        #expect(labels.count > 10)
        let outline = DistanceTransform.interiorDistance(labels: t.regionMap)
        for label in labels {
            let s = min(max(simdDot(label.position - a, b - a) / simdLengthSquared(b - a), 0), 1)
            let line = simdLength(label.position - (a + (b - a) * s)) - Float(LabelKeepOut.lineHalfWidth)
            let room = outline[Int(label.position.x), Int(label.position.y)]
            #expect(line >= 0.75 * room, "A number at \(label.position) is squeezed beside the line: \(label.radius) of \(room)")
        }
    }

    /// An end that stops a little short of a line stays where it was drawn, never led into the
    /// line: the line closes no cell and is drawn inside the sky's.
    @Test func anEndShortOfALineStaysWhereDrawn() throws {
        let plain = try Self.generate([]).template
        let out = try Self.generate([Self.draw([SIMD2(15, -8), SIMD2(15, 66)])])
        let t = out.template
        expectValid(t)
        #expect(out.vectorStats.labelRoomUnmet == 0)
        #expect(t.regions.count == plain.regions.count, "The line was led into the horizon")
        let line = try #require(Self.stroke(in: t, near: SIMD2(15, 40)))
        #expect(abs((line.map(\.y).max() ?? 0) - 66) < 1, "\(line)")
        #expect(Self.inkDistance(t, SIMD2(15, 69)) > 2)
    }

    /// Lines with both ends free stay inside their cells as drawn, and the template holds: one
    /// across the sky ending 5 px short of the disc and of the square (reaching both, it would
    /// close a cell above the horizon), and a short stub.
    @Test func freeEndedLinesStayInsideTheirCells() throws {
        let plain = try Self.generate([]).template
        let across = [SIMD2<Float>(89, 60), SIMD2(115, 60)], stub = [SIMD2<Float>(100, 20), SIMD2(108, 24)]
        let out = try Self.generate([Self.draw(across), Self.draw(stub)])
        let t = out.template
        expectValid(t)
        #expect(out.vectorStats.labelRoomUnmet == 0)
        #expect(out.lineArtStats?.drawnLines == 2)
        #expect(t.regions.count == plain.regions.count, "A line closed a cell")
        #expect(t.lineArt!.strokes.count == plain.lineArt!.strokes.count + 2)
        for (drawn, middle) in [(across, SIMD2<Float>(102, 60)), (stub, SIMD2<Float>(104, 22))] {
            let line = try #require(Self.stroke(in: t, near: middle))
            for end in drawn {
                #expect(line.contains { simdLength($0 - end) < 1 }, "\(end) is not an end of \(line)")
            }
            #expect(line.allSatisfy { $0.x >= drawn[0].x - 1 && $0.x <= drawn[1].x + 1 }, "\(line) runs past its ends")
        }
    }

    /// The eraser takes out the lines under it: the ground's detail line inside its cell, and
    /// a stretch of the disc's outline, whose two paints stay two cells with the boundary there
    /// no longer drawn while the rest of the outline is.
    @Test func theEraserTakesLinesOut() throws {
        let plain = try Self.generate([]).template
        #expect(Self.inkDistance(plain, SIMD2(96, 120.5)) < 2 && Self.inkDistance(plain, SIMD2(61, 46)) < 2)
        let out = try Self.generate([
            Self.erase([SIMD2(-10, 120), SIMD2(200, 120)], radius: 6),
            Self.erase([SIMD2(61, 46)], radius: 8),
        ])
        let t = out.template
        expectValid(t)
        #expect(out.lineArtStats?.erasures == 2)
        #expect(Self.inkDistance(t, SIMD2(96, 120.5)) > 4)
        #expect(Self.inkDistance(t, SIMD2(61, 46)) > 3)
        #expect(t.region(at: SIMD2<Float>(60, 55)) != t.region(at: SIMD2<Float>(60, 35)))
        #expect(Self.inkDistance(t, SIMD2(40, 55.5)) < 2, "The rest of the disc's outline went too")
        #expect(t.regions.count == plain.regions.count)
    }

    /// A line erased whole goes from end to end, and the lines it met keep their junction: a
    /// line tapped away where it ends on another leaves that one whole, so the cells it keeps
    /// apart stay apart (the eraser's round reach would open a gap there and join them).
    @Test func aLineErasedWholeLeavesItsJunctionsAlone() throws {
        let plain = try Self.generate([]).template
        let wall = Self.draw([SIMD2(15, -8), SIMD2(15, 77)]), branch = [SIMD2<Float>(-8, 36), SIMD2(15, 36)]
        let branched = try Self.generate([wall, Self.draw(branch)]).template
        #expect(branched.regions.count == plain.regions.count + 2)
        let t = try Self.generate([
            wall, Self.draw(branch), LineEdit(kind: .eraseLine, points: Self.path(branch), radius: 4.5 / Self.canvas.x),
        ]).template
        expectValid(t)
        #expect(Self.inkDistance(t, SIMD2(7, 36)) > 3)
        #expect(Self.inkDistance(t, SIMD2(15.5, 36)) < 1.5, "The line it met was cut")
        #expect(t.regions.count == plain.regions.count + 1)
    }

    /// A line drawn along part of a boundary between two paints, where nothing was drawn, is
    /// drawn just there: a third of the disc's upper rim, on a blank edge map.
    @Test func aLineAlongPartOfABoundaryIsDrawnJustThere() throws {
        let blank = EdgeMap(width: 128, height: 96, values: [UInt8](repeating: 0, count: 128 * 96))
        func rim(_ degrees: Float) -> SIMD2<Float> {
            let a = degrees * .pi / 180
            return SIMD2(60.75 + 27 * cos(a), 72.75 - 27 * sin(a))
        }
        let t = try Self.generate([Self.draw(stride(from: 60, through: 120, by: 10).map { rim(Float($0)) })], edges: blank).template
        expectValid(t)
        #expect(Self.inkDistance(t, rim(90)) < 1.5)
        #expect(Self.inkDistance(t, rim(165)) > 4, "The whole rim is drawn")
    }

    /// Edits take effect in the order they were made: a line erased after it was drawn goes,
    /// one drawn over an erased place stays.
    @Test func editsTakeEffectInOrder() throws {
        let plain = try Self.generate([]).template
        let line = [SIMD2<Float>(58, 17), SIMD2(86, 29)]
        let erased = try Self.generate([Self.draw(line), Self.erase(line, radius: 4)]).template
        #expect(erased.regions.count == plain.regions.count && Self.inkDistance(erased, SIMD2(72, 23)) > 4)
        let redrawn = try Self.generate([Self.erase(line, radius: 4), Self.draw(line)]).template
        #expect(Self.inkDistance(redrawn, SIMD2(72, 23)) < 1.5)
        expectValid(redrawn)
    }

    /// No edits, or edits with nothing in them, leave the template as it was; the same edits
    /// give the same bytes.
    @Test func editsAreDeterministic() throws {
        let plain = try Self.generate([]).template
        #expect(try Self.generate([LineEdit(kind: .draw, points: []), LineEdit(kind: .erase, points: [])]).template == plain)
        let edits = [
            Self.draw([SIMD2(15, -8), SIMD2(15, 77)]), Self.erase([SIMD2(60, 45)], radius: 6),
            Self.draw([SIMD2(58, 17), SIMD2(70, 30), SIMD2(86, 29)]),
        ]
        #expect(try Self.generate(edits).template.encoded() == Self.generate(edits).template.encoded())
    }

    /// What a hostile file could hold costs little and breaks nothing: points that aren't
    /// numbers or lie far off, radii out of range, more edits than are read, and more path than
    /// is drawn.
    @Test func hostileEditsAreHarmless() throws {
        let edits = [
            LineEdit(kind: .draw, points: [SIMD2(.nan, 0.5), SIMD2(1e30, -1e30), SIMD2(0.5, .infinity)]),
            LineEdit(kind: .erase, points: [SIMD2(0.5, 0.5)], radius: .nan),
        ] + (0..<2_500).map { k in
            LineEdit(kind: k % 2 == 0 ? .draw : .erase, points: [SIMD2(0.1, Float(k % 90) / 100), SIMD2(0.9, 0.5)], radius: 9)
        }
        let out = try Self.generate(edits)
        expectValid(out.template)
        let read = LineEdits.sanitized(edits)
        #expect(read.count < edits.count && read.allSatisfy { edit in edit.points.allSatisfy { all($0 .>= -0.5) && all($0 .<= 1.5) } })
        let length = read.reduce(Float(0)) { sum, edit in
            sum + zip(edit.points, edit.points.dropFirst()).reduce(0) { $0 + simdLength($1.1 - $1.0) }
        }
        #expect(length <= LineEdits.maximumLength)
        let dabs = (0..<2_500).map { _ in LineEdit(kind: .erase, points: [SIMD2(0.5, 0.5)], radius: 0.01) }
        #expect(LineEdits.sanitized(dabs).count == LineEdits.maximumEdits)
    }

    /// A free end reaches the line ahead of it, unless that place is blocked (erased after the
    /// line was drawn).
    @Test func noEndReachesIntoABlockedPlace() {
        let w = 40, h = 20
        func line(_ points: [SIMD2<Float>], free: (Bool, Bool)) -> DrawnLine {
            DrawnLine(
                points: points, strength: [Float](repeating: 1, count: points.count),
                layer: [UInt8](repeating: LineLayer.outline.rawValue, count: points.count), closed: false, free: free,
                links: [], eye: false)
        }
        let lines = [
            line((2...18).map { SIMD2(30, Float($0)) }, free: (false, false)),
            line((5...24).map { SIMD2(Float($0), 10) }, free: (false, true)),
        ]
        let walls = LineLayering.walls(lines, width: w, height: h)
        let colorEdge = [Bool](repeating: false, count: w * h)
        var reached = lines
        #expect(LineLayering.closeFreeEnds(&reached, walls: walls, colorEdge: colorEdge, reach: [10, 10, 10]) == 1)
        #expect(reached[1].points.last == SIMD2(30, 10))
        var held = lines
        let blocked: (Int, Int) -> Bool = { k, i in k == 1 && i % w >= 27 }
        #expect(LineLayering.closeFreeEnds(&held, walls: walls, colorEdge: colorEdge, reach: [10, 10, 10], blocked: blocked) == 0)
        #expect(held[1].points == lines[1].points)
    }

    /// A drawn line's ends stay where the painter drew them, and none is free: one crossing a
    /// line a little, one stopping short of it, the tails of a loop drawn past its start; one
    /// run off the canvas ends on the frame. The drawing's own free ends are still led into a
    /// drawn line.
    @Test func drawnEndsStayWhereDrawn() throws {
        let w = 60, h = 40
        func line(_ points: [SIMD2<Float>], free: (Bool, Bool)) -> DrawnLine {
            DrawnLine(
                points: points, strength: [Float](repeating: 1, count: points.count),
                layer: [UInt8](repeating: LineLayer.outline.rawValue, count: points.count), closed: false, free: free,
                links: [], eye: false)
        }
        let wall = line((2...37).map { SIMD2(30, Float($0)) }, free: (false, false))
        func applied(_ points: [SIMD2<Float>]) -> DrawnLine? {
            let normalized = points.map { ($0 + 0.5) / SIMD2(Float(w), Float(h)) }
            let result = LineEdits.apply([LineEdit(kind: .draw, points: normalized)], to: [wall], width: w, height: h)
            return result.lines.count == 2 ? result.lines[1] : nil
        }
        func near(_ p: SIMD2<Float>?, _ q: SIMD2<Float>) -> Bool { p.map { simdLength($0 - q) < 0.01 } ?? false }
        func held(_ line: DrawnLine?) -> Bool { line.map { !$0.free.0 && !$0.free.1 } ?? false }
        // Crossing the wall by 4 pixels: kept.
        let crossing = applied([SIMD2(10, 20), SIMD2(34, 20)])
        #expect(near(crossing?.points.first, SIMD2(10, 20)) && near(crossing?.points.last, SIMD2(34, 20)) && held(crossing))
        // Stopping 5 pixels short: kept, and not free for `closeFreeEnds` to lead on.
        let short = try #require(applied([SIMD2(10, 20), SIMD2(25, 20)]))
        #expect(near(short.points.last, SIMD2(25, 20)) && held(short))
        // Run off the canvas: cut at the frame.
        let off = applied([SIMD2(10, 20), SIMD2(10, 50)])
        #expect(off?.points.last?.y == Float(h - 1) && held(off))
        // A loop past its start: both tails stay.
        let loop = applied([SIMD2(4, 10), SIMD2(20, 10), SIMD2(20, 26), SIMD2(8, 26), SIMD2(8, 6)])
        #expect(near(loop?.points.first, SIMD2(4, 10)) && near(loop?.points.last, SIMD2(8, 6)) && held(loop))

        // The drawing's own free end, 6 pixels above the short drawn line, reaches it; the drawn
        // line stays as it was.
        var lines = [wall, short, line((2...14).map { SIMD2(15, Float($0)) }, free: (false, true))]
        let walls = LineLayering.walls(lines, width: w, height: h)
        let colorEdge = [Bool](repeating: false, count: w * h)
        #expect(LineLayering.closeFreeEnds(&lines, walls: walls, colorEdge: colorEdge, reach: [10, 10, 10]) == 1)
        #expect(lines[1].points == short.points)
        #expect(near(lines[2].points.last, SIMD2(15, 20)))
    }

    /// The points of the interior stroke passing within a pixel of `p`, if one does.
    static func stroke(in t: Template, near p: SIMD2<Float>) -> [SIMD2<Float>]? {
        let art = t.lineArt!
        for s in art.strokes {
            let points = Array(art.strokePoints[Int(s.pointStart)..<Int(s.pointStart + s.pointCount)])
            for (a, b) in zip(points, points.dropFirst()) {
                let ab = b - a
                let u = min(max(simdDot(p - a, ab) / max(simdLengthSquared(ab), 1e-9), 0), 1)
                if simdLength(p - (a + ab * u)) < 1 { return points }
            }
        }
        return nil
    }
}
