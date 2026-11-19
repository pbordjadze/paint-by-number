import CoreGraphics
import Foundation
import PaintCore
import Testing
import UIKit
@testable import PaintByNumber

/// A finished coloring book shown as paint alone, without its drawing's ink (More › Show Lines
/// off, in SideStore and Debug builds; painting-company row 295): the lines go and the writing
/// stays, on the canvas and in pictures; the painting keeps the choice; an unfinished painting
/// has its lines whatever the choice.
@MainActor
struct FinishedWithoutLinesTests {
    private static func everyAreaPainted(_ t: Template) -> PaintProgress {
        var progress = PaintProgress(regionCount: t.regions.count)
        for r in t.regions.indices { progress.paint(r) }
        return progress
    }

    /// A stroke of the drawing (not writing) over the lightest paint that has one: where ink
    /// and paint are furthest apart.
    private static func inkProbe(_ t: Template) throws -> Int {
        let art = try #require(t.lineArt)
        func lightness(_ s: Int) -> Float { t.palette[Int(t.regions[Int(art.strokes[s].region)].colorIndex)].oklab.x }
        return try #require(art.strokes.indices.filter { !art.isWritingStroke($0) }.max { lightness($0) < lightness($1) })
    }

    // MARK: The canvas's lines

    /// Asked to, the outline geometry marks writing over a light paint too, so the shader can
    /// keep it when the ink goes; unasked (Paint by Mosaic's canvas), it is as it was.
    @Test func writingIsMarkedForACanvasThatCanHideItsInk() throws {
        let (t, dark, light, _) = try LineArtRenderingTests.writing()
        let art = try #require(t.lineArt)
        let marked = OutlineGeometry(t, marksWriting: true)
        for (s, stroke) in art.strokes.enumerated() {
            let mark = s == dark ? OutlineGeometry.lightWritingMark : s == light ? OutlineGeometry.writingMark : 0
            #expect(marked.lineLayers[t.edges.count + s] == Float(stroke.layer) + mark, "stroke \(s)")
        }
        let plain = OutlineGeometry(t)
        #expect(plain.lineLayers[t.edges.count + light] == Float(art.strokes[light].layer))
        #expect(plain.segments == marked.segments && plain.lineRegions == marked.lineRegions)
        // Edges carry no mark either way.
        #expect(Array(marked.lineLayers.prefix(t.edges.count)) == Array(plain.lineLayers.prefix(t.edges.count)))
    }

    /// A frame says how far the ink has gone, to a coloring book's shader alone.
    @Test func aFrameCarriesTheHiddenInk() throws {
        let context = try #require(RenderContext.shared)
        let book = try #require(CanvasScene(template: LineArtRenderingTests.book, context: context))
        var options = CanvasSnapshot.Options.painting
        #expect(CanvasSnapshot.uniforms(scene: book, width: 100, height: 100, options: options).lineMode == SIMD4(1, 0, 0, 0))
        options.withoutInk = true
        #expect(CanvasSnapshot.uniforms(scene: book, width: 100, height: 100, options: options).lineMode == SIMD4(1, 1, 0, 0))
        let classic = try #require(CanvasScene(template: Fixtures.mosaic, context: context))
        #expect(CanvasSnapshot.uniforms(scene: classic, width: 100, height: 100, options: options).lineMode == .zero)
        var u = CanvasUniforms()
        u.setColoringBookLines(width: 3, inkHidden: 7)
        #expect(u.lineMode.y == 1)
    }

    /// The finished picture without its ink, as the canvas shaders draw it: where the drawing
    /// was, the paint under it; the writing still there, in the ink over a light paint and in
    /// the paper's tone over a dark one.
    @Test func theCanvasDrawsTheFinishedPictureWithoutItsInk() throws {
        let (t, dark, light, drawing) = try LineArtRenderingTests.writing()
        let art = try #require(t.lineArt)
        let size = CGSize(width: t.width * 2, height: t.height * 2)
        let done = Self.everyAreaPainted(t)
        func render(_ options: CanvasSnapshot.Options, _ name: String) throws -> PixelReader {
            let image = try #require(CanvasSnapshot.render(template: t, progress: done, size: size, options: options))
            record(image, name)
            return PixelReader(image)
        }
        func at(_ stroke: Int, _ px: PixelReader) -> Int {
            let p = LineArtRenderingTests.middle(of: stroke, in: t)
            return luma(px[Int(p.x * 2), Int(p.y * 2)])
        }
        /// The paint of the stroke's region, as the canvas shows it.
        func paint(_ stroke: Int) -> Int {
            let color = t.palette[Int(t.regions[Int(art.strokes[stroke].region)].colorIndex)]
            return luma(encoded(CanvasColor.linearP3(color, space: t.colorSpace)))
        }
        var options = CanvasSnapshot.Options.painting
        let inked = try render(options, "finished-with-lines")
        options.withoutInk = true
        let bare = try render(options, "finished-without-lines")
        let paper = luma(encoded(CanvasPalette.light.paper))
        // With its lines, the drawing is ink over the paint.
        #expect(at(drawing, inked) < paint(drawing) - 15 || paint(drawing) < 45, "the drawing is drawn: \(at(drawing, inked))")
        // Without: the paint where the drawing was, on strokes and on drawn edges alike.
        #expect(abs(at(drawing, bare) - paint(drawing)) <= 3, "the drawing's ink is gone: \(at(drawing, bare)) on \(paint(drawing))")
        for s in art.strokes.indices where s != dark && s != light {
            #expect(abs(at(s, bare) - paint(s)) <= 3, "stroke \(s)")
        }
        var edges = 0
        for (e, edge) in t.edges.enumerated()
        where edge.right != BoundaryEdge.outside && edge.pointCount >= 3 && LineLayer.isDrawn(art.edgeLayers[e]) {
            let p = t.points[Int(edge.pointStart + edge.pointCount / 2)]
            let here = luma(bare[Int(p.x * 2), Int(p.y * 2)])
            let sides = [edge.left, edge.right].map { side in
                luma(encoded(CanvasColor.linearP3(t.palette[Int(t.regions[Int(side)].colorIndex)], space: t.colorSpace)))
            }
            // The paint of one side or the other, or between them where they meet in the pixel:
            // no ink, and no paper showing through a seam.
            #expect(here >= sides.min()! - 3 && here <= sides.max()! + 3, "edge \(e): \(here) between \(sides)")
            edges += 1
        }
        #expect(edges > 0)
        // The writing stays.
        #expect(at(light, bare) < paper - 60, "writing over a light paint stays ink: \(at(light, bare))")
        #expect(at(dark, bare) > paper - 25, "writing over a dark paint stays in the paper's tone: \(at(dark, bare))")
        #expect(at(light, bare) == at(light, inked) && at(dark, bare) == at(dark, inked))
    }

    /// The live canvas: only a finished painting loses its ink, an undo brings it back, a replay
    /// shows it and its Stop takes it away again. Off screen and under Reduce Motion it cuts.
    @Test func theCanvasHidesItsLinesOnlyWhileThePaintingIsFinished() throws {
        let t = LineArtRenderingTests.book
        let session = PaintingSession(template: t)
        let view = CanvasView(session: session)
        view.reduceMotion = true
        view.frame = CGRect(x: 0, y: 0, width: 400, height: 800)
        view.layoutIfNeeded()
        view.hidesLines = true
        #expect(view.inkHidden == 0 && view.frameUniforms().lineMode.y == 0, "not begun: the drawing is what there is to paint")
        session.paint(Array(t.regions.indices.dropLast()), from: .zero, animated: false)
        #expect(view.inkHidden == 0, "one area left")
        view.hidesLines = false
        session.paint([t.regions.count - 1], from: .zero, animated: false)
        #expect(session.isComplete && view.inkHidden == 0, "finished, with its lines")
        view.hidesLines = true
        #expect(view.inkHidden == 1 && view.frameUniforms().lineMode.y == 1)
        view.hidesLines = false
        #expect(view.inkHidden == 0)
        view.hidesLines = true
        // An undo: unfinished again, the lines are back.
        _ = try #require(session.undo())
        #expect(view.inkHidden == 0)
        // Finished again, the ink waits for the finale, which the canvas keeps for the shine's
        // moment; a replay shows the painting as it was made, and Stop the finished picture.
        session.paint([t.regions.count - 1], from: .zero, animated: false)
        view.replay()
        #expect(view.inkHidden == 0, "replaying")
        view.stopReplay()
        #expect(view.inkHidden == 1, "the replay stopped")
        view.tearDown()
    }

    /// A painting opened finished without its lines shows so from its first frame.
    @Test func aPaintingLeftWithoutItsLinesOpensWithoutThem() {
        let t = LineArtRenderingTests.book
        let session = PaintingSession(template: t)
        session.paint(Array(t.regions.indices), from: .zero, animated: false)
        let view = CanvasView(session: session)
        view.hidesLines = true
        #expect(view.inkHidden == 1)
        view.tearDown()
    }

    // MARK: Pictures

    /// A style hides the lines only of a finished picture.
    @Test func aStyleHidesTheLinesOfAFinishedPictureAlone() {
        typealias Style = TemplateRasterizer.Style
        #expect(Style.finished.hidingLines(true, painted: nil).withoutInk, "the finished style paints every area")
        #expect(Style.thumbnail.hidingLines(true, painted: [true, true]).withoutInk)
        #expect(!Style.thumbnail.hidingLines(true, painted: [true, false]).withoutInk)
        #expect(!Style.thumbnail.hidingLines(true, painted: nil).withoutInk && !Style.thumbnail.hidingLines(true, painted: []).withoutInk)
        #expect(!Style.finished.hidingLines(false, painted: nil).withoutInk && !Style.thumbnail.hidingLines(false, painted: [true]).withoutInk)
    }

    /// Thumbnails and shared pictures without the ink: the paint alone where the drawing was
    /// (as the style that draws no drawing has it), and the writing as ever.
    @Test func picturesDrawTheFinishedPictureWithoutItsInk() throws {
        let (t, dark, light, drawing) = try LineArtRenderingTests.writing()
        let all = [Bool](repeating: true, count: t.regions.count)
        func lumas(_ stroke: Int, _ image: CGImage) -> (middle: Int, darkest: Int) {
            let scale = Float(image.height) / Float(t.height), p = LineArtRenderingTests.middle(of: stroke, in: t)
            let pixels = PixelReader(image), x = Int(p.x * scale), y = Int(p.y * scale)
            let around = (-1...1).flatMap { dy in (-1...1).map { dx in luma(pixels[x + dx, y + dy]) } }
            return (luma(pixels[x, y]), around.min()!)
        }
        let paintAlone = try #require(TemplateRasterizer.image(t, style: .paintedAreas, maxPixelSize: 2 * t.height))
        for style in [TemplateRasterizer.Style.finished, .thumbnail] {
            let inked = try #require(TemplateRasterizer.image(t, painted: all, style: style, maxPixelSize: 2 * t.height))
            let bare = try #require(TemplateRasterizer.image(
                t, painted: all, style: style.hidingLines(true, painted: all), maxPixelSize: 2 * t.height))
            record(bare, "picture-without-lines-\(style.paintAll ? "finished" : "thumbnail")")
            #expect(lumas(drawing, inked).darkest < lumas(drawing, paintAlone).middle - 10 || lumas(drawing, paintAlone).middle < 45)
            #expect(abs(lumas(drawing, bare).middle - lumas(drawing, paintAlone).middle) <= 3, "the paint where the drawing was")
            #expect(lumas(light, bare).darkest < 100, "writing over a light paint stays ink")
            #expect(lumas(dark, bare).middle > 200, "writing over a dark paint stays in the paper's tone")
        }
        // Unfinished, the same call draws the lines as ever.
        var some = all
        some[0] = false
        let unfinished = TemplateRasterizer.Style.thumbnail.hidingLines(true, painted: some)
        let a = try #require(TemplateRasterizer.pngData(t, painted: some, style: unfinished, maxPixelSize: 320))
        let b = try #require(TemplateRasterizer.pngData(t, painted: some, style: .thumbnail, maxPixelSize: 320))
        #expect(a == b)
    }

    // MARK: The painting keeps the choice

    /// `meta.json` from before the choice has no `hidesLines`, which reads as lines shown and
    /// writes no key; set, it round-trips, also through a file a newer app wrote.
    @Test func theChoiceIsAnOptionalFieldOfTheMetadata() throws {
        var artwork = Artwork(title: "Book", template: LineArtRenderingTests.book, settings: GenerationSettings())
        #expect(artwork.hidesLines == nil && !artwork.paintsWithoutLines)
        let plain = try JSONEncoder().encode(artwork)
        let fields = try #require(try JSONSerialization.jsonObject(with: plain) as? [String: Any])
        #expect(fields["hidesLines"] == nil)
        #expect(try JSONDecoder().decode(Artwork.self, from: plain).hidesLines == nil)

        artwork.hidesLines = true
        let chosen = try JSONEncoder().encode(artwork)
        let read = try JSONDecoder().decode(Artwork.self, from: chosen)
        #expect(read.hidesLines == true && read.id == artwork.id)
        #expect(read.paintsWithoutLines)

        var newer = try #require(try JSONSerialization.jsonObject(with: chosen) as? [String: Any])
        newer["format"] = Artwork.currentFormat + 1
        #expect(try JSONDecoder().decode(Artwork.self, from: JSONSerialization.data(withJSONObject: newer)).hidesLines == true)
        // A value that isn't a Bool is no choice, never an unreadable painting.
        newer["format"] = Artwork.currentFormat
        newer["hidesLines"] = "yes"
        #expect(try JSONDecoder().decode(Artwork.self, from: JSONSerialization.data(withJSONObject: newer)).hidesLines == nil)
    }

    /// The library keeps the choice with the painting, and a finished painting's gallery picture
    /// follows it; an unfinished one's stays.
    @Test func theLibraryKeepsTheChoiceAndTheThumbnailFollowsIt() async throws {
        let root = Fixtures.temporaryDirectory()
        func makeLibrary() -> Library { Library(store: ArtworkStore(root: root)) }
        let t = try LineArtRenderingTests.writing().template
        let drawing = try Self.inkProbe(t)
        let library = makeLibrary()
        let artwork = try await library.create(ArtworkDraft(title: "Book", template: t, settings: GenerationSettings()))
        let id = artwork.id
        func drawingInThumbnail() throws -> Int {
            let image = try #require(library.store.thumbnail(id))
            let scale = Float(image.height) / Float(t.height), p = LineArtRenderingTests.middle(of: drawing, in: t)
            let pixels = PixelReader(image), x = Int(p.x * scale), y = Int(p.y * scale)
            return (-1...1).flatMap { dy in (-1...1).map { dx in luma(pixels[x + dx, y + dy]) } }.min()!
        }

        // Not finished: the choice is kept, the picture untouched.
        await library.setHidesLines(id, true, template: t, progress: PaintProgress(regionCount: t.regions.count))
        #expect(library.artwork(with: id)?.hidesLines == true && library.artwork(with: id)?.thumbnailVersion == artwork.thumbnailVersion)
        await library.flush()
        #expect(makeLibrary().artwork(with: id)?.hidesLines == true)
        await library.setHidesLines(id, false, template: t, progress: PaintProgress(regionCount: t.regions.count))
        #expect(library.artwork(with: id)?.hidesLines == false)

        // Finished, with its lines.
        let done = Self.everyAreaPainted(t)
        library.saveProgress(done, for: id)
        await library.refreshThumbnail(id, template: t, progress: done)
        let version = try #require(library.artwork(with: id)?.thumbnailVersion)
        let inked = try drawingInThumbnail()

        await library.setHidesLines(id, true, template: t, progress: done)
        await library.flush()
        #expect(makeLibrary().artwork(with: id)?.hidesLines == true)
        #expect(library.artwork(with: id)?.thumbnailVersion == version + 1)
        #expect(try drawingInThumbnail() > inked + 10, "the gallery's picture lost its ink: \(inked)")
        let shared = try ArtworkExporter.paintingPNG(store: library.store, artwork: try #require(library.artwork(with: id)))
        let plain = try #require(TemplateRasterizer.pngData(
            t, style: .finished.hidingLines(true, painted: nil), maxPixelSize: ArtworkExporter.imagePixelSize))
        #expect(shared == plain, "Share Painting's picture is the painting as paint alone")

        // Back with its lines.
        await library.setHidesLines(id, false, template: t, progress: done)
        #expect(try drawingInThumbnail() == inked)
        // The same choice again changes nothing.
        let settled = try #require(library.artwork(with: id)?.thumbnailVersion)
        await library.setHidesLines(id, false, template: t, progress: done)
        #expect(library.artwork(with: id)?.thumbnailVersion == settled)
    }

    /// The completion bar's picture is drawn again when the lines are hidden or shown.
    @Test func theSharedPictureFollowsTheChoice() async throws {
        let t = LineArtRenderingTests.book
        let session = PaintingSession(template: t)
        session.paint(Array(t.regions.indices), from: .zero, animated: false)
        let share = CompletionShare()
        await share.prepare(for: session)
        let inked = try #require(share.picture)
        share.withoutLines = true
        await share.prepare(for: session)
        let bare = try #require(share.picture)
        #expect(bare !== inked)
        let p = LineArtRenderingTests.middle(of: try Self.inkProbe(t), in: t)
        let scale = Float(bare.width) / Float(t.width)
        func at(_ image: CGImage) -> Int { luma(PixelReader(image)[Int(p.x * scale), Int(p.y * scale)]) }
        #expect(at(bare) > at(inked) + 10, "the stroke's ink is in one and not the other: \(at(inked)), \(at(bare))")
        // Asked again with nothing changed, it is the same picture.
        await share.prepare(for: session)
        #expect(share.picture === bare)
    }
}
