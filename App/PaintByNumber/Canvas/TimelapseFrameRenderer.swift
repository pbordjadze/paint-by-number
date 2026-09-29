import CoreVideo
import Foundation
import Metal
import PaintCore

/// Replays a painting into video frames with the canvas shaders, for `TimelapseExporter`:
/// fills appear in the order they were painted, the one in progress spreads with the same
/// wet-paint animation as on the live canvas, and recent fills are still settling.
nonisolated final class TimelapseFrameRenderer {
    enum RenderError: Error { case unavailable, texture }

    private let context: RenderContext
    private let scene: CanvasScene
    private let order: [Int]
    private let origins: [SIMD2<Float>]
    private let radii: [Float]
    private let stateBuffer: any MTLBuffer
    private let options: CanvasSnapshot.Options
    private var cache: CVMetalTextureCache?
    private var targetSize = SIMD2<Int>(0, 0)
    private var multisample: (any MTLTexture)?
    private var outlines: (any MTLTexture)?

    init?(template: Template, progress: PaintProgress, options: CanvasSnapshot.Options = .thumbnail) {
        guard let context = RenderContext.shared, let scene = CanvasScene(template: template, context: context) else { return nil }
        var origins: [SIMD2<Float>] = []
        var radii: [Float] = []
        for (i, region) in template.regions.enumerated() {
            let b = region.bounds
            let o = template.labels(ofRegion: i).first?.position ?? SIMD2(Float(b.minX + b.maxX) / 2, Float(b.minY + b.maxY) / 2)
            origins.append(o)
            var r: Float = 1
            for x in [Float(b.minX), Float(b.maxX)] {
                for y in [Float(b.minY), Float(b.maxY)] { r = max(r, ((SIMD2(x, y) - o) * (SIMD2(x, y) - o)).sum().squareRoot()) }
            }
            radii.append(r)
        }
        let states = template.regions.indices.map { RegionState.settled(painted: false, origin: origins[$0], seed: 0) }
        let stateBuffer: (any MTLBuffer)? = states.isEmpty
            ? context.device.makeBuffer(length: 16, options: .storageModeShared)
            : context.device.makeBuffer(bytes: states, length: MemoryLayout<RegionState>.stride * states.count, options: .storageModeShared)
        guard let stateBuffer else { return nil }
        self.context = context
        self.scene = scene
        self.order = progress.log.map { Int($0.region) }
        self.origins = origins
        self.radii = radii
        self.stateBuffer = stateBuffer
        self.options = options
        CVMetalTextureCacheCreate(nil, nil, context.device, nil, &cache)
    }

    var strokeCount: Int { order.count }

    /// Draws the first `strokes` fills plus `fraction` of the next one into a 32BGRA buffer.
    func render(strokes: Int, fraction: Float, into buffer: CVPixelBuffer) throws {
        let w = CVPixelBufferGetWidth(buffer), h = CVPixelBufferGetHeight(buffer)
        let states = stateBuffer.contents().bindMemory(to: RegionState.self, capacity: max(1, scene.regionCount))
        // Time is measured in strokes: the renderer clock is 0, a fill started `age` strokes ago.
        for (k, r) in order.enumerated() {
            let age = Float(strokes - k) + fraction
            if k < strokes || (k == strokes && fraction > 0) {
                states[r] = RegionState(origin: origins[r], start: -age, duration: 1, radius: radii[r], painted: 1, seed: Float(r % 61) * 0.73)
            } else {
                states[r] = .settled(painted: false, origin: origins[r], seed: 0)
            }
        }

        var cvTexture: CVMetalTexture?
        guard let cache,
              CVMetalTextureCacheCreateTextureFromImage(nil, cache, buffer, nil, RenderContext.colorFormat, w, h, 0, &cvTexture) == kCVReturnSuccess,
              let cvTexture, let texture = CVMetalTextureGetTexture(cvTexture)
        else { throw RenderError.texture }
        let size = SIMD2(w, h)
        if size != targetSize || outlines == nil {
            multisample = context.makeMultisampleTarget(width: w, height: h)
            outlines = context.makeOutlineTarget(width: w, height: h)
            targetSize = size
        }
        guard let outlines, let commands = context.queue.makeCommandBuffer() else { throw RenderError.unavailable }
        let u = CanvasSnapshot.uniforms(scene: scene, width: w, height: h, options: options)
        let background = u.background
        context.encode(
            commands, scene: scene, states: stateBuffer, uniforms: u,
            targets: RenderContext.Targets(color: texture, multisample: multisample, outlines: outlines),
            content: RenderContext.Content(
                outlines: options.outlines, numbers: options.numbers,
                clear: MTLClearColor(red: Double(background.x), green: Double(background.y), blue: Double(background.z), alpha: 1)))
        commands.commit()
        commands.waitUntilCompleted()
        // The pixels are Display P3; tag them so encoders and players keep the true paint colors.
        CVBufferSetAttachment(buffer, kCVImageBufferColorPrimariesKey, kCVImageBufferColorPrimaries_P3_D65, .shouldPropagate)
        CVBufferSetAttachment(buffer, kCVImageBufferTransferFunctionKey, kCVImageBufferTransferFunction_ITU_R_709_2, .shouldPropagate)
        CVBufferSetAttachment(buffer, kCVImageBufferYCbCrMatrixKey, kCVImageBufferYCbCrMatrix_ITU_R_709_2, .shouldPropagate)
    }

    /// Exports the replay of `progress` as a movie at `url`.
    @concurrent
    static func export(
        template: Template, progress: PaintProgress, to url: URL, longSide: Int = 1080,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) async throws {
        guard let renderer = TimelapseFrameRenderer(template: template, progress: progress) else { throw RenderError.unavailable }
        let size = CanvasSnapshot.fittedSize(for: template, longSide: longSide)
        try await TimelapseExporter.export(
            strokeCount: renderer.strokeCount, options: TimelapseExporter.Options(size: size), to: url, progress: onProgress
        ) { _, strokes, fraction, buffer in
            try renderer.render(strokes: strokes, fraction: fraction, into: buffer)
        }
    }
}
