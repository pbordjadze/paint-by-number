import Foundation
import Testing
@testable import PaintCore

@Suite("Line art")
struct LineArtTests {

    // MARK: - A synthetic scene

    /// `Fixtures/layered-photo.ppm`, 128×96: flat sky (150, 190, 230) over flat ground
    /// (90, 150, 70), the horizon at y = 48, a dark red disc (140, 30, 40) of radius 18 around
    /// (40, 48) and a yellow square (240, 200, 40) over x 80..<112, y 30..<62.
    static func photo() -> RGBAImage { try! Netpbm.read(TestFixtures.data("layered-photo.ppm")) }

    /// `Fixtures/layered-edges.pgm`, the photo's lines as a learned detector draws them (soft:
    /// a Gaussian profile, σ = 2 px): 0.95 around the disc and the square, 0.9 along the
    /// horizon where it is visible, 0.62 across the ground at y = 80 (same paint on both
    /// sides) and 0.42 down the sky at x = 60 (likewise). Values are rounded to 8 bits.
    static func edges() -> EdgeMap {
        let image = try! Netpbm.read(TestFixtures.data("layered-edges.pgm"))
        return EdgeMap(width: image.width, height: image.height, values: (0..<(image.width * image.height)).map { image.pixels[$0 * 4] })
    }

    /// `edges()` with a soft line (σ = 2 px, 0.9 at its centre) added from `a` to `b` (pixel
    /// coordinates of the photo): a stretch of drawing that bounds no cell when it runs through
    /// a flat area.
    static func edges(adding a: SIMD2<Float>, to b: SIMD2<Float>) -> EdgeMap {
        var map = edges()
        let ab = b - a, length2 = max(simdLengthSquared(ab), 1e-6)
        for y in 0..<map.height {
            for x in 0..<map.width {
                let p = SIMD2(Float(x), Float(y))
                let t = min(max(simdDot(p - a, ab) / length2, 0), 1)
                let d2 = simdLengthSquared(p - (a + ab * t))
                let value = UInt8((0.9 * exp(-d2 / 8) * 255).rounded())
                map.values[y * map.width + x] = max(map.values[y * map.width + x], value)
            }
        }
        return map
    }

    /// A coloring book with the scene's thresholds: the disc, the square and the horizon are
    /// outlines, the ground's line detail and the sky's too faint to draw. Same-paint cells join
    /// across everything but outlines, as the app's books do.
    static func settings(_ change: (inout LineArtSettings) -> Void = { _ in }) -> GenerationSettings {
        var lineArt = LineArtSettings(
            outlineThreshold: 0.8, detailThreshold: 0.5, minimumStrokeLength: 10, gapBridging: 6, lineSmoothing: 0.5)
        change(&lineArt)
        return GenerationSettings(colorCount: 8, detail: 0.5, lineArt: lineArt)
    }

    static func generate(
        _ settings: GenerationSettings = settings(), eyes: [[SIMD2<Float>]] = [], input: Bool = true
    ) throws -> TemplateGenerator.Output {
        try TemplateGenerator(settings: settings).generate(
            from: photo(), lineArt: input ? LineArtInput(edges: edges(), eyes: eyes) : nil, cancel: .none)
    }

    /// Generation from a given photo and line-art input (nil: the settings alone).
    static func generate(
        _ settings: GenerationSettings, photo: RGBAImage = Self.photo(), input: LineArtInput?,
        cancel: CancellationCheck = .none
    ) throws -> TemplateGenerator.Output {
        try TemplateGenerator(settings: settings).generate(from: photo, lineArt: input, cancel: cancel)
    }

    /// Length of edges per layer (outline, detail, texture, color).
    static func lengths(_ t: Template) -> [Float] {
        var out: [Float] = [0, 0, 0, 0]
        for (k, e) in t.edges.enumerated() {
            let p = t.points(of: e)
            for i in p.indices.dropFirst() { out[Int(t.lineArt!.edgeLayers[k])] += simdLength(p[i] - p[i - 1]) }
        }
        return out
    }

    // MARK: - Generation

    @Test func lineArtTemplateIsValid() throws {
        let out = try Self.generate()
        let t = out.template
        let lines = try #require(t.lineArt)
        #expect(lines.style == .coloringBook)
        #expect(lines.edgeLayers.count == t.edges.count && lines.edgeWeights.count == t.edges.count)
        let report = expectValid(t)
        #expect(report.badLines == [])
        #expect(out.vectorStats.labelRoomUnmet == 0)
        // The disc, square and horizon are outlines.
        #expect(Self.lengths(t)[0] > 300, "\(Self.lengths(t))")
        let stats = try #require(out.lineArtStats)
        #expect(stats.cells == t.regions.count)
        #expect(out.segmentation.regionCount == t.regions.count)
        // The ground's detail line is drawn inside its cell; split, it divides the ground's paint
        // into two cells.
        #expect(lines.strokes.contains { $0.layer == LineLayer.detail.rawValue })
        let split = try Self.generate(Self.settings { $0.samePaint = .split })
        let splitStats = try #require(split.lineArtStats)
        #expect(Self.lengths(split.template)[1] > 150, "\(Self.lengths(split.template))")
        #expect(split.template.regions.count > splitStats.segmentationRegions)
    }

    @Test func classicIgnoresTheEdgeMap() throws {
        var classic = Self.settings()
        classic.lineArt.style = .classic
        let plain = try TemplateGenerator(settings: classic).generate(from: Self.photo(), cancel: .none)
        let given = try Self.generate(classic)
        #expect(given.template == plain.template)
        #expect(given.template.lineArt == nil && given.lineArtStats == nil)
        #expect(!LineArtSettings.Style.classic.usesEdgeMap && LineArtSettings.Style.coloringBook.usesEdgeMap)
        // A coloring book without an edge map is classic lines over the book's flatter paint.
        let missing = try Self.generate(Self.settings(), input: false)
        #expect(missing.template.lineArt == nil && missing.lineArtStats == nil)
        #expect(missing.template.regions.count <= plain.template.regions.count)
        #expect(missing.template.palette.count <= plain.template.palette.count)
    }

    // MARK: - Coloring book

    /// A coloring book draws every line that is detail or stronger, keeps the stretches that
    /// bound no cell as strokes (a drawing, not just cell boundaries), has no texture lines,
    /// and says so in its template.
    @Test func coloringBookIsADrawingOverTheCells() throws {
        // A short, strong line in the open sky: it closes nothing.
        let dangling = Self.edges(adding: SIMD2(12, 8), to: SIMD2(36, 14))
        func generate(_ settings: GenerationSettings) throws -> TemplateGenerator.Output {
            try Self.generate(settings, input: LineArtInput(edges: dangling))
        }
        let split = Self.settings { $0.samePaint = .split }
        let book = try generate(split).template
        #expect(book.lineArt?.style == .coloringBook)
        expectValid(book)
        // The dangling line is drawn, in the sky's cell.
        let sky = try #require(book.region(at: SIMD2<Float>(45, 15)))
        func strokes(_ t: Template, near p: SIMD2<Float>) -> [InteriorStroke] {
            let art = t.lineArt!
            return art.strokes.filter { s in
                let pts = art.strokePoints[Int(s.pointStart)..<Int(s.pointStart + s.pointCount)]
                return zip(pts, pts.dropFirst()).contains { a, b in
                    let ab = b - a
                    let t = min(max(simdDot(p - a, ab) / max(simdLengthSquared(ab), 1e-6), 0), 1)
                    return simdLength(p - (a + ab * t)) < 6
                }
            }
        }
        let middle = SIMD2<Float>(24 * 1.5, 11 * 1.5)
        let drawn = strokes(book, near: middle)
        #expect(drawn.count == 1 && drawn.first?.region == UInt32(sky) && drawn.first?.layer == LineLayer.outline.rawValue)
        // No texture lines: nothing below the detail threshold is drawn, so the sky's faint
        // line (0.42) is gone, while the ground's detail line (0.62) splits the ground.
        let lengths = Self.lengths(book)
        #expect(lengths[2] == 0 && !book.lineArt!.strokes.contains { $0.layer == LineLayer.texture.rawValue })
        #expect(lengths[1] > 150 && lengths[0] > 300, "\(lengths)")
        let stats = try #require(generate(split).lineArtStats)
        #expect(stats.interiorStrokes == book.lineArt!.strokes.count && stats.cells == book.regions.count)
        // Every stroke is drawing of some length, inside its cell.
        for s in book.lineArt!.strokes {
            let pts = book.lineArt!.strokePoints[Int(s.pointStart)..<Int(s.pointStart + s.pointCount)]
            let length = zip(pts, pts.dropFirst()).reduce(Float(0)) { $0 + simdLength($1.1 - $1.0) }
            #expect(length >= LineLayering.minimumRun - 1, "a \(length)-unit stroke in cell \(s.region)")
            #expect(book.region(at: pts[pts.startIndex + pts.count / 2]) == Int(s.region))
        }
    }

    @Test func samePaintChoices() throws {
        // No texture lines, so joining across them splits like Always Split; joining across
        // detail unites the ground's two cells and draws the line inside.
        let split = try Self.generate(Self.settings { $0.samePaint = .split }).template
        let texture = try Self.generate(Self.settings { $0.samePaint = .joinTexture }).template
        let all = try Self.generate(Self.settings { $0.samePaint = .joinAllButOutlines }).template
        #expect(texture == split)
        #expect(all.regions.count < split.regions.count)
        #expect(all.lineArt!.strokes.contains { $0.layer == LineLayer.detail.rawValue })
        for t in [split, all] { expectValid(t) }
        // Interior strokes lie inside their cell, whose paint is on both sides.
        for s in all.lineArt!.strokes {
            let p = all.lineArt!.strokePoints[Int(s.pointStart) + Int(s.pointCount) / 2]
            #expect(all.region(at: p) == Int(s.region))
        }
        // No stroke is a trimming leftover: a boundary stretch's end point or a merged tiny cell's
        // sliver (shorter than the layering's minimum run, less the simplification's slack).
        for t in [split, all] {
            let art = t.lineArt!
            for s in art.strokes where !(s.pointCount > 2 && art.strokePoints[Int(s.pointStart)] == art.strokePoints[Int(s.pointStart + s.pointCount - 1)]) {
                let pts = art.strokePoints[Int(s.pointStart)..<Int(s.pointStart + s.pointCount)]
                let length = zip(pts, pts.dropFirst()).reduce(Float(0)) { $0 + simdLength($1.1 - $1.0) }
                #expect(length >= LineLayering.minimumRun - 1, "a \(length)-unit stroke inside cell \(s.region)")
            }
        }
    }

    @Test func coloringBookSVGIsOneDrawing() throws {
        let book = try Self.generate().template
        let options = SVGExport.Options(painted: false, outlines: true, numbers: false)
        let svg = SVGExport.render(book, options: options)
        #expect(svg.contains("id=\"lines-drawing\"") && !svg.contains("lines-color") && !svg.contains("lines-outline"))
        // A template of the retired layered style draws as a coloring book.
        var layered = book
        layered.lineArt!.style = .layered
        #expect(SVGExport.render(layered, options: options) == svg)
    }

    @Test func selectedColorIsHatched() throws {
        let book = try Self.generate().template
        let selected = SVGExport.render(book, options: .init(painted: false, outlines: true, numbers: true, selectedColor: 0))
        #expect(selected.contains("<pattern id=\"hatch\"") && selected.contains("id=\"selection\""))
        // Its cells, and only its cells: one subpath per ring of every region of that paint.
        let cells = book.regions.indices.filter { book.regions[$0].colorIndex == 0 }
        let rings = cells.reduce(0) { $0 + book.polygons(ofRegion: $1).count }
        let group = selected.components(separatedBy: "id=\"selection\"")[1].components(separatedBy: "</g>")[0]
        #expect(group.components(separatedBy: "Z").count - 1 == rings && rings > 0)
        // Nothing selected, or a paint the template doesn't have: no selection group.
        #expect(!SVGExport.render(book).contains("selection"))
        #expect(!SVGExport.render(book, options: .init(selectedColor: book.palette.count)).contains("selection"))
    }

    @Test func deterministic() throws {
        let a = try Self.generate().template.encoded(), b = try Self.generate().template.encoded()
        #expect(a == b)
    }

    @Test func subjectsCloseTheirSilhouettes() throws {
        func generate(objects: [[SIMD2<Float>]], on: Bool = true) throws -> Template {
            try Self.generate(
                Self.settings { $0.outlineObjects = on }, input: LineArtInput(edges: Self.edges(), objects: objects)).template
        }
        let plain = try Self.generate().template
        let outline = Int(LineLayer.outline.rawValue)
        // A subject in the sky's top-left corner with no edge of its own: its silhouette is
        // drawn whole, as an outline, and walls its cells off from the rest of the sky.
        let box: [SIMD2<Float>] = [SIMD2(4, 4), SIMD2(56, 4), SIMD2(56, 26), SIMD2(4, 26)].map { $0 / SIMD2(128, 96) }
        let boxed = try generate(objects: [box])
        #expect(boxed.regions.count > plain.regions.count)
        #expect(Self.lengths(boxed)[outline] > Self.lengths(plain)[outline] + 100)
        expectValid(boxed)
        // The disc's own silhouette runs along its drawn contour: nothing is added.
        let disc = (0..<64).map { k -> SIMD2<Float> in
            let a = Float(k) / 64 * 2 * .pi
            return SIMD2(40 + 18 * cos(a), 48 + 18 * sin(a)) / SIMD2(128, 96)
        }
        let same = try generate(objects: [disc])
        #expect(same.regions.count == plain.regions.count)
        #expect(abs(Self.lengths(same)[outline] - Self.lengths(plain)[outline]) < 20)
        // Off, subjects change nothing.
        #expect(try generate(objects: [box], on: false) == plain)
    }

    @Test func maskContoursTraceShapes() {
        // A 64×48 mask: a rectangle (x 8..<40, y 6..<30) and a disc of radius 7 around (52, 38);
        // a 2-pixel speck is left out.
        let w = 64, h = 48
        var mask = [Bool](repeating: false, count: w * h)
        for y in 6..<30 { for x in 8..<40 { mask[y * w + x] = true } }
        for y in 0..<h {
            for x in 0..<w where (x - 52) * (x - 52) + (y - 38) * (y - 38) <= 49 { mask[y * w + x] = true }
        }
        mask[2 * w + 60] = true
        mask[2 * w + 61] = true
        let outlines = MaskContours.outlines(of: mask, width: w, height: h)
        #expect(outlines.count == 2)
        func area(_ poly: [SIMD2<Float>]) -> Float {
            var sum: Float = 0
            for i in poly.indices {
                let a = poly[i] * SIMD2(Float(w), Float(h)), b = poly[(i + 1) % poly.count] * SIMD2(Float(w), Float(h))
                sum += a.x * b.y - b.x * a.y
            }
            return abs(sum) / 2
        }
        // Largest first: the rectangle is exactly its four corners, the disc close to its area.
        #expect(outlines[0].count == 4 && abs(area(outlines[0]) - 32 * 24) < 1)
        #expect(outlines[0].contains(SIMD2(8.0 / 64, 6.0 / 48)) && outlines[0].contains(SIMD2(40.0 / 64, 30.0 / 48)))
        #expect(abs(area(outlines[1]) - Float.pi * 49) < 25 && outlines[1].count >= 8)
        #expect(outlines.allSatisfy { $0.allSatisfy { $0.x >= 0 && $0.x <= 1 && $0.y >= 0 && $0.y <= 1 } })
        // The whole mask: the frame itself, one polygon.
        let full = MaskContours.outlines(of: [Bool](repeating: true, count: w * h), width: w, height: h)
        #expect(full.count == 1 && full[0].count == 4 && abs(area(full[0]) - Float(w * h)) < 1)
        #expect(MaskContours.outlines(of: [Bool](repeating: false, count: w * h), width: w, height: h).isEmpty)
    }

    @Test func contoursDecideTheOutlines() throws {
        // The drawing (`edges()`) is drawn as before; which of its lines are outlines follows the
        // contour map alone: scaled under the outline threshold, nothing is an outline (the
        // disc, square and horizon become detail); with the ground's 0.62 line raised to full
        // strength in the contours, that line is an outline though the drawing has it faint.
        let split = Self.settings { $0.samePaint = .split }
        func generate(contours: EdgeMap) throws -> Template {
            try Self.generate(split, input: LineArtInput(edges: Self.edges(), contours: contours)).template
        }
        let plain = try Self.generate(split).template
        var faint = Self.edges()
        faint.values = faint.values.map { UInt8(Float($0) * 0.6) }
        let noOutlines = try generate(contours: faint)
        let outline = LineLayer.outline.rawValue, detail = LineLayer.detail.rawValue
        #expect(Self.lengths(plain)[Int(outline)] > 100)
        #expect(Self.lengths(noOutlines)[Int(outline)] == 0)
        #expect(Self.lengths(noOutlines)[Int(detail)] > Self.lengths(plain)[Int(detail)] + 100)
        var strongGround = Self.edges()
        for x in 0..<strongGround.width { for y in 78...82 { strongGround.values[y * strongGround.width + x] = 255 } }
        let groundOutlined = try generate(contours: strongGround)
        // The template's canvas is the photo scaled up to the working size.
        func groundEdges(_ t: Template) -> [Int] {
            let scale = Float(t.height) / 96
            return t.edges.indices.filter { k in
                t.edges[k].right != BoundaryEdge.outside && t.points(of: t.edges[k]).allSatisfy { abs($0.y - 80 * scale) < 3 * scale }
            }
        }
        let outlined = groundEdges(groundOutlined), plainGround = groundEdges(plain)
        #expect(!outlined.isEmpty && outlined.allSatisfy { groundOutlined.lineArt!.edgeLayers[$0] == outline })
        #expect(!plainGround.isEmpty && plainGround.allSatisfy { plain.lineArt!.edgeLayers[$0] == detail })
        // The same map as contours changes nothing.
        #expect(try generate(contours: Self.edges()) == plain)
    }

    @Test func eyesAreOutlined() throws {
        // A diamond inside the yellow square (normalized to the photo).
        let c = SIMD2<Float>(96 / 128, 46 / 96)
        let rx: Float = 9 / 128, ry: Float = 7 / 96
        let eye: [SIMD2<Float>] = [SIMD2(c.x - rx, c.y), SIMD2(c.x, c.y - ry), SIMD2(c.x + rx, c.y), SIMD2(c.x, c.y + ry)]
        let with = try Self.generate(eyes: [eye])
        let without = try Self.generate()
        #expect(with.lineArtStats?.eyes == 1)
        #expect(with.template.regions.count > without.template.regions.count)
        expectValid(with.template)
        // The diamond is drawn as an outline: outline edges run around its centre.
        let t = with.template
        let centre = SIMD2<Float>(c.x * Float(t.width), c.y * Float(t.height))
        var nearOutline: Float = 0
        for (k, e) in t.edges.enumerated() where t.lineArt!.edgeLayers[k] == LineLayer.outline.rawValue {
            let p = t.points(of: e)
            for i in p.indices.dropFirst() where simdLength(p[i] - centre) < 16 { nearOutline += simdLength(p[i] - p[i - 1]) }
        }
        #expect(nearOutline > 40, "\(nearOutline)")
        // Switched off, eyes are ignored.
        let off = try Self.generate(Self.settings { $0.outlineEyes = false }, eyes: [eye])
        #expect(off.template == without.template)
    }

    @Test func anEyeTooSmallForANumberIsStillDrawn() throws {
        // A diamond 3 units across inside the square: no room for a number, so its cell joins
        // the square and the contour is drawn inside it, closed.
        let c = SIMD2<Float>(96 / 128, 46 / 96)
        let rx: Float = 1 / 128, ry: Float = 1 / 96
        let eye: [SIMD2<Float>] = [SIMD2(c.x - rx, c.y), SIMD2(c.x, c.y - ry), SIMD2(c.x + rx, c.y), SIMD2(c.x, c.y + ry)]
        let t = try Self.generate(eyes: [eye]).template
        let lines = try #require(t.lineArt)
        let stroke = try #require(lines.strokes.first { $0.layer == LineLayer.outline.rawValue })
        let first = lines.strokePoints[Int(stroke.pointStart)]
        let last = lines.strokePoints[Int(stroke.pointStart + stroke.pointCount) - 1]
        #expect(first == last)
        #expect(t.region(at: first) == Int(stroke.region))
        expectValid(t)
    }

    @Test func mergingCloseColorsGivesFewerCells() throws {
        // A soft gradient band across the ground makes paint-only boundaries.
        var image = Self.photo()
        for y in 48..<96 {
            for x in 0..<128 where x < 80 || x >= 112 || y >= 62 {
                let dx = Float(x) - 40, dy = Float(y) - 48
                guard dx * dx + dy * dy > 18 * 18 else { continue }
                image[x, y] = SIMD4(UInt8(60 + x / 2), UInt8(130 + x / 4), 70, 255)
            }
        }
        func run(_ keep: Bool) throws -> Template {
            var s = Self.settings { $0.keepColorEdges = keep }
            s.colorCount = 16
            return try Self.generate(s, photo: image, input: LineArtInput(edges: Self.edges())).template
        }
        let kept = try run(true), merged = try run(false)
        #expect(merged.regions.count < kept.regions.count)
        expectValid(merged)
    }

    @Test func edgeMapAtAnotherResolution() throws {
        // A map at half the photo's size still lines up (it is resampled to the working size).
        let full = Self.edges()
        var half = [UInt8](repeating: 0, count: 64 * 48)
        for y in 0..<48 {
            for x in 0..<64 {
                let a = Int(full.values[2 * y * 128 + 2 * x]) + Int(full.values[2 * y * 128 + 2 * x + 1])
                let b = Int(full.values[(2 * y + 1) * 128 + 2 * x]) + Int(full.values[(2 * y + 1) * 128 + 2 * x + 1])
                half[y * 64 + x] = UInt8((a + b + 2) / 4)
            }
        }
        let t = try Self.generate(
            Self.settings(), input: LineArtInput(edges: EdgeMap(width: 64, height: 48, values: half))).template
        expectValid(t)
        #expect(Self.lengths(t)[0] > 300)
    }

    @Test func emptyEdgeMapKeepsTheCells() throws {
        let blank = EdgeMap(width: 128, height: 96, values: [UInt8](repeating: 0, count: 128 * 96))
        // The book's paint without its lines: the same settings without an edge map.
        let plain = try Self.generate(Self.settings(), input: false).template
        let t = try Self.generate(Self.settings(), input: LineArtInput(edges: blank)).template
        #expect(t.regions.count == plain.regions.count)
        #expect(t.lineArt!.edgeLayers.allSatisfy { $0 == LineLayer.color.rawValue })
        #expect(t.lineArt!.strokes.isEmpty)
        expectValid(t)
    }

    // MARK: - Maps

    /// A drawing over contours: the drawing's levels where it has lines, the contours scaled
    /// elsewhere; a contour map of another size is resampled first, and the result is bytes
    /// for bytes the same on every run.
    @Test func drawingCombinesWithContours() {
        let drawing = EdgeMap(width: 4, height: 2, values: [0, 200, 40, 0, 255, 0, 0, 10])
        let contours = EdgeMap(width: 4, height: 2, values: [100, 100, 100, 100, 0, 255, 60, 60])
        let combined = EdgeMap.combined(drawing: drawing, contours: contours)
        #expect(combined.values == [85, 200, 85, 85, 255, 217, 51, 51])
        #expect(EdgeMap.combined(drawing: drawing, contours: contours, contourWeight: 1) .values == [100, 200, 100, 100, 255, 255, 60, 60])
        // Contours twice the drawing's size resample to it; the same levels come out again.
        let large = EdgeMap(width: 8, height: 4, values: (0..<32).map { UInt8(($0 * 37) % 256) })
        let small = large.resampled(width: 4, height: 2)
        #expect(small.width == 4 && small.height == 2 && small == large.resampled(width: 4, height: 2))
        #expect(EdgeMap.combined(drawing: drawing, contours: large) == EdgeMap.combined(drawing: drawing, contours: small))
        #expect(large.resampled(width: 8, height: 4) == large)
        // Resampling up and down keeps a flat map flat and its levels inside the range.
        let flat = EdgeMap(width: 3, height: 3, values: [UInt8](repeating: 77, count: 9))
        #expect(flat.resampled(width: 7, height: 5).values.allSatisfy { $0 == 77 })
    }

    /// The detector says which of the two maps a generation reads: the drawing over the
    /// contours with the contours deciding the outlines, or either alone, deciding everything.
    @Test func detectorPicksWhatTheInputReads() {
        let drawing = EdgeMap(width: 4, height: 2, values: [0, 200, 40, 0, 255, 0, 0, 10])
        let contours = EdgeMap(width: 4, height: 2, values: [100, 100, 100, 100, 0, 255, 60, 60])
        let eyes: [[SIMD2<Float>]] = [[SIMD2(0.1, 0.1), SIMD2(0.4, 0.1), SIMD2(0.4, 0.4)]]
        let objects: [[SIMD2<Float>]] = [[SIMD2(0.5, 0.5), SIMD2(0.9, 0.5), SIMD2(0.9, 0.9)]]
        func input(_ detector: LineArtSettings.Detector, weight: Float = EdgeMap.contourWeight) -> LineArtInput {
            LineArtInput(
                drawing: drawing, contours: contours, detector: detector, eyes: eyes, objects: objects, contourWeight: weight)
        }
        #expect(input(.drawingAndContours) == LineArtInput(
            edges: EdgeMap.combined(drawing: drawing, contours: contours), eyes: eyes, objects: objects, contours: contours))
        #expect(input(.drawingAndContours, weight: 1).edges == EdgeMap.combined(drawing: drawing, contours: contours, contourWeight: 1))
        #expect(input(.drawing) == LineArtInput(edges: drawing, eyes: eyes, objects: objects))
        #expect(input(.contours) == LineArtInput(edges: contours, eyes: eyes, objects: objects))
    }

    // MARK: - Stages

    @Test func layersByHysteresisAlongTheLine() {
        // Points 2.5 apart: a seed needs three points (5 units) at or above its threshold.
        let strength: [Float] = [0.2, 0.55, 0.9, 0.9, 0.9, 0.55, 0.45, 0.35, 0.2, 0.32, 0.35, 0.33, 0.1, 0.9, 0.1]
        let arc = strength.indices.map { Float($0) * 2.5 }
        let layer = LineLayering.classify(strength, arc: arc, closed: false, thresholds: [0.8, 0.5, 0.3])
        // The sustained 0.9 makes its run above 0.48 an outline; 0.45 and 0.35 are detail
        // (above 0.25, connected to the 0.55s, which reach 0.5 for 10 units with the 0.9s);
        // 0.2 to 0.33 are texture (above 0.15, seeded by 0.32–0.33); the lone 0.9 between
        // 0.1s is too short for any seed, and 0.1 is below every layer.
        #expect(layer == [2, 0, 0, 0, 0, 0, 1, 1, 2, 2, 2, 2, LineLayering.none, LineLayering.none, LineLayering.none])
    }

    @Test func crowdedLinesAreDetailUnlessLong() {
        // On a 1500-unit canvas: a short, strong stroke is an outline where nothing crowds it
        // and detail where lines crowd; a long one stays an outline either way.
        let w = 1500, h = 100
        func stroke(length: Int) -> StrokeGraph.Stroke {
            StrokeGraph.Stroke(
                points: (0..<length).map { SIMD2(Float(10 + $0), 50) }, strength: [Float](repeating: 0.95, count: length),
                closed: false, free: (true, true), links: [])
        }
        let calm = [Float](repeating: 0, count: w * h), crowded = [Float](repeating: 1, count: w * h)
        let thresholds: [Float] = [0.85, 0.5, 0.3]
        func layers(_ s: StrokeGraph.Stroke, _ clutter: [Float]) -> Set<UInt8> {
            Set(LineLayering.layered([s], thresholds: thresholds, clutter: clutter, width: w).flatMap(\.layer))
        }
        #expect(layers(stroke(length: 60), calm) == [LineLayer.outline.rawValue])
        #expect(layers(stroke(length: 60), crowded) == [LineLayer.detail.rawValue])
        #expect(layers(stroke(length: 200), crowded) == [LineLayer.outline.rawValue])
        // Half crowded: the threshold is halfway to 1, so 0.95 still makes an outline.
        let half = [Float](repeating: 0.5, count: w * h)
        #expect(layers(stroke(length: 60), half) == [LineLayer.outline.rawValue])
    }

    @Test func clutterCountsCrowdedLinesOnly() throws {
        // A 1500-unit canvas (crowding is measured relative to the canvas size): a lone line on
        // the left, lines 6 units apart on the right, 30 apart in the middle.
        let w = 1500, h = 200
        var mask = [Bool](repeating: false, count: w * h)
        for y in 0..<h { mask[y * w + 100] = true }
        for x in stride(from: 400, to: 800, by: 30) { for y in 0..<h { mask[y * w + x] = true } }
        for x in stride(from: 1000, to: 1400, by: 6) { for y in 0..<h { mask[y * w + x] = true } }
        let clutter = try LineDetection.clutter(mask, width: w, height: h, cancel: .none)
        #expect(clutter[100 * w + 100] == 0)
        #expect(clutter[100 * w + 610] < 0.05)
        #expect(clutter[100 * w + 1200] > 0.9)
    }

    @Test func linesAroundEyesAreStronger() {
        let w = 200, h = 100
        // A texture line passing just above an eye, and another far from it.
        func line(_ y: Float) -> DrawnLine {
            DrawnLine(points: (0..<180).map { SIMD2(Float(10 + $0), y) }, strength: [Float](repeating: 0.35, count: 180),
                      layer: [UInt8](repeating: LineLayer.texture.rawValue, count: 180), closed: false,
                      free: (true, true), links: [], eye: false)
        }
        let eye: [SIMD2<Float>] = [SIMD2(90, 50), SIMD2(100, 44), SIMD2(110, 50), SIMD2(100, 56)]
        let out = LineLayering.addEyes([line(40), line(90)], eyes: [eye], width: w, height: h)
        #expect(out.count == 3)
        let near = out[0], far = out[1]
        #expect(near.layer[90] == LineLayer.detail.rawValue)
        #expect(near.layer[0] == LineLayer.texture.rawValue)
        #expect(far.layer.allSatisfy { $0 == LineLayer.texture.rawValue })
        #expect(out[2].eye && out[2].closed && out[2].layer.allSatisfy { $0 == LineLayer.outline.rawValue })
    }

    @Test func lineArtGenerationCancels() throws {
        // Cancelled at about 25 evenly spaced check counts up to the last: always a CancellationError.
        let input = LineArtInput(edges: Self.edges())
        let total = LockedCounter()
        _ = try Self.generate(Self.settings(), input: input, cancel: CancellationCheck { total.increment(); return false })
        let checks = total.count
        #expect(checks > 20)
        for after in stride(from: 0, to: checks, by: max(1, checks / 25)) {
            let counter = LockedCounter()
            #expect(throws: CancellationError.self, "after \(after)") {
                try Self.generate(Self.settings(), input: input, cancel: CancellationCheck { counter.increment() > after })
            }
        }
    }

    @Test func thinningLeavesOnePixelLines() {
        let w = 40, h = 20
        var mask = [Bool](repeating: false, count: w * h)
        for y in 7..<12 { for x in 4..<36 { mask[y * w + x] = true } }
        Thinning.thin(&mask, width: w, height: h)
        // One pixel thick: no 2×2 block of set pixels.
        for y in 0..<(h - 1) {
            for x in 0..<(w - 1) {
                #expect(!(mask[y * w + x] && mask[y * w + x + 1] && mask[(y + 1) * w + x] && mask[(y + 1) * w + x + 1]))
            }
        }
        let count = mask.filter { $0 }.count
        #expect(count > 24 && count < 36)
    }

    @Test func gapsAreBridged() {
        // Two collinear strokes with a 5-pixel gap become one.
        let w = 60, h = 20
        var mask = [Bool](repeating: false, count: w * h)
        for x in 5..<25 { mask[10 * w + x] = true }
        for x in 30..<55 { mask[10 * w + x] = true }
        var g = StrokeGraph.trace(mask, strength: [Float](repeating: 1, count: w * h), width: w, height: h)
        g.mergeDegree2()
        #expect(g.components().count == 2)
        g.bridgeGaps(4)
        #expect(g.components().count == 2)
        g.bridgeGaps(7)
        #expect(g.components().count == 1)
        let strokes = g.strokes(sigma: 1)
        #expect(strokes.count == 1)
        #expect(strokes[0].free == (true, true))
    }

    // MARK: - Validation

    @Test func validationReportsBadLineData() throws {
        var t = try Self.generate().template
        #expect(t.validate().badLines == [])
        var classic = t
        classic.lineArt = nil
        #expect(classic.validate().badLines == nil)
        #expect(!classic.validate().description.contains("lines"))
        // A stroke moved to a region it does not touch.
        let stroke = t.lineArt!.strokes[0]
        let points = t.lineArt!.strokePoints[Int(stroke.pointStart)..<Int(stroke.pointStart + stroke.pointCount)]
        let far = t.regions.indices.first { r in
            points.allSatisfy { p in
                let x = Int(p.x), y = Int(p.y)
                return (max(0, y - 1)...min(t.height - 1, y + 1)).allSatisfy { yy in
                    (max(0, x - 1)...min(t.width - 1, x + 1)).allSatisfy { xx in t.regionMap[xx, yy] != UInt32(r) }
                }
            }
        }!
        t.lineArt!.strokes[0].region = UInt32(far)
        let report = t.validate()
        #expect(!report.isValid)
        #expect(report.badLines?.count == 1)
        #expect(report.description.contains("lines 1"))
    }
}
