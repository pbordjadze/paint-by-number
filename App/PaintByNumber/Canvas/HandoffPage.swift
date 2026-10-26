import CoreGraphics
import Foundation
import PaintCore

/// A new painting's page as its canvas first draws it: fitted to `size` points, nothing painted,
/// the selected color not shown yet, in the canvas's paper, ink and line weight
/// (`CanvasLook`), with no drop shadow. The create flow's picture becomes it before the painting
/// takes the screen, so that the canvas, drawing the same page under it, changes nothing when it
/// does (`StartHandoff`); the canvas then eases the selected color in (`revealSelection`).
nonisolated enum HandoffPage {
    /// What the page is drawn with: its size in points and pixels per point, and the canvas's
    /// settings.
    nonisolated struct Look: Equatable, Sendable {
        var size: CGSize
        var scale: CGFloat
        var paper: PaperAppearance
        var interfaceIsDark: Bool
        var lineWeight: LineWeight
        var reduceMotion: Bool

        /// The pixels it is drawn in, or nil for a size too small or too large to draw.
        var pixels: (width: Int, height: Int)? {
            let w = (size.width * scale).rounded(), h = (size.height * scale).rounded()
            guard w.isFinite, h.isFinite, w >= 1, h >= 1, w <= 8192, h <= 8192 else { return nil }
            return (Int(w), Int(h))
        }
    }

    /// Off the main actor; nil without Metal.
    @concurrent
    static func render(_ template: Template, look: Look) async -> CGImage? {
        guard let pixels = look.pixels, template.width > 0, template.height > 0,
              let context = RenderContext.shared, let scene = CanvasScene(template: template, context: context)
        else { return nil }
        let (w, h) = pixels
        let palette = CanvasPalette.resolve(look.paper, interfaceIsDark: look.interfaceIsDark)
        let s = Float(look.scale)
        // The canvas's zoom, in pixels per canvas unit, for a page `size` wide.
        let zoom = Float(w) / Float(template.width)
        let canvasLook = CanvasLook(
            pointScale: s, depth: 0, palette: palette, coloringBook: scene.isColoringBook, lineWeight: look.lineWeight,
            selectionShown: 0, reduceMotion: look.reduceMotion)
        let frame = CanvasFrame(
            origin: .zero, scale: zoom, pointScale: s, targetSize: SIMD2(Float(w), Float(h)),
            canvasSize: SIMD2(Float(template.width), Float(template.height)),
            palette: palette, shadowOpacity: 0, outlineOpacity: canvasLook.outlineOpacity,
            outlineWidth: canvasLook.outlineWidth, selectedOutlineWidth: canvasLook.selectedOutlineWidth, hatch: 0,
            numbersShown: 1, lines: canvasLook.lines, labels: canvasLook.labels, numbers: canvasLook.numbers,
            time: SIMD4(0, CanvasClock.never, CanvasClock.never, CanvasClock.never),
            selection: nil, hovered: -1, pulsing: -1, bumped: -1, brush: nil,
            shine: (start: CanvasClock.never, color: -1), photoOpacity: 0)
        return CanvasSnapshot.image(
            scene: scene, states: Array(repeating: .settled(painted: false), count: template.regions.count),
            uniforms: CanvasUniforms(frame), content: RenderContext.Content(outlines: true, numbers: true),
            width: w, height: h, context: context)
    }
}
