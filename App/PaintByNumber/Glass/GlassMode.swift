#if UNRELEASED
import CoreGraphics
import Metal
import PaintCore
import os

/// Stained Glass on the canvas (painting-company row 366): the canvas's mode (`CanvasMode`) for a
/// window, Liquid Glass misused as its glass (Paul's pick, November 21, 2026): each piece a clear
/// lens over the window's photo, its rim bending the photo and catching the light, tinted by the
/// glass poured into it; the lead heavy medieval came (`glassFillFragment`). It draws from the
/// window's fields (`GlassTexture.fields()`, one texture at the template's size), its photo and the
/// glasses offered. A piece's glass rides in its region state (`RegionState.mode`,
/// `code(glass:replacing:)`), so a glass pours in from the touch over the one before it. No
/// outlines, the lead is the drawing; each piece not yet glazed shows the number of its glass
/// (every mode is by numbers, painting-company row 366), in candlelight ink over the dark.
nonisolated final class GlassMode: CanvasMode, @unchecked Sendable {
    /// Must match `GlassParameters` (Shaders.metal).
    struct Parameters {
        var lead: SIMD4<Float>
        var lens: SIMD4<Float>
    }

    /// The lens's rounded rim, as a share of the window's long side.
    static let rimShare: Float = 0.025

    let drawsOutlines = false
    let drawsNumbers = true
    /// The finished window glows past white where the screen can (`ExtendedRange`): the moon
    /// comes up behind it as the sun passes. The poured glass takes the headroom; the light
    /// pass's sun band, added over it, may lift bright clear glass a little past white too. Only
    /// where both of its pipelines past white were made: elsewhere the window draws as it always
    /// has, never lost for want of them.
    let wantsExtendedRange: Bool
    let ink: SIMD3<Float>? = CanvasColor.linearP3(sRGB: SIMD3(0.97, 0.92, 0.80))
    let backdrop: SIMD3<Float>? = CanvasColor.linearP3(sRGB: GlassPicture.nave)

    /// How long the sun takes to pass behind a finished window.
    static let sunDuration: Float = 2.6

    private let pipeline: any MTLRenderPipelineState
    private let lightPipeline: any MTLRenderPipelineState
    /// The same two drawing into `RenderContext.extendedFormat`, for the painting screen past
    /// white (the shelf's pictures use the two above).
    private let extendedPipeline: (any MTLRenderPipelineState)?
    private let extendedLightPipeline: (any MTLRenderPipelineState)?
    private let fields: any MTLTexture
    private let photo: any MTLTexture
    private let glasses: any MTLBuffer
    private let parameters: Parameters
    /// The light over the window: the sun's pass (x its start on the renderer's clock, y its
    /// duration, z where it is held, 0…1, < 0: not held, w 1 while it may pass), then the hour's
    /// light (`daylight`: rgb added, w how much it dims) from `dayFrom.x` on (the renderer's
    /// clock; `dayFrom.y` 1 while a whole window shows it), and its glow past white (`glow.x`
    /// when it starts to come, over the sun's pass; `glow.y` 1 while the window is whole). Set
    /// from the main actor, read as frames encode. Must match `GlassLight` (Shaders.metal).
    struct Light {
        var sun = SIMD4<Float>(0, GlassMode.sunDuration, -1, 0)
        var day = SIMD4<Float>(0, 0, 0, 0)
        var dayFrom = SIMD4<Float>(0, 0, 0, 0)
        var glow = SIMD4<Float>(0, 0, 0, 0)
    }
    /// How much of the screen's headroom past white the lit glass takes (`ExtendedRange`), so the
    /// brightest pane stays short of glaring.
    static let glowShare: Float = 0.85
    private let light = OSAllocatedUnfairLock(initialState: Light())
    /// How long the hour's light takes to come over a window.
    static let dayFade: Float = 1.5

    /// The window `template`, its fields `texture`, the glasses `offered` (as the glazing names
    /// them) and its `photo` (none: the lenses look onto the dark room). Uploads to the GPU and
    /// waits for it: make it off the main actor.
    init?(template: Template, texture: GlassTexture, offered: [PaletteColor], photo: CGImage?, context: RenderContext) {
        guard texture.width == template.width, texture.height == template.height,
              let pipeline = context.makePipeline(vertex: "fillVertex", fragment: "glassFillFragment", blends: false),
              let lightPipeline = context.makePipeline(vertex: "canvasRectVertex", fragment: "glassLightFragment", blends: true),
              let fields = Self.upload(texture, context: context),
              let photo = photo.flatMap({ context.makePhotoTexture($0) }) ?? Self.darkRoom(context: context),
              let glasses = CanvasScene.buffer(
                offered.map { SIMD4(CanvasColor.linearP3($0, space: template.colorSpace), 1) }, context.device)
        else { return nil }
        self.pipeline = pipeline
        self.lightPipeline = lightPipeline
        let extendedPipeline = context.makePipeline(
            vertex: "fillVertex", fragment: "glassFillFragment", blends: false, format: RenderContext.extendedFormat)
        let extendedLightPipeline = context.makePipeline(
            vertex: "canvasRectVertex", fragment: "glassLightFragment", blends: true, format: RenderContext.extendedFormat)
        self.extendedPipeline = extendedPipeline
        self.extendedLightPipeline = extendedLightPipeline
        context.prepareExtendedRange()
        wantsExtendedRange = extendedPipeline != nil && extendedLightPipeline != nil && context.hasExtendedRange
        self.fields = fields
        self.photo = photo
        self.glasses = glasses
        let width = Float(GlassPicture.leadWidth(width: template.width, height: template.height))
        let rim = Self.rimShare * Float(max(template.width, template.height))
        parameters = Parameters(lead: SIMD4(GlassPicture.lead, width), lens: SIMD4(rim, Float(offered.count), 0, 0))
    }

    /// The value a piece's region state carries: the glass in it (nil: none), the one it pours
    /// over (nil: the clear lens) and whether it is framed (led in by the painter; a glazed piece
    /// always is, and a piece never shown is not). See `glassFillFragment`.
    static func code(glass: Int?, replacing before: Int?, framed: Bool = true) -> Float {
        Float((glass.map { $0 + 1 } ?? 0) + 1024 * (before.map { $0 + 1 } ?? 0) + (framed ? framedFlag : 0))
    }

    /// The framed bit of a region state's code (exact in a `Float`, past every glass's place).
    static let framedFlag = 1 << 20

    func drawPaint(_ encoder: any MTLRenderCommandEncoder, frame: CanvasModeFrame) {
        let scene = frame.scene
        guard scene.indexCount > 0 else { return }
        var u = frame.uniforms, p = parameters, l = light.withLock { $0 }
        p.lens.z = Self.glowShare * max(frame.headroom - 1, 0)
        let size = MemoryLayout<CanvasUniforms>.stride
        guard let fill = frame.format == RenderContext.extendedFormat ? extendedPipeline : Optional(pipeline) else { return }
        encoder.setRenderPipelineState(fill)
        encoder.setVertexBuffer(scene.positions, offset: 0, index: 0)
        encoder.setVertexBuffer(scene.vertexRegions, offset: 0, index: 1)
        encoder.setVertexBytes(&u, length: size, index: 2)
        encoder.setFragmentBuffer(frame.states, offset: 0, index: 1)
        encoder.setFragmentBytes(&u, length: size, index: 2)
        encoder.setFragmentBuffer(glasses, offset: 0, index: 3)
        encoder.setFragmentBytes(&p, length: MemoryLayout<Parameters>.stride, index: 4)
        encoder.setFragmentBytes(&l, length: MemoryLayout<Light>.stride, index: 5)
        encoder.setFragmentTexture(fields, index: 0)
        encoder.setFragmentTexture(photo, index: 1)
        encoder.drawIndexedPrimitives(
            type: .triangle, indexCount: scene.indexCount, indexType: .uint32,
            indexBuffer: scene.indices, indexBufferOffset: 0)
    }

    /// The sun starts across the window at `time` (the renderer's clock, `CanvasView.canvasTime`),
    /// or stays held `held` of the way across (demos); `passes` false (Reduce Motion, a window
    /// no longer whole) keeps it away. The hour's light (`hour`, local, 0…24) comes over the
    /// window once the sun has passed, at once without it; nil, none (a window not whole). A
    /// whole window glows past white as the sun passes, at once without it or held.
    func sun(at time: Float, held: Float? = nil, passes: Bool, hour: Float?) {
        light.withLock {
            $0.sun = SIMD4(time, Self.sunDuration, held ?? -1, passes ? 1 : 0)
            $0.glow = hour == nil ? .zero : SIMD4(passes && held == nil ? time : time - Self.sunDuration - 1, 1, 0, 0)
            guard let hour, held == nil else { $0.dayFrom = .zero; return }
            $0.day = Self.daylight(hour: hour)
            $0.dayFrom = SIMD4(passes ? time + Self.sunDuration : time - Self.dayFade, 1, 0, 0)
        }
    }

    /// The hour's light over a whole window: night's moonlight dims it, dawn is rose, the day
    /// plain and clear, the evening amber. Keys hold from one hour to the next, eased between.
    static func daylight(hour: Float) -> SIMD4<Float> {
        let night = SIMD4<Float>(0.010, 0.016, 0.040, 0.35)
        let keys: [(Float, SIMD4<Float>)] = [
            (0, night), (5, night), (6.5, SIMD4(0.09, 0.05, 0.05, 0.08)), (9, SIMD4(0.05, 0.05, 0.045, 0)),
            (16, SIMD4(0.05, 0.05, 0.045, 0)), (18.5, SIMD4(0.10, 0.055, 0.015, 0.05)),
            (20.5, SIMD4(0.03, 0.025, 0.05, 0.2)), (22, night), (24, night),
        ]
        let h = min(max(hour, 0), 24)
        for (a, b) in zip(keys, keys.dropFirst()) where h <= b.0 {
            let t = (h - a.0) / max(b.0 - a.0, 1e-3)
            let e = t * t * (3 - 2 * t)
            return a.1 + (b.1 - a.1) * e
        }
        return night
    }

    func isAnimating(at time: Float) -> Bool {
        let l = light.withLock { $0 }
        let sweeping = l.sun.w > 0.5 && l.sun.z < 0 && time >= l.sun.x && time <= l.sun.x + l.sun.y
        let dawning = l.dayFrom.y > 0.5 && time <= l.dayFrom.x + Self.dayFade
        return sweeping || dawning
    }

    func drawOver(_ encoder: any MTLRenderCommandEncoder, frame: CanvasModeFrame) {
        var u = frame.uniforms, l = light.withLock { $0 }, margin: Float = 0
        let size = MemoryLayout<CanvasUniforms>.stride
        guard let sun = frame.format == RenderContext.extendedFormat ? extendedLightPipeline : Optional(lightPipeline) else { return }
        encoder.setRenderPipelineState(sun)
        encoder.setVertexBytes(&u, length: size, index: 0)
        encoder.setVertexBytes(&margin, length: MemoryLayout<Float>.size, index: 1)
        encoder.setFragmentBytes(&u, length: size, index: 0)
        encoder.setFragmentBytes(&l, length: MemoryLayout<Light>.stride, index: 1)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
    }

    /// One pixel of the dark room, for a window whose photo is gone.
    private static func darkRoom(context: RenderContext) -> (any MTLTexture)? {
        guard let space = CGColorSpace(name: CGColorSpace.displayP3),
              let ctx = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.setFillColor(GlassPicture.cgColor(GlassPicture.nave, space: .displayP3))
        ctx.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        return ctx.makeImage().flatMap { context.makePhotoTexture($0) }
    }

    /// The fields as a half-float texture, uploaded by blit into private storage (which every GPU
    /// takes, the simulator's too).
    private static func upload(_ texture: GlassTexture, context: RenderContext) -> (any MTLTexture)? {
        let w = texture.width, h = texture.height
        guard w > 0, h > 0 else { return nil }
        let values = texture.fields()
        let rowBytes = (w * 8 + 255) / 256 * 256
        guard let staging = context.device.makeBuffer(length: rowBytes * h, options: .storageModeShared) else { return nil }
        let base = staging.contents()
        for y in 0..<h {
            let row = (base + y * rowBytes).bindMemory(to: Float16.self, capacity: w * 4)
            // A piece with no edge keeps its far distance: clamped to what a half float holds.
            for i in 0..<(w * 4) { row[i] = Float16(min(values[y * w * 4 + i], 60_000)) }
        }
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: w, height: h, mipmapped: false)
        desc.usage = .shaderRead
        desc.storageMode = .private
        guard let out = context.device.makeTexture(descriptor: desc),
              let commands = context.queue.makeCommandBuffer(),
              let blit = commands.makeBlitCommandEncoder()
        else { return nil }
        blit.copy(
            from: staging, sourceOffset: 0, sourceBytesPerRow: rowBytes, sourceBytesPerImage: rowBytes * h,
            sourceSize: MTLSize(width: w, height: h, depth: 1),
            to: out, destinationSlice: 0, destinationLevel: 0, destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
        blit.endEncoding()
        commands.commit()
        commands.waitUntilCompleted()
        return commands.status == .completed ? out : nil
    }
}
#endif
