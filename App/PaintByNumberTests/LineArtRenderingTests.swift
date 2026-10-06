import CoreGraphics
import Foundation
import PaintCore
import Testing
import UIKit
@testable import PaintByNumber

/// Line art: the outline geometry the canvas uploads, and how the canvas, offscreen renders and
/// the CoreGraphics rasterizer draw a coloring book (`ColoringBookLook`) at its Line Weight, and
/// a template of the retired layered style, which draws as a book. Classic templates must draw
/// exactly as before.
struct LineArtRenderingTests {
    /// The canvas tests' mosaic as a coloring book, with every edge's layer set by its index
    /// (border edges too) and one outline-layer stroke inside each cell that has room: layers are
    /// known per edge.
    static let book: Template = {
        let t = Fixtures.mosaic
        var layers: [UInt8] = [], weights: [UInt8] = []
        for e in t.edges.indices {
            layers.append(UInt8(e % 4))
            weights.append(UInt8(40 + (e * 37) % 200))
        }
        var points: [SIMD2<Float>] = [], strokes: [InteriorStroke] = []
        for label in t.labels where label.radius >= 14 {
            let c = label.position + SIMD2(0, 0.6 * label.radius), half = 0.45 * label.radius
            strokes.append(InteriorStroke(
                pointStart: UInt32(points.count), pointCount: 3, layer: LineLayer.outline.rawValue, weight: 200, region: label.region))
            points += [c - SIMD2(half, 0), c, c + SIMD2(half, 0)]
        }
        var book = t
        book.lineArt = TemplateLineArt(
            edgeLayers: layers, edgeWeights: weights, strokePoints: points, strokes: strokes, style: .coloringBook)
        return book
    }()

    /// The same line art as the retired layered style recorded it.
    static let layered: Template = {
        var t = book
        t.lineArt!.style = .layered
        return t
    }()

    // MARK: Line data and geometry

    @Test func classicGeometryIsTheEdgesAsEver() {
        let t = Fixtures.mosaic
        let g = OutlineGeometry(t)
        #expect(!g.isColoringBook && g.points == t.points)
        var segments: [SIMD2<UInt32>] = []
        for (e, edge) in t.edges.enumerated() where edge.pointCount >= 2 {
            for k in 0..<(edge.pointCount - 1) { segments.append(SIMD2(edge.pointStart + k, UInt32(e))) }
        }
        #expect(g.segments == segments)
        #expect(g.lineRegions == t.edges.map { SIMD2($0.left, $0.right) })
        #expect(g.lineLayers == Array(repeating: 0, count: t.edges.count))
    }

    @Test func lineArtGeometryAddsStrokesAsLinesInsideTheirCell() throws {
        let t = Self.book
        let art = try #require(t.lineArt)
        let g = OutlineGeometry(t)
        #expect(g.isColoringBook)
        #expect(g.points == t.points + art.strokePoints)
        #expect(g.lineRegions.count == t.edges.count + art.strokes.count)
        for (e, edge) in t.edges.enumerated() {
            #expect(g.lineRegions[e] == SIMD2(edge.left, edge.right))
            #expect(g.lineLayers[e] == Float(art.edgeLayers[e]))
        }
        for (s, stroke) in art.strokes.enumerated() {
            let line = t.edges.count + s
            #expect(g.lineRegions[line] == SIMD2(stroke.region, stroke.region))
            #expect(g.lineLayers[line] == Float(stroke.layer))
            let segments = g.segments.filter { $0.y == UInt32(line) }
            #expect(segments.map(\.x) == (0..<(stroke.pointCount - 1)).map { UInt32(t.points.count) + stroke.pointStart + $0 })
        }
        let classicSegments = OutlineGeometry(Fixtures.mosaic).segments
        #expect(Array(g.segments.prefix(classicSegments.count)) == classicSegments)
        // A layered template's lines are the same geometry, drawn as a book.
        let layered = OutlineGeometry(Self.layered)
        #expect(layered.isColoringBook && layered.lineLayers == g.lineLayers && layered.segments == g.segments)
    }

    @Test func malformedLineArtIsSkippedNotTrusted() {
        var t = Self.book
        var art = t.lineArt!
        let good = art.strokes.count
        art.strokes.append(InteriorStroke(pointStart: UInt32(art.strokePoints.count - 1), pointCount: 2, layer: 0, weight: 9, region: 0))
        art.strokes.append(InteriorStroke(pointStart: 0, pointCount: 1, layer: 0, weight: 9, region: 0))
        art.strokes.append(InteriorStroke(pointStart: 0, pointCount: 2, layer: 7, weight: 9, region: 0))
        art.strokes.append(InteriorStroke(pointStart: 0, pointCount: 2, layer: 1, weight: 9, region: UInt32(t.regions.count)))
        art.edgeLayers[0] = 9
        t.lineArt = art
        let lines = DrawableLineArt(t)
        #expect(lines?.strokes.count == good)
        #expect(lines?.edgeLayers[0] == LineLayer.color.rawValue)
        // Line data that doesn't match the edges draws the template as classic.
        art.edgeWeights.removeLast()
        t.lineArt = art
        #expect(DrawableLineArt(t) == nil && !OutlineGeometry(t).isColoringBook)
    }

    // MARK: Uniforms

    @Test func classicAndBookUniforms() throws {
        var u = CanvasUniforms()
        u.ink.w = 0.434
        u.outline = SIMD4(1.25, 2.4, 1, 1)
        u.setClassicLines()
        #expect(u.lineAlpha == SIMD4(repeating: 0.434) && u.lineWidth == SIMD4(repeating: 1.25) && u.lineMode == .zero)
        // A book: full ink on every drawn layer, none on color edges, one width, the book mode.
        u.setColoringBookLines(width: 4)
        #expect(u.lineAlpha == SIMD4(1, 1, 1, 0) && u.lineWidth == SIMD4(4, 4, 4, 0) && u.lineMode == SIMD4(1, 0, 0, 0))

        let context = try #require(RenderContext.shared)
        let classic = try #require(CanvasScene(template: Fixtures.mosaic, context: context))
        #expect(!classic.isColoringBook)
        let c = CanvasSnapshot.uniforms(scene: classic, width: 240, height: 320, options: .preview)
        #expect(c.lineAlpha == SIMD4(repeating: c.ink.w) && c.lineWidth == SIMD4(repeating: c.outline.x) && c.lineMode == .zero)

        let book = try #require(CanvasScene(template: Self.book, context: context))
        #expect(book.isColoringBook && book.segmentCount > classic.segmentCount)
        #expect(try #require(CanvasScene(template: Self.layered, context: context)).isColoringBook)
        var options = CanvasSnapshot.Options.preview
        options.lineWeight = .bold
        let b = CanvasSnapshot.uniforms(scene: book, width: 240, height: 320, options: options)
        #expect(b.lineMode.x == 1 && b.lineAlpha == SIMD4(1, 1, 1, 0))
        #expect(abs(b.lineWidth.x - b.outline.x * ColoringBookLook.widthFactor * LineWeight.bold.factor) < 1e-4)
    }

    @Test func bookLineGrowsSlowerThanTheZoomAndFollowsTheWeight() {
        // Three times the classic line fitted, growing slower than the zoom.
        #expect(ColoringBookLook.widthPoints(depth: 0, weight: 1) == 3 * ClassicLook.widthPoints(depth: 0))
        #expect(ColoringBookLook.widthPoints(depth: 2, weight: 1) < 4 * ColoringBookLook.widthPoints(depth: 0, weight: 1))
        #expect(ColoringBookLook.widthPoints(depth: 1, weight: 2) == 2 * ColoringBookLook.widthPoints(depth: 1, weight: 1))
        #expect(ClassicLook.strength(depth: 0) == 0.7 && abs(ClassicLook.strength(depth: 2) - 1) < 1e-6)
    }

    @MainActor
    @Test func canvasFollowsTheLineWeight() throws {
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 700)
        window.overrideUserInterfaceStyle = .light
        window.isHidden = false
        defer { window.isHidden = true }
        func canvas(_ t: Template) -> CanvasView {
            let view = CanvasView(session: PaintingSession(template: t))
            window.addSubview(view)
            view.frame = window.bounds
            view.layoutIfNeeded()
            return view
        }
        let book = canvas(Self.book)
        defer { book.removeFromSuperview() }
        let regular = book.frameUniforms()
        #expect(regular.lineMode.x == 1 && regular.lineAlpha == SIMD4(1, 1, 1, 0))
        // A new weight reaches the next frame.
        book.lineWeight = .bold
        let bold = book.frameUniforms()
        #expect(abs(bold.lineWidth.x - regular.lineWidth.x * LineWeight.bold.factor) < 1e-3)
        // Classic templates ignore it.
        let classic = canvas(Fixtures.mosaic)
        defer { classic.removeFromSuperview() }
        classic.lineWeight = .bold
        let c = classic.frameUniforms()
        #expect(c.lineAlpha == SIMD4(repeating: c.ink.w) && c.lineWidth == SIMD4(repeating: c.outline.x) && c.lineMode == .zero)
    }

    // MARK: Rendering

    /// A template of the retired layered style draws exactly as the same line art does as a
    /// coloring book: on the canvas, in pictures and in print.
    @Test func layeredTemplatesDrawAsColoringBooks() throws {
        let size = CGSize(width: Self.book.width * 2, height: Self.book.height * 2)
        var options = CanvasSnapshot.Options(outlines: true, numbers: true, outlineWidth: 1.5)
        options.highlight = 1
        var progress = PaintProgress(regionCount: Self.book.regions.count)
        for r in Self.book.regions.indices where r % 3 == 0 { progress.paint(r) }
        let book = PixelReader(try #require(CanvasSnapshot.render(template: Self.book, progress: progress, size: size, options: options)))
        let layered = PixelReader(try #require(CanvasSnapshot.render(template: Self.layered, progress: progress, size: size, options: options)))
        var differing = 0
        for y in 0..<book.height { for x in 0..<book.width where book[x, y] != layered[x, y] { differing += 1 } }
        #expect(differing == 0)
        for style in [TemplateRasterizer.Style.thumbnail, .template, .finished, .printable] {
            let a = try #require(TemplateRasterizer.pngData(Self.book, painted: progress.painted, style: style, maxPixelSize: 640))
            let b = try #require(TemplateRasterizer.pngData(Self.layered, painted: progress.painted, style: style, maxPixelSize: 640))
            #expect(a == b)
        }
    }

    /// The drawing is drawn in full ink on every drawn layer, color edges not at all; nothing
    /// changes with a selection, and the drawing stays over painted cells.
    @Test func coloringBookDrawsTheDrawingOverEverything() throws {
        let t = Self.book
        let art = try #require(t.lineArt)
        let size = CGSize(width: t.width * 2, height: t.height * 2)
        let options = CanvasSnapshot.Options(outlines: true, numbers: false, outlineWidth: 1.5)
        func render(_ options: CanvasSnapshot.Options, progress: PaintProgress? = nil) throws -> PixelReader {
            PixelReader(try #require(CanvasSnapshot.render(template: t, progress: progress, size: size, options: options)))
        }
        let blank = try render(options)
        record(try #require(CanvasSnapshot.render(template: t, progress: nil, size: size, options: options)), "book-mosaic")
        let darkness = layerDarkness(blank, t, scale: 2)
        let paper = luma(encoded(CanvasPalette.light.paper))
        #expect(darkness[3] < 8, "color edges are not drawn: \(darkness)")
        for layer in 0..<3 {
            #expect(darkness[layer] > Double(paper - 90), "layer \(layer) in full ink: \(darkness)")
            #expect(abs(darkness[layer] - darkness[0]) < 8, "every drawn layer alike: \(darkness)")
        }
        // A selection hatches its cells (the hatch ink is far lighter than the line ink) but
        // outlines nothing: no color edge of a selected cell gets a line.
        let color = 1
        var selecting = options
        selecting.highlight = color
        let selected = try render(selecting)
        record(try #require(CanvasSnapshot.render(template: t, progress: nil, size: size, options: selecting)), "book-mosaic-selected")
        var hatchedEdges = 0
        for (e, edge) in t.edges.enumerated()
        where edge.right != BoundaryEdge.outside && edge.pointCount >= 3 && art.edgeLayers[e] == LineLayer.color.rawValue
            && [edge.left, edge.right].contains(where: { t.regions[Int($0)].colorIndex == UInt32(color) }) {
            let p = t.points[Int(edge.pointStart + edge.pointCount / 2)]
            #expect(darkest(selected, Int(p.x * 2), Int(p.y * 2)) > 100, "edge \(e) of a selected cell is outlined")
            hatchedEdges += 1
        }
        // The mosaic puts every fourth edge in the color layer: four of them bound the selected cells.
        #expect(hatchedEdges >= 3, "\(hatchedEdges) color edges on the selected cells")
        let afterSelection = layerDarkness(selected, t, scale: 2)
        for layer in 0..<3 { #expect(abs(afterSelection[layer] - darkness[layer]) < 8) }
        // Painting everything leaves the drawing, strokes included, where it was.
        var done = PaintProgress(regionCount: t.regions.count)
        for r in t.regions.indices { done.paint(r) }
        let painted = try render(options, progress: done)
        let afterPaint = layerDarkness(painted, t, scale: 2)
        for layer in 0..<3 { #expect(afterPaint[layer] > Double(paper - 90), "layer \(layer) stays over the paint: \(afterPaint)") }
        for stroke in art.strokes {
            let p = art.strokePoints[Int(stroke.pointStart) + 1]
            #expect(luma(painted[Int(p.x * 2), Int(p.y * 2)]) < paper - 60, "stroke in region \(stroke.region) stays")
        }
        // Without outlines asked for (the painting as painted so far), the drawing still shows.
        let picture = try render(.painting, progress: done)
        #expect(layerDarkness(picture, t, scale: 2)[0] > Double(paper - 90))
    }

    @Test func coloringBookPicturesAndPrint() throws {
        // Stripes: separator 1 is an outline, separator 2 a color boundary, a detail stroke runs
        // down the middle of stripe 0.
        var t = Fixtures.stripes(count: 3, stripeWidth: 40, height: 40)
        var layers = Array(repeating: LineLayer.color.rawValue, count: t.edges.count)
        layers[1] = LineLayer.outline.rawValue
        t.lineArt = TemplateLineArt(
            edgeLayers: layers, edgeWeights: Array(repeating: 128, count: t.edges.count),
            strokePoints: [SIMD2(20, 6), SIMD2(20, 34)],
            strokes: [InteriorStroke(pointStart: 0, pointCount: 2, layer: LineLayer.detail.rawValue, weight: 128, region: 0)],
            style: .coloringBook)
        func column(_ style: TemplateRasterizer.Style, _ x: Int, painted: [Bool]? = nil, y: Int = 30 * 4) throws -> Int {
            let image = try #require(TemplateRasterizer.image(t, painted: painted, style: style, maxPixelSize: 480))
            let pixels = PixelReader(image)
            return ((x - 4)...(x + 4)).map { luma(pixels[$0, y]) }.min() ?? 255
        }
        // Every screen style: the outline and the stroke in full ink, the color edge invisible
        // (no darker than the stripes beside it), painted or not; the painted preview (no outlines
        // of its own) and the finished picture too.
        for screen in [TemplateRasterizer.Style.template, .thumbnail, .finished, .painting] {
            let outline = try column(screen, 160), color = try column(screen, 320), stroke = try column(screen, 80)
            #expect(outline < 60 && stroke < 60, "\(screen.outlineWidth): outline \(outline), stroke \(stroke)")
            let beside = min(try column(screen, 296), try column(screen, 344))
            #expect(color >= beside - 2, "no color edge: \(color) vs \(beside)")
            let painted = try column(screen, 160, painted: [true, true, false]), paintedStroke = try column(screen, 80, painted: [true, true, false])
            #expect(painted < 60 && paintedStroke < 60, "the drawing stays over the paint")
        }
        // Heavier with a heavier Line Weight.
        func ink(_ weight: LineWeight) throws -> Int {
            var style = TemplateRasterizer.Style.template
            style.lineWeight = weight
            let pixels = PixelReader(try #require(TemplateRasterizer.image(t, style: style, maxPixelSize: 480)))
            return (140...180).filter { luma(pixels[$0, 120]) < 128 }.count
        }
        #expect(try ink(.bold) > ink(.fine))
        // Print: the drawing in full ink, and dotted guides along the color edge.
        var print = TemplateRasterizer.Style.printable
        print.outlineWidth = 3
        let printed = try #require(TemplateRasterizer.image(t, style: print, maxPixelSize: 480))
        let pixels = PixelReader(printed)
        let outline = (156...164).map { luma(pixels[$0, 120]) }.min() ?? 255
        #expect(outline < 60)
        let guide = (0..<160).map { y in (316...324).map { luma(pixels[$0, y]) }.min() ?? 255 }
        #expect(guide.min()! < 200 && guide.filter { $0 > 240 }.count > 10, "dotted: \(guide.min()!) with \(guide.filter { $0 > 240 }.count) gaps")
        Attachment.record(try #require(ImageCodec.pngData(printed)), named: "book-stripes-print.png")
    }

    @Test func coloringBookPicturesForReview() throws {
        let url = try #require(Bundle.main.url(forResource: "red-fox", withExtension: "jpg"))
        let photo = try PhotoLoader.load(url: url, maxPixelSize: 640)
        let settings = GenerationSettings(colorCount: 18, detail: 0.4)
        let t = try TemplateGenerator(settings: settings)
            .generate(from: photo, lineArt: LineArtInput(edges: SyntheticTemplate.edgeMap(for: photo)), cancel: .none).template
        #expect(t.lineArt?.style == .coloringBook)
        let size = CanvasSnapshot.fittedSize(for: t, longSide: 1600)
        var progress = PaintProgress(regionCount: t.regions.count)
        for r in t.regions.indices where t.regions[r].colorIndex % 2 == 0 { progress.paint(r) }
        var options = CanvasSnapshot.Options.preview
        options.highlight = 1
        record(try #require(CanvasSnapshot.render(template: t, progress: progress, size: size, options: options)), "book-fox-canvas")
        Attachment.record(try #require(TemplateRasterizer.pngData(t, painted: progress.painted, style: .thumbnail, maxPixelSize: 1024)), named: "book-fox-thumbnail.png")
        Attachment.record(try #require(TemplateRasterizer.pngData(t, style: .finished, maxPixelSize: 1600)), named: "book-fox-finished.png")
        let pdf = PDFExporter.document(for: t, title: "Red Fox", paper: .a4)
        Attachment.record(pdf, named: "book-fox.pdf")
    }

    // MARK: Helpers

    /// Mean darkness (paper luma minus the darkest pixel around an edge's middle point) of the
    /// interior edges of each layer.
    private func layerDarkness(_ px: PixelReader, _ t: Template, scale: Float) -> [Double] {
        let paper = luma(encoded(CanvasPalette.light.paper))
        var sums = [Double](repeating: 0, count: 4), counts = [Int](repeating: 0, count: 4)
        for (e, edge) in t.edges.enumerated() where edge.right != BoundaryEdge.outside && edge.pointCount >= 3 {
            let p = t.points[Int(edge.pointStart + edge.pointCount / 2)]
            let layer = Int(t.lineArt!.edgeLayers[e])
            sums[layer] += Double(paper - darkest(px, Int(p.x * scale), Int(p.y * scale)))
            counts[layer] += 1
        }
        return (0..<4).map { sums[$0] / Double(max(counts[$0], 1)) }
    }

    private func darkest(_ px: PixelReader, _ x: Int, _ y: Int) -> Int {
        var best = 255
        for dy in -1...1 { for dx in -1...1 { best = min(best, luma(px[x + dx, y + dy])) } }
        return best
    }
}
