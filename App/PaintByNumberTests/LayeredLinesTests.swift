import CoreGraphics
import Foundation
import PaintCore
import Testing
import UIKit
@testable import PaintByNumber

/// Layered line art: the appearance's interpolation, the styles renderers derive from it, the
/// outline geometry the canvas uploads, and how the canvas, offscreen renders and the
/// CoreGraphics rasterizer draw layers, interior strokes, painted and selected cells. Classic
/// templates must draw exactly as before.
struct LayeredLinesTests {
    /// The canvas tests' mosaic with every edge's layer set by its index (border edges too) and
    /// one outline-layer stroke inside each cell that has room: layers are known per edge.
    static let mosaic: Template = {
        let t = CanvasRenderTests.template
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
        var layered = t
        layered.lineArt = TemplateLineArt(edgeLayers: layers, edgeWeights: weights, strokePoints: points, strokes: strokes)
        return layered
    }()

    /// Full ink at width 1 in every layer: pictures draw their classic line at full ink, so with
    /// this appearance their layered lines are exactly the classic ones.
    static let neutral: LineAppearance = {
        let layer = LineAppearance.Layer(opacity: [1, 1, 1], width: [1, 1, 1])
        return LineAppearance(outline: layer, detail: layer, texture: layer, color: layer, weighted: false)
    }()

    // MARK: Appearance and style

    @Test func appearanceInterpolatesOnLogZoomAndHoldsBeyondItsKeys() {
        let values: [Float] = [0.2, 0.5, 0.8]
        #expect(LineAppearance.interpolate(values, zoom: 1) == 0.2)
        #expect(LineAppearance.interpolate(values, zoom: 2) == 0.5)
        #expect(LineAppearance.interpolate(values, zoom: 4) == 0.8)
        #expect(abs(LineAppearance.interpolate(values, zoom: Float(2).squareRoot()) - 0.35) < 1e-5)
        #expect(abs(LineAppearance.interpolate(values, zoom: Float(8).squareRoot()) - 0.65) < 1e-5)
        #expect(LineAppearance.interpolate(values, zoom: 0.5) == 0.2)
        #expect(LineAppearance.interpolate(values, zoom: 16) == 0.8)
        let texture = LineAppearance.default.texture
        #expect(texture.opacity(atZoom: 1) == texture.opacity[0] && texture.width(atZoom: 4) == texture.width[2])
    }

    @Test func styleIsTheAppearanceRelativeToTheClassicLine() {
        let appearance = LineAppearance.default
        for zoom: Float in [0.8, 1, 1.5, 2, 3, 4, 6] {
            // The canvas's classic line is lighter zoomed out; pictures draw it at full ink.
            let strength = LineStyle.classicStrength(depth: log2(max(zoom, 1)))
            let canvas = LineStyle(appearance, zoom: zoom, classicStrength: strength)
            let picture = LineStyle(appearance, zoom: zoom)
            for layer in LineLayer.allCases {
                let i = Int(layer.rawValue), opacity = appearance[layer].opacity(atZoom: zoom)
                #expect(abs(canvas.opacity[i] * strength - opacity) < 1e-5, "\(layer) at \(zoom)")
                #expect(picture.opacity[i] == opacity)
                #expect(canvas.width[i] == appearance[layer].width(atZoom: zoom) && picture.width[i] == canvas.width[i])
            }
            #expect(canvas.weighted == appearance.weighted)
        }
        #expect(LineStyle.classicStrength(depth: 0) == 0.7 && abs(LineStyle.classicStrength(depth: 2) - 1) < 1e-6)
        #expect(LineStyle.classic.opacity == SIMD4(repeating: 1) && LineStyle.classic.width == SIMD4(repeating: 1))
        #expect(LineStyle(Self.neutral, zoom: 1) == .classic && LineStyle(Self.neutral, zoom: 4) == .classic)
        // Fainter layers are fainter and finer by default, and come in as the painter zooms.
        let fitted = LineStyle(appearance, zoom: 1), deep = LineStyle(appearance, zoom: 4)
        for i in 1..<4 {
            #expect(fitted.opacity[i] < fitted.opacity[i - 1] && fitted.width[i] <= fitted.width[i - 1])
            #expect(deep.opacity[i] > fitted.opacity[i] * 1.5)
        }
        // Print: every layer clearly visible, outlines heaviest.
        #expect(LineStyle.print.opacity.min() >= 0.5 && LineStyle.print.width.max() == LineStyle.print.width[0])
    }

    @Test func storedAppearanceRoundTripsAndFallsBackToTheDefault() throws {
        let suite = "PBNTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(LineAppearance.stored(in: defaults) == .default)
        var custom = LineAppearance.default
        custom.texture.opacity = [0.4, 0.6, 1]
        custom.weighted = true
        try defaults.set(JSONEncoder().encode(custom), forKey: SettingsKey.lineAppearance)
        #expect(LineAppearance.stored(in: defaults) == custom)
        defaults.set(Data("not json".utf8), forKey: SettingsKey.lineAppearance)
        #expect(LineAppearance.stored(in: defaults) == .default)
        #expect(LineAppearance.decoded(nil) == .default)
    }

    // MARK: Line data and geometry

    @Test func weightsFollowStrengthWithinEachLayer() {
        let layers: [UInt8] = [0, 0, 0, 1, 1, 2, 3, 3]
        let strengths: [UInt8] = [100, 200, 255, 10, 30, 90, 0, 0]
        let w = DrawableLineArt.weights(layers: layers, strengths: strengths)
        // Layer 0's mean is 185: 100 → 0.6 (clamped from 0.54), 200 → 1.08, 255 → 1.38.
        #expect(w[0] == 0.6 && abs(w[1] - 200 / 185) < 1e-5 && abs(w[2] - 255 / 185) < 1e-5)
        #expect(w[3] == 0.6 && w[4] == 1.4)         // mean 20: 0.5 and 1.5, clamped
        #expect(w[5] == 1)                          // a layer's only line has its mean
        #expect(w[6] == 1 && w[7] == 1)             // all-zero strengths draw evenly
    }

    @Test func classicGeometryIsTheEdgesAsEver() {
        let t = CanvasRenderTests.template
        let g = OutlineGeometry(t)
        #expect(!g.isLayered && g.points == t.points)
        var segments: [SIMD2<UInt32>] = []
        for (e, edge) in t.edges.enumerated() where edge.pointCount >= 2 {
            for k in 0..<(edge.pointCount - 1) { segments.append(SIMD2(edge.pointStart + k, UInt32(e))) }
        }
        #expect(g.segments == segments)
        #expect(g.lineRegions == t.edges.map { SIMD2($0.left, $0.right) })
        #expect(g.lineStyles == Array(repeating: SIMD2(0, 1), count: t.edges.count))
    }

    @Test func layeredGeometryAddsStrokesAsLinesInsideTheirCell() throws {
        let t = Self.mosaic
        let art = try #require(t.lineArt)
        let g = OutlineGeometry(t)
        #expect(g.isLayered)
        #expect(g.points == t.points + art.strokePoints)
        #expect(g.lineRegions.count == t.edges.count + art.strokes.count)
        let weights = DrawableLineArt.weights(
            layers: art.edgeLayers + art.strokes.map(\.layer), strengths: art.edgeWeights + art.strokes.map(\.weight))
        for (e, edge) in t.edges.enumerated() {
            #expect(g.lineRegions[e] == SIMD2(edge.left, edge.right))
            #expect(g.lineStyles[e] == SIMD2(Float(art.edgeLayers[e]), weights[e]))
        }
        for (s, stroke) in art.strokes.enumerated() {
            let line = t.edges.count + s
            #expect(g.lineRegions[line] == SIMD2(stroke.region, stroke.region))
            #expect(g.lineStyles[line].x == Float(stroke.layer))
            let segments = g.segments.filter { $0.y == UInt32(line) }
            #expect(segments.map(\.x) == (0..<(stroke.pointCount - 1)).map { UInt32(t.points.count) + stroke.pointStart + $0 })
        }
        let classicSegments = OutlineGeometry(CanvasRenderTests.template).segments
        #expect(Array(g.segments.prefix(classicSegments.count)) == classicSegments)
    }

    @Test func malformedLineArtIsSkippedNotTrusted() {
        var t = Self.mosaic
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
        #expect(DrawableLineArt(t) == nil && !OutlineGeometry(t).isLayered)
    }

    // MARK: Uniforms

    @Test func classicUniformsGiveEveryLayerTheClassicLine() throws {
        var u = CanvasUniforms()
        u.ink.w = 0.434
        u.outline = SIMD4(1.25, 2.4, 1, 1)
        u.setLines(.classic)
        #expect(u.lineAlpha == SIMD4(repeating: 0.434) && u.lineWidth == SIMD4(repeating: 1.25) && u.lineMode == .zero)

        let context = try #require(RenderContext.shared)
        let classic = try #require(CanvasScene(template: CanvasRenderTests.template, context: context))
        #expect(!classic.isLayered)
        let c = CanvasSnapshot.uniforms(scene: classic, width: 240, height: 320, options: .preview)
        #expect(c.lineAlpha == SIMD4(repeating: c.ink.w) && c.lineWidth == SIMD4(repeating: c.outline.x))

        let layered = try #require(CanvasScene(template: Self.mosaic, context: context))
        #expect(layered.isLayered && layered.segmentCount > classic.segmentCount)
        var options = CanvasSnapshot.Options.preview
        options.lineAppearance = .default
        options.lineZoom = 2
        let l = CanvasSnapshot.uniforms(scene: layered, width: 240, height: 320, options: options)
        let style = LineStyle(.default, zoom: 2)
        #expect(l.lineAlpha == l.ink.w * style.opacity && l.lineWidth == l.outline.x * style.width)
    }

    // MARK: Canvas rendering (Metal)

    /// With an appearance that matches the classic line, a layered template's lines (in every
    /// layer, weights ignored) give exactly the classic frame, selection included.
    @Test func neutralAppearanceRendersExactlyLikeClassic() throws {
        var lineless = Self.mosaic.lineArt!
        lineless.strokes = []
        lineless.strokePoints = []
        var layered = CanvasRenderTests.template
        layered.lineArt = lineless
        let size = CGSize(width: 960, height: 1280)
        var options = CanvasSnapshot.Options(outlines: true, numbers: true)
        options.lineAppearance = Self.neutral
        options.highlight = 3
        var progress = PaintProgress(regionCount: layered.regions.count)
        for r in layered.regions.indices where r % 3 == 0 { progress.paint(r) }
        let classicImage = try #require(CanvasSnapshot.render(template: CanvasRenderTests.template, progress: progress, size: size, options: options))
        let layeredImage = try #require(CanvasSnapshot.render(template: layered, progress: progress, size: size, options: options))
        let a = Pixels(classicImage), b = Pixels(layeredImage)
        var differing = 0
        for y in 0..<a.height { for x in 0..<a.width where a[x, y] != b[x, y] { differing += 1 } }
        #expect(differing == 0)
    }

    @Test func layersFadeByOpacityAndComeInWhenZoomed() throws {
        let t = Self.mosaic
        func darkness(zoom: Float) throws -> [Double] {
            var options = CanvasSnapshot.Options(outlines: true, numbers: false, outlineWidth: 1.5)
            options.lineAppearance = .default
            options.lineZoom = zoom
            let image = try #require(CanvasSnapshot.render(template: t, progress: nil, size: CGSize(width: t.width * 2, height: t.height * 2), options: options))
            record(image, "layered-mosaic-z\(Int(zoom))")
            return layerDarkness(Pixels(image), t, scale: 2)
        }
        let fitted = try darkness(zoom: 1), deep = try darkness(zoom: 4)
        for i in 1..<4 {
            #expect(fitted[i] < fitted[i - 1] * 0.8, "layer \(i) at 1×: \(fitted)")
            #expect(fitted[i] > 2, "layer \(i) still shows at 1×: \(fitted)")
            #expect(deep[i] > fitted[i] * 1.5, "layer \(i) comes in at 4×: \(fitted) → \(deep)")
        }
    }

    @Test func strokesDrawInsideTheirCellAndDissolveWithIt() throws {
        let t = Self.mosaic
        let art = try #require(t.lineArt)
        var options = CanvasSnapshot.Options(outlines: true, numbers: false, outlineWidth: 1.5)
        options.lineAppearance = .default
        let size = CGSize(width: t.width * 2, height: t.height * 2)
        let blank = Pixels(try #require(CanvasSnapshot.render(template: t, progress: nil, size: size, options: options)))
        var done = PaintProgress(regionCount: t.regions.count)
        for r in t.regions.indices { done.paint(r) }
        let painted = Pixels(try #require(CanvasSnapshot.render(template: t, progress: done, size: size, options: options)))
        let paper = luma(encoded(CanvasPalette.light.paper))
        #expect(art.strokes.count > 10)
        for stroke in art.strokes {
            let p = art.strokePoints[Int(stroke.pointStart) + 1]
            let x = Int(p.x * 2), y = Int(p.y * 2)
            #expect(luma(blank[x, y]) < paper - 40, "stroke in region \(stroke.region) should be inked")
            let paint = bytes(t.palette[Int(t.regions[Int(stroke.region)].colorIndex)].rgb)
            #expect(maxDifference(painted[x, y], paint) <= 3, "stroke in region \(stroke.region) should dissolve with its cell")
        }
    }

    /// The selected color's unpainted cells are outlined boldly even where their boundary is
    /// the faintest layer.
    @Test func selectedCellsAreOutlinedWhateverTheLayer() throws {
        var t = CanvasRenderTests.template
        t.lineArt = TemplateLineArt(
            edgeLayers: Array(repeating: LineLayer.color.rawValue, count: t.edges.count),
            edgeWeights: Array(repeating: 100, count: t.edges.count))
        let color = 1
        var options = CanvasSnapshot.Options(outlines: true, numbers: false, outlineWidth: 1.5)
        options.lineAppearance = .default
        options.highlight = color
        let image = try #require(CanvasSnapshot.render(template: t, progress: nil, size: CGSize(width: t.width * 2, height: t.height * 2), options: options))
        record(image, "layered-selected")
        let px = Pixels(image)
        let paper = luma(encoded(CanvasPalette.light.paper))
        var bounding: [Double] = [], other: [Double] = []
        for edge in t.edges where edge.right != BoundaryEdge.outside && edge.pointCount >= 3 {
            let p = t.points[Int(edge.pointStart + edge.pointCount / 2)]
            let dark = Double(paper - darkest(px, Int(p.x * 2), Int(p.y * 2)))
            let selected = [edge.left, edge.right].contains { t.regions[Int($0)].colorIndex == UInt32(color) }
            if selected { bounding.append(dark) } else { other.append(dark) }
        }
        #expect(!bounding.isEmpty && !other.isEmpty)
        let mean = { (v: [Double]) in v.reduce(0, +) / Double(max(v.count, 1)) }
        #expect(mean(bounding) > 3 * mean(other), "selected \(mean(bounding)) vs other \(mean(other))")
    }

    @MainActor
    @Test func canvasFollowsTheAppearanceAndTheZoom() throws {
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 700)
        window.overrideUserInterfaceStyle = .light
        window.isHidden = false
        defer { window.isHidden = true }
        func canvas(_ t: Template, zoom: CGFloat? = nil) -> CanvasView {
            let view = CanvasView(session: PaintingSession(template: t))
            if let zoom { view.initialCamera = CanvasCamera(zoom: zoom, center: SIMD2(Float(t.width), Float(t.height)) / 2) }
            window.addSubview(view)
            view.frame = window.bounds
            view.layoutIfNeeded()
            return view
        }
        let full = CanvasPalette.light.outlineOpacity
        let fitted = canvas(Self.mosaic)
        defer { fitted.removeFromSuperview() }
        var u = fitted.frameUniforms()
        for layer in LineLayer.allCases {
            let i = Int(layer.rawValue)
            #expect(abs(u.lineAlpha[i] - full * LineAppearance.default[layer].opacity[0]) < 1e-4, "\(layer)")
        }
        // A new appearance reaches the next frame.
        var faint = LineAppearance.default
        faint.outline.opacity = [0.1, 0.1, 0.1]
        faint.weighted = true
        fitted.lineAppearance = faint
        u = fitted.frameUniforms()
        #expect(abs(u.lineAlpha.x - full * 0.1) < 1e-4 && u.lineMode.x == 1)

        let deep = canvas(Self.mosaic, zoom: 4)
        defer { deep.removeFromSuperview() }
        let d = deep.frameUniforms()
        #expect(abs(d.lineAlpha.z - full * LineAppearance.default.texture.opacity[2]) < 1e-3)
        #expect(abs(d.lineWidth.z - d.outline.x * LineAppearance.default.texture.width[2]) < 1e-3)

        // Classic templates ignore it.
        let classic = canvas(CanvasRenderTests.template)
        defer { classic.removeFromSuperview() }
        classic.lineAppearance = faint
        let c = classic.frameUniforms()
        #expect(c.lineAlpha == SIMD4(repeating: c.ink.w) && c.lineMode.x == 0)
    }

    // MARK: Pictures and print (CoreGraphics)

    /// Classic pictures are untouched, and a layered template whose lines are all one layer at
    /// the neutral appearance draws exactly the classic picture.
    @Test func rasterizerDrawsNeutralLayersExactlyLikeClassic() throws {
        let t = CanvasRenderTests.template
        var layered = t
        layered.lineArt = TemplateLineArt(
            edgeLayers: Array(repeating: LineLayer.detail.rawValue, count: t.edges.count),
            edgeWeights: Array(repeating: 90, count: t.edges.count))
        var progress = PaintProgress(regionCount: t.regions.count)
        for r in t.regions.indices where r % 2 == 0 { progress.paint(r) }
        for var style in [TemplateRasterizer.Style.thumbnail, .template, .finished] {
            style.lines = .screen(Self.neutral, zoom: 1)
            let a = try #require(TemplateRasterizer.pngData(t, painted: progress.painted, style: style, maxPixelSize: 640))
            let b = try #require(TemplateRasterizer.pngData(layered, painted: progress.painted, style: style, maxPixelSize: 640))
            #expect(a == b)
        }
    }

    @Test func picturesFadeLayersAndPrintShowsThemAll() throws {
        // Stripes: separator 1 is an outline, separator 2 a color boundary, a detail stroke runs
        // down the middle of stripe 0.
        var t = Fixtures.stripes(count: 3, stripeWidth: 40, height: 40)
        var layers = Array(repeating: LineLayer.color.rawValue, count: t.edges.count)
        layers[1] = LineLayer.outline.rawValue
        t.lineArt = TemplateLineArt(
            edgeLayers: layers, edgeWeights: Array(repeating: 128, count: t.edges.count),
            strokePoints: [SIMD2(20, 6), SIMD2(20, 34)],
            strokes: [InteriorStroke(pointStart: 0, pointCount: 2, layer: LineLayer.detail.rawValue, weight: 128, region: 0)])
        func column(_ style: TemplateRasterizer.Style, _ x: Int) throws -> Int {
            let image = try #require(TemplateRasterizer.image(t, style: style, maxPixelSize: 480))
            let pixels = PixelReader(image)
            return ((x - 3)...(x + 3)).map { luma(pixels[$0, 30 * 4]) }.min() ?? 255
        }
        var screen = TemplateRasterizer.Style.template
        screen.outlineWidth = 4
        screen.lines = .screen(.default, zoom: 1)
        let outline = try column(screen, 160), color = try column(screen, 320), stroke = try column(screen, 80)
        #expect(outline < color - 60, "outline \(outline) vs color line \(color)")
        #expect(color < 250, "the color line still shows: \(color)")
        #expect(stroke < color && stroke > outline, "the detail stroke sits between: \(stroke)")
        // Painted: the stroke goes with its cell.
        let painted = PixelReader(try #require(TemplateRasterizer.image(t, painted: [true, false, false], style: screen, maxPixelSize: 480)))
        for x in 77...83 { #expect(painted[x, 120] == SIMD3(255, 0, 0)) }

        var print = TemplateRasterizer.Style.printable
        print.outlineWidth = 4
        #expect(print.lines == .print)
        let printedColor = try column(print, 320), printedOutline = try column(print, 160)
        #expect(printedColor < 200, "every layer prints: \(printedColor)")
        #expect(printedOutline < printedColor)
    }

    /// Pictures of a layered painting, for the eye: canvas renders at the 1×, 2× and 4× looks,
    /// the gallery thumbnail, the share picture and the printed template.
    @Test func layeredPicturesForReview() throws {
        let url = try #require(Bundle.main.url(forResource: "parrots", withExtension: "jpg"))
        let photo = try PhotoLoader.load(url: url, maxPixelSize: 640)
        var settings = GenerationSettings(colorCount: 18, detail: 0.4)
        settings.lineArt.style = .layered
        let t = try TemplateGenerator(settings: settings)
            .generate(from: photo, lineArt: LineArtInput(edges: SyntheticTemplate.edgeMap(for: photo)), cancel: .none).template
        let art = try #require(t.lineArt)
        // The pipeline's line data is what the renderers draw, all of it.
        let lines = try #require(DrawableLineArt(t))
        #expect(lines.strokes.count == art.strokes.count && lines.edgeLayers == art.edgeLayers)
        #expect(Set(art.edgeLayers).count > 2)
        let size = CanvasSnapshot.fittedSize(for: t, longSide: 1600)
        for zoom: Float in [1, 2, 4] {
            var options = CanvasSnapshot.Options.preview
            options.lineAppearance = .default
            options.lineZoom = zoom
            let image = try #require(CanvasSnapshot.render(template: t, progress: nil, size: size, options: options))
            record(image, "layered-parrots-canvas-z\(Int(zoom))")
        }
        var progress = PaintProgress(regionCount: t.regions.count)
        for r in t.regions.indices where t.regions[r].colorIndex % 2 == 0 { progress.paint(r) }
        var thumbnail = TemplateRasterizer.Style.thumbnail
        thumbnail.lines = .screen(.default, zoom: 1)
        let png = try #require(TemplateRasterizer.pngData(t, painted: progress.painted, style: thumbnail, maxPixelSize: 1024))
        Attachment.record(png, named: "layered-parrots-thumbnail.png")
        var template = TemplateRasterizer.Style.template
        template.lines = .screen(.default, zoom: 1)
        let preview = try #require(TemplateRasterizer.pngData(t, style: template, maxPixelSize: 1600))
        Attachment.record(preview, named: "layered-parrots-template.png")
        let pdf = PDFExporter.document(for: t, title: "Parrots", paper: .a4)
        Attachment.record(pdf, named: "layered-parrots.pdf")
        let document = try #require(CGDataProvider(data: pdf as CFData).flatMap { CGPDFDocument($0) })
        let page = try #require(document.page(at: 1))
        let box = page.getBoxRect(.mediaBox)
        let ctx = try #require(CGContext(
            data: nil, width: Int(box.width * 3), height: Int(box.height * 3), bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: box.width * 3, height: box.height * 3))
        ctx.scaleBy(x: 3, y: 3)
        ctx.drawPDFPage(page)
        record(try #require(ctx.makeImage()), "layered-parrots-pdf-page1")
    }

    // MARK: Coloring book

    /// The mosaic as a coloring book: the same lines, drawn as a drawing.
    static let book: Template = {
        var t = mosaic
        t.lineArt!.style = .coloringBook
        return t
    }()

    @Test func coloringBookAppearanceAndUniforms() throws {
        // The weight is tolerant: missing or out of range falls back to 1.
        var heavy = LineAppearance.default
        heavy.coloringBookWeight = 1.5
        let data = try JSONEncoder().encode(heavy)
        #expect(LineAppearance.decoded(data) == heavy && heavy != .default)
        #expect(LineAppearance.decoded(Data(#"{"coloringBookWeight": 9}"#.utf8)).coloringBookWeight == 1)
        #expect(LineAppearance.decoded(Data("{}".utf8)) == .default)
        // The canvas's book line: three times the classic line fitted, growing slower than the zoom.
        #expect(ColoringBookLook.widthPoints(depth: 0, weight: 1) == 3 * LineStyle.classicWidthPoints(depth: 0))
        #expect(ColoringBookLook.widthPoints(depth: 2, weight: 1) < 4 * ColoringBookLook.widthPoints(depth: 0, weight: 1))
        #expect(ColoringBookLook.widthPoints(depth: 1, weight: 2) == 2 * ColoringBookLook.widthPoints(depth: 1, weight: 1))
        // Uniforms: full ink on every drawn layer, none on color edges, one width, the book mode.
        var u = CanvasUniforms()
        u.ink.w = 0.5
        u.setColoringBookLines(width: 4)
        #expect(u.lineAlpha == SIMD4(1, 1, 1, 0) && u.lineWidth == SIMD4(4, 4, 4, 0) && u.lineMode == SIMD4(0, 1, 0, 0))
        let context = try #require(RenderContext.shared)
        let scene = try #require(CanvasScene(template: Self.book, context: context))
        #expect(scene.isLayered && scene.lineArtStyle == .coloringBook)
        #expect(try #require(CanvasScene(template: Self.mosaic, context: context)).lineArtStyle == .layered)
        #expect(try #require(CanvasScene(template: CanvasRenderTests.template, context: context)).lineArtStyle == nil)
        var options = CanvasSnapshot.Options.preview
        options.lineAppearance = heavy
        let s = CanvasSnapshot.uniforms(scene: scene, width: 240, height: 320, options: options)
        #expect(s.lineMode.y == 1 && s.lineAlpha == SIMD4(1, 1, 1, 0))
        #expect(abs(s.lineWidth.x - s.outline.x * ColoringBookLook.widthFactor * 1.5) < 1e-4)
    }

    /// The drawing is drawn in full ink on every drawn layer, color edges not at all; nothing
    /// changes with a selection, and the drawing stays over painted cells.
    @Test func coloringBookDrawsTheDrawingOverEverything() throws {
        let t = Self.book
        let art = try #require(t.lineArt)
        let size = CGSize(width: t.width * 2, height: t.height * 2)
        var options = CanvasSnapshot.Options(outlines: true, numbers: false, outlineWidth: 1.5)
        options.lineAppearance = .default
        func render(_ options: CanvasSnapshot.Options, progress: PaintProgress? = nil) throws -> Pixels {
            Pixels(try #require(CanvasSnapshot.render(template: t, progress: progress, size: size, options: options)))
        }
        let blank = try render(options)
        record(try #require(CanvasSnapshot.render(template: t, progress: nil, size: size, options: options)), "book-mosaic")
        let darkness = layerDarkness(blank, t, scale: 2)
        let paper = luma(encoded(CanvasPalette.light.paper))
        #expect(darkness[3] < 8, "color edges are not drawn: \(darkness)")
        for layer in 0..<3 {
            #expect(darkness[layer] > paper - 90, "layer \(layer) in full ink: \(darkness)")
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
        #expect(hatchedEdges > 5)
        let afterSelection = layerDarkness(selected, t, scale: 2)
        for layer in 0..<3 { #expect(abs(afterSelection[layer] - darkness[layer]) < 8) }
        // Painting everything leaves the drawing, strokes included, where it was.
        var done = PaintProgress(regionCount: t.regions.count)
        for r in t.regions.indices { done.paint(r) }
        let painted = try render(options, progress: done)
        let afterPaint = layerDarkness(painted, t, scale: 2)
        for layer in 0..<3 { #expect(afterPaint[layer] > paper - 90, "layer \(layer) stays over the paint: \(afterPaint)") }
        for stroke in art.strokes {
            let p = art.strokePoints[Int(stroke.pointStart) + 1]
            #expect(luma(painted[Int(p.x * 2), Int(p.y * 2)]) < paper - 60, "stroke in region \(stroke.region) stays")
        }
        // Without outlines asked for (the painting as painted so far), the drawing still shows.
        var painting = CanvasSnapshot.Options.painting
        painting.lineAppearance = .default
        let picture = try render(painting, progress: done)
        #expect(layerDarkness(picture, t, scale: 2)[0] > paper - 90)
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
        // (no darker than the stripes beside it), painted or not; the painted preview (no lines)
        // and the finished picture too.
        for style in [TemplateRasterizer.Style.template, .thumbnail, .finished, .painting] {
            var screen = style
            screen.lines = .screen(.default, zoom: 1)
            let outline = try column(screen, 160), color = try column(screen, 320), stroke = try column(screen, 80)
            #expect(outline < 60 && stroke < 60, "\(style.outlineWidth): outline \(outline), stroke \(stroke)")
            let beside = min(try column(screen, 296), try column(screen, 344))
            #expect(color >= beside - 2, "no color edge: \(color) vs \(beside)")
            let painted = try column(screen, 160, painted: [true, true, false]), paintedStroke = try column(screen, 80, painted: [true, true, false])
            #expect(painted < 60 && paintedStroke < 60, "the drawing stays over the paint")
        }
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
        var settings = GenerationSettings(colorCount: 18, detail: 0.4)
        settings.lineArt.style = .coloringBook
        let t = try TemplateGenerator(settings: settings)
            .generate(from: photo, lineArt: LineArtInput(edges: SyntheticTemplate.edgeMap(for: photo)), cancel: .none).template
        #expect(t.lineArt?.style == .coloringBook)
        let size = CanvasSnapshot.fittedSize(for: t, longSide: 1600)
        var progress = PaintProgress(regionCount: t.regions.count)
        for r in t.regions.indices where t.regions[r].colorIndex % 2 == 0 { progress.paint(r) }
        var options = CanvasSnapshot.Options.preview
        options.lineAppearance = .default
        options.highlight = 1
        record(try #require(CanvasSnapshot.render(template: t, progress: progress, size: size, options: options)), "book-fox-canvas")
        var thumbnail = TemplateRasterizer.Style.thumbnail
        thumbnail.lines = .screen(.default, zoom: 1)
        Attachment.record(try #require(TemplateRasterizer.pngData(t, painted: progress.painted, style: thumbnail, maxPixelSize: 1024)), named: "book-fox-thumbnail.png")
        var finished = TemplateRasterizer.Style.finished
        finished.lines = .screen(.default, zoom: 1)
        Attachment.record(try #require(TemplateRasterizer.pngData(t, style: finished, maxPixelSize: 1600)), named: "book-fox-finished.png")
        let pdf = PDFExporter.document(for: t, title: "Red Fox", paper: .a4)
        Attachment.record(pdf, named: "book-fox.pdf")
    }

    // MARK: Helpers

    /// Mean darkness (paper luma minus the darkest pixel around an edge's middle point) of the
    /// interior edges of each layer.
    private func layerDarkness(_ px: Pixels, _ t: Template, scale: Float) -> [Double] {
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

    private func darkest(_ px: Pixels, _ x: Int, _ y: Int) -> Int {
        var best = 255
        for dy in -1...1 { for dx in -1...1 { best = min(best, luma(px[x + dx, y + dy])) } }
        return best
    }

    private func record(_ image: CGImage, _ name: String) {
        if let png = ImageCodec.pngData(image) { Attachment.record(png, named: "\(name).png") }
    }
}
