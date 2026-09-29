import CoreGraphics
import Foundation
import ImageIO
import Metal
import PaintCore
import UniformTypeIdentifiers

/// Offscreen rendering with the canvas shaders: gallery thumbnails, share/export images,
/// printable previews and time-lapse frames. Thread-safe; call it off the main actor.
nonisolated enum CanvasSnapshot {
    nonisolated struct Options: Sendable {
        var outlines: Bool
        var numbers: Bool
        /// Outline width in output pixels per canvas unit of scale (≥ 1 px is kept crisp).
        var outlineWidth: Float = 1.1
        var dark = false

        /// The artwork as painted so far: unpainted regions stay paper, no line art.
        static let painting = Options(outlines: false, numbers: false)
        /// Line art and numbers (painted regions filled): a printable template.
        static let preview = Options(outlines: true, numbers: true)
        /// Gallery tile: paint plus faint line art, no numbers.
        static let thumbnail = Options(outlines: true, numbers: false, outlineWidth: 0.8)
    }

    /// Renders `template` with `progress` (nil = nothing painted) into an image of `size`
    /// pixels; the canvas is fitted and centred, any letterbox is transparent.
    static func render(template: Template, progress: PaintProgress?, size: CGSize, options: Options = .painting) -> CGImage? {
        guard let context = RenderContext.shared, let scene = CanvasScene(template: template, context: context) else { return nil }
        let painted = (0..<template.regions.count).map { progress?.isPainted($0) ?? false }
        return render(scene: scene, template: template, painted: painted, size: size, options: options, context: context)
    }

    /// Time-lapse frame: the first `strokes` fills of the progress log.
    static func timelapseFrame(template: Template, progress: PaintProgress, strokes: Int, size: CGSize) -> CGImage? {
        guard let context = RenderContext.shared, let scene = CanvasScene(template: template, context: context) else { return nil }
        var painted = [Bool](repeating: false, count: template.regions.count)
        for stroke in progress.log.prefix(max(0, strokes)) { painted[Int(stroke.region)] = true }
        return render(scene: scene, template: template, painted: painted, size: size, options: .thumbnail, context: context)
    }

    static func render(
        scene: CanvasScene, template: Template, painted: [Bool], size: CGSize, options: Options, context: RenderContext
    ) -> CGImage? {
        let w = min(8192, max(1, Int(size.width.rounded()))), h = min(8192, max(1, Int(size.height.rounded())))
        let canvasW = Float(template.width), canvasH = Float(template.height)
        let scale = min(Float(w) / canvasW, Float(h) / canvasH)
        let palette = CanvasPalette.appearance(dark: options.dark)

        var states: [RegionState] = []
        states.reserveCapacity(template.regions.count)
        for i in template.regions.indices {
            states.append(.settled(painted: painted[i], origin: .zero, seed: 0))
        }

        var u = CanvasUniforms()
        u.transform = SIMD4((Float(w) - canvasW * scale) / 2, (Float(h) - canvasH * scale) / 2, scale, 1)
        u.viewport = SIMD4(Float(w), Float(h), canvasW, canvasH)
        u.background = SIMD4(palette.background, 1)
        u.paper = SIMD4(palette.paper, 0)
        u.ink = SIMD4(palette.ink, palette.outlineOpacity)
        let width = options.outlineWidth * max(scale, 0.25)
        u.outline = SIMD4(width, width, 0, options.numbers ? 1 : 0)
        u.labels = SIMD4(5, 7, .greatestFiniteMagnitude, 0)
        u.time = SIMD4(0, -10_000, -10_000, -10_000)

        let device = context.device
        let rowBytes = (w * 4 + 255) / 256 * 256
        let stateBuffer: (any MTLBuffer)? = states.isEmpty
            ? device.makeBuffer(length: 16, options: .storageModeShared)
            : device.makeBuffer(bytes: states, length: MemoryLayout<RegionState>.stride * states.count, options: .storageModeShared)
        guard let color = context.makeColorTarget(width: w, height: h),
              let outlines = context.makeOutlineTarget(width: w, height: h),
              let stateBuffer,
              let readback = device.makeBuffer(length: rowBytes * h, options: .storageModeShared),
              let commands = context.queue.makeCommandBuffer()
        else { return nil }

        context.encode(
            commands, scene: scene, states: stateBuffer, uniforms: u,
            targets: RenderContext.Targets(
                color: color, multisample: context.makeMultisampleTarget(width: w, height: h), outlines: outlines),
            content: RenderContext.Content(outlines: options.outlines, numbers: options.numbers))
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

    /// Output size for a template fitted into `longSide` pixels.
    static func fittedSize(for template: Template, longSide: Int) -> CGSize {
        let s = Double(longSide) / Double(max(template.width, template.height))
        return CGSize(width: (Double(template.width) * s).rounded(), height: (Double(template.height) * s).rounded())
    }

    static func pngData(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data as CFMutableData, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        return CGImageDestinationFinalize(dest) ? data as Data : nil
    }
}
