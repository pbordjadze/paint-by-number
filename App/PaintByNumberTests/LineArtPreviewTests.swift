import CoreGraphics
import Foundation
import PaintCore
import SwiftUI
import Testing
@testable import PaintByNumber

/// Settings › Preview's Line Art: what the create flow's comparison draws of a template
/// (`LineArtDrawing`), how heavy, the comparison drawing it, and the model making it.
@MainActor
struct LineArtPreviewTests {
    /// A book draws its drawing alone: the drawn edges between regions and its strokes, never a
    /// color edge or the canvas's border.
    @Test func aBookDrawsItsDrawingAlone() throws {
        let t = LineArtRenderingTests.book
        let art = try #require(t.lineArt)
        let drawing = LineArtDrawing(t)
        #expect(drawing.isColoringBook)
        #expect(drawing.size == CGSize(width: t.width, height: t.height))
        let edges = t.edges.indices.filter {
            t.edges[$0].right != BoundaryEdge.outside && art.edgeLayers[$0] != LineLayer.color.rawValue
                && t.edges[$0].pointCount >= 2
        }
        #expect(!edges.isEmpty && !art.strokes.isEmpty)
        #expect(drawing.lines.count == edges.count + art.strokes.count)
        // In the template's order: the edges' points, then the strokes'.
        let first = try #require(drawing.lines.first)
        #expect(first.points == t.points(of: t.edges[edges[0]]).map { CGPoint($0) })
        let canvas = CGRect(origin: .zero, size: drawing.size).insetBy(dx: -1, dy: -1)
        #expect(drawing.lines.allSatisfy { canvas.contains($0.bounds) })
    }

    /// A classic template (the edge detector failed) draws every edge between regions, lighter.
    @Test func aClassicTemplateDrawsEveryEdgeBetweenRegions() {
        let t = Fixtures.mosaic
        let drawing = LineArtDrawing(t)
        #expect(!drawing.isColoringBook)
        #expect(drawing.lines.count == t.edges.filter { $0.right != BoundaryEdge.outside && $0.pointCount >= 2 }.count)
        #expect(drawing.inkOpacity(scale: 1) < 1)
    }

    /// Zoomed in, a frame strokes only the lines that pass through what it shows; showing half
    /// the canvas or more, all of them.
    @Test func aFrameStrokesTheLinesInView() {
        let drawing = LineArtDrawing(LineArtRenderingTests.book)
        func subpaths(_ path: Path) -> Int {
            var count = 0
            path.forEach { if case .move = $0 { count += 1 } }
            return count
        }
        #expect(subpaths(drawing.path(within: CGRect(origin: .zero, size: drawing.size))) == drawing.lines.count)
        let corner = CGRect(x: 0, y: 0, width: drawing.size.width / 4, height: drawing.size.height / 4)
        let inCorner = drawing.lines.filter { $0.bounds.intersects(corner) }.count
        #expect(inCorner > 0 && inCorner < drawing.lines.count)
        #expect(subpaths(drawing.path(within: corner)) == inCorner)
    }

    /// The lines are as heavy as the canvas draws them: its fitted width where the picture is as
    /// large as the canvas fits the painting, its zoomed width above, scaled down with smaller
    /// pictures but never below a hairline.
    @Test func linesAreAsHeavyAsTheCanvasDrawsThem() {
        let book = LineArtDrawing(LineArtRenderingTests.book)
        for weight in LineWeight.allCases {
            let fitted = CGFloat(ColoringBookLook.widthPoints(depth: 0, weight: weight.factor))
            #expect(abs(book.lineWidth(scale: 1, weight: weight) - fitted) < 1e-5)
            #expect(abs(book.lineWidth(scale: 0.5, weight: weight) - fitted / 2) < 1e-5)
            let zoomed = CGFloat(ColoringBookLook.widthPoints(depth: 2, weight: weight.factor))
            #expect(abs(book.lineWidth(scale: 4, weight: weight) - zoomed) < 1e-5)
        }
        #expect(book.lineWidth(scale: 0.01, weight: .fine) == LineArtDrawing.minimumWidth)
        #expect(book.inkOpacity(scale: 0.5) == 1 && book.inkOpacity(scale: 4) == 1)
        let classic = LineArtDrawing(Fixtures.mosaic)
        #expect(abs(classic.lineWidth(scale: 2, weight: .bold) - CGFloat(ClassicLook.widthPoints(depth: 1))) < 1e-5)
    }

    /// The comparison shows the line art on the sheet's paper beside the photo, the drawing's
    /// ink where its lines run and nothing of the photo.
    @Test func theComparisonShowsTheLineArtBesideThePhoto() throws {
        let book = LineArtRenderingTests.book
        let red = SIMD3(200, 30, 40)
        let photo = try #require(Self.solid(red, width: book.width, height: book.height))
        let view = CompareView(
            photo: photo, after: .lineArt(LineArtDrawing(book)), afterID: "book", afterLabel: "Line Art",
            aspectRatio: CGFloat(book.width) / CGFloat(book.height)
        )
        .frame(width: 300, height: 400)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        let image = try #require(renderer.cgImage)
        let pixels = try #require(Self.pixels(of: image))
        #expect(pixels.width == 300 && pixels.height == 400)
        // The photo on the leading half (the divider starts in the middle)…
        #expect(maxDifference(pixels[60, 300], red) < 16)
        // …and on the trailing half, clear of the divider's handle and the caption, only paper
        // and ink.
        let paper = bytes(CanvasPalette.sheetPaperSRGB)
        var onPaper = 0, inked = 0, photoShowing = 0
        for y in stride(from: 60, to: 390, by: 2) {
            for x in stride(from: 185, to: 295, by: 2) {
                let c = pixels[x, y]
                if maxDifference(c, paper) < 10 {
                    onPaper += 1
                } else if luma(c) < 120 {
                    inked += 1
                }
                if c.x - c.z > 60 { photoShowing += 1 }
            }
        }
        #expect(photoShowing == 0, "The photo shows through the line art")
        #expect(onPaper > 2000 && inked > 50, "paper \(onPaper), ink \(inked)")
    }

    /// With the Line Art preview, a photo's comparison waits for the winner's draft rather than
    /// show the first candidate, which has no drawing (every edge between its regions would
    /// stand in for it), and then shows the drawing.
    @Test func theModelPreviewsTheLineArt() async throws {
        let model = CreateModel(paintingLength: .relaxed, previewStyle: .lineArt)
        model.load(sample: try #require(Sample.named("red-fox")))
        var shownBeforeTheDecision = false
        try await waitUntil(polling: .milliseconds(5)) {
            if model.decision == nil, model.preview != nil { shownBeforeTheDecision = true }
            return model.isFinal
        }
        #expect(!shownBeforeTheDecision, "The first candidate showed as line art")
        let preview = try #require(model.preview)
        guard case .lineArt(let drawing) = preview.picture else {
            Issue.record("The preview isn't line art")
            return
        }
        #expect(drawing.isColoringBook && !drawing.lines.isEmpty)
        #expect(drawing.size == CGSize(width: preview.template.width, height: preview.template.height))
    }

    /// One color, `width` × `height` pixels.
    private static func solid(_ rgb: SIMD3<Int>, width: Int, height: Int) -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.setFillColor(CGColor(srgbRed: CGFloat(rgb.x) / 255, green: CGFloat(rgb.y) / 255, blue: CGFloat(rgb.z) / 255, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()
    }

    /// `image` drawn into 8-bit sRGB (whatever space the renderer gave it).
    private static func pixels(of image: CGImage) -> PixelReader? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return ctx.makeImage().map(PixelReader.init)
    }
}
