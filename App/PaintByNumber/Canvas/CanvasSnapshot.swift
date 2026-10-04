import CoreGraphics
import Foundation
import Metal
import PaintCore

/// Offscreen rendering with the canvas shaders: the finished painting's share picture
/// (`CompletionShare`), the time-lapse's frames (`TimelapseFrameRenderer` uses its uniforms)
/// and the render tests. Thumbnails, shared images, previews and PDFs are `TemplateRasterizer`'s.
/// Thread-safe; call it off the main actor.
nonisolated enum CanvasSnapshot {
    nonisolated struct Options: Sendable {
        var outlines: Bool
        var numbers: Bool
        /// Outline width in output pixels per canvas unit of scale (≥ 1 px is kept crisp).
        var outlineWidth: Float = 1.1
        /// Light paper unless a test asks for another palette; exports never do.
        var palette = CanvasPalette.light
        /// Palette index whose unpainted regions get the selection highlight.
        var highlight: Int?
        /// How a layered template's lines draw, and how heavy a coloring book's are; nil = the
        /// one Settings › Advanced stored.
        var lineAppearance: LineAppearance?
        /// The zoom whose line look to draw (1 = the painting fitted, as images show it).
        var lineZoom: Float = 1

        /// The artwork as painted so far: unpainted regions stay paper, no line art (a coloring
        /// book keeps its drawing, `drawsLines(for:)`).
        static let painting = Options(outlines: false, numbers: false)
        /// Line art and numbers over the paint (render tests).
        static let preview = Options(outlines: true, numbers: true)
        /// The time-lapse's look: paint plus faint line art, no numbers.
        static let thumbnail = Options(outlines: true, numbers: false, outlineWidth: 0.8)

        /// Whether `scene`'s line art is drawn: with `outlines`, and always for a coloring book,
        /// whose drawing is part of the picture.
        func drawsLines(for scene: CanvasScene) -> Bool { outlines || scene.lineArtStyle == .coloringBook }
    }

    /// Renders `template` with `progress` (nil = nothing painted) into an image of `size`
    /// pixels; the canvas is fitted and centred, any letterbox is transparent.
    static func render(template: Template, progress: PaintProgress?, size: CGSize, options: Options = .painting) -> CGImage? {
        guard let context = RenderContext.shared, let scene = CanvasScene(template: template, context: context) else { return nil }
        let painted = (0..<template.regions.count).map { progress?.isPainted($0) ?? false }
        return render(scene: scene, painted: painted, size: size, options: options, context: context)
    }

    /// `scene` with the regions `painted` says (one flag per region), as `render(template:…)`.
    static func render(scene: CanvasScene, painted: [Bool], size: CGSize, options: Options, context: RenderContext) -> CGImage? {
        let w = min(8192, max(1, Int(size.width.rounded()))), h = min(8192, max(1, Int(size.height.rounded())))
        return image(
            scene: scene, states: painted.map(RegionState.settled(painted:)),
            uniforms: uniforms(scene: scene, width: w, height: h, options: options),
            content: RenderContext.Content(outlines: options.drawsLines(for: scene), numbers: options.numbers),
            width: w, height: h, context: context)
    }

    /// One frame of `scene` with these region states, uniforms and passes, read back as a
    /// Display P3 image of `w`×`h` pixels.
    static func image(
        scene: CanvasScene, states: [RegionState], uniforms: CanvasUniforms, content: RenderContext.Content,
        width w: Int, height h: Int, context: RenderContext
    ) -> CGImage? {
        let device = context.device
        let rowBytes = (w * 4 + 255) / 256 * 256
        guard let stateBuffer = CanvasScene.buffer(states, device),
              let color = context.makeColorTarget(width: w, height: h),
              let outlines = context.makeOutlineTarget(width: w, height: h),
              let readback = device.makeBuffer(length: rowBytes * h, options: .storageModeShared),
              let commands = context.queue.makeCommandBuffer()
        else { return nil }
        context.encode(
            commands, scene: scene, states: stateBuffer, uniforms: uniforms,
            targets: RenderContext.Targets(
                color: color, multisample: context.makeMultisampleTarget(width: w, height: h), outlines: outlines),
            content: content)
        guard let blit = commands.makeBlitCommandEncoder() else { return nil }
        blit.copy(
            from: color, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
            sourceSize: MTLSize(width: w, height: h, depth: 1),
            to: readback, destinationOffset: 0, destinationBytesPerRow: rowBytes, destinationBytesPerImage: rowBytes * h)
        blit.endEncoding()
        commands.commit()
        commands.waitUntilCompleted()
        guard commands.status == .completed else { return nil }

        let data = Data(bytes: readback.contents(), count: rowBytes * h)
        guard let provider = CGDataProvider(data: data as CFData),
              let space = CGColorSpace(name: CGColorSpace.displayP3)
        else { return nil }
        return CGImage(
            width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: rowBytes, space: space,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    /// Shader constants for an offscreen frame: canvas fitted and centred in `width`×`height`
    /// pixels, renderer clock at 0.
    static func uniforms(scene: CanvasScene, width w: Int, height h: Int, options: Options) -> CanvasUniforms {
        let canvasW = scene.canvasSize.x, canvasH = scene.canvasSize.y
        let scale = min(Float(w) / canvasW, Float(h) / canvasH)
        let palette = options.palette
        var u = CanvasUniforms()
        u.transform = SIMD4((Float(w) - canvasW * scale) / 2, (Float(h) - canvasH * scale) / 2, scale, 1)
        u.viewport = SIMD4(Float(w), Float(h), canvasW, canvasH)
        u.setChrome(palette, shadowOpacity: 0, outlineOpacity: palette.outlineOpacity)
        let width = options.outlineWidth * max(scale, 0.25)
        u.outline = SIMD4(width, width, 0, options.numbers ? 1 : 0)
        switch scene.lineArtStyle {
        case .layered:
            u.setLines(LineStyle(options.lineAppearance ?? .stored(), zoom: options.lineZoom))
        case .coloringBook:
            let weight = (options.lineAppearance ?? .stored()).coloringBookWeight
            u.setColoringBookLines(width: width * ColoringBookLook.widthFactor * weight)
        case nil:
            u.setLines(.classic)
        }
        u.labels = SIMD4(5, 7, .greatestFiniteMagnitude, 0)
        u.numbers = SIMD4(0.8, 0.9, 0.04, 0)
        u.time = SIMD4(0, CanvasClock.never, CanvasClock.never, CanvasClock.never)
        if let color = options.highlight, color >= 0, color < scene.paletteLinear.count {
            u.select(scene.paletteLinear[color], palette: palette)
            u.ids.x = Int32(color)
            u.outline.z = 1
        }
        return u
    }

    /// Output size for a template fitted into `longSide` pixels.
    static func fittedSize(for template: Template, longSide: Int) -> CGSize {
        let s = Double(longSide) / Double(max(template.width, template.height))
        return CGSize(width: (Double(template.width) * s).rounded(), height: (Double(template.height) * s).rounded())
    }
}
