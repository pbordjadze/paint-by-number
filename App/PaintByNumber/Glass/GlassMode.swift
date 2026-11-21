#if UNRELEASED
import Metal
import PaintCore
import os

/// Stained Glass on the canvas (painting-company row 366): the canvas's mode (`CanvasMode`) for a
/// window, drawing each piece as `GlassTexture` paints it, lit or unlit, with its lead, from the
/// window's fields (`GlassTexture.fields()`, one texture at the template's size) and the glasses
/// offered. A piece's glass rides in its region state (`RegionState.mode`, `code(glass:replacing:)`),
/// so a glass pours in from the touch over the one before it. No outlines and no numbers: the
/// lead is the drawing, and glazing is free.
nonisolated final class GlassMode: CanvasMode, @unchecked Sendable {
    /// Must match `GlassParameters` (Shaders.metal).
    struct Parameters {
        var lead: SIMD4<Float>
        var warm: SIMD4<Float>
        var unlit: SIMD4<Float>
    }

    let drawsOutlines = false
    let drawsNumbers = false
    let backdrop: SIMD3<Float>? = CanvasColor.linearP3(sRGB: GlassPicture.nave)

    /// How long the sun takes to pass behind a finished window.
    static let sunDuration: Float = 2.6

    private let pipeline: any MTLRenderPipelineState
    private let lightPipeline: any MTLRenderPipelineState
    private let fields: any MTLTexture
    private let glasses: any MTLBuffer
    private let parameters: Parameters
    /// The sun: x its start on the renderer's clock, y its duration, z where it is held (0…1;
    /// < 0: not held), w 1 while it may pass. Set from the main actor, read as frames encode.
    private let sunState = OSAllocatedUnfairLock(initialState: SIMD4<Float>(0, GlassMode.sunDuration, -1, 0))

    /// The window `template`, its fields `texture` and the glasses `offered` (as the
    /// glazing names them). Uploads to the GPU and waits for it: make it off the main actor.
    init?(template: Template, texture: GlassTexture, offered: [PaletteColor], context: RenderContext) {
        guard texture.width == template.width, texture.height == template.height,
              let pipeline = context.makePipeline(vertex: "fillVertex", fragment: "glassFillFragment", blends: false),
              let lightPipeline = context.makePipeline(vertex: "canvasRectVertex", fragment: "glassLightFragment", blends: true),
              let fields = Self.upload(texture, context: context),
              let glasses = CanvasScene.buffer(
                offered.map { SIMD4(CanvasColor.linearP3($0, space: template.colorSpace), 1) }, context.device)
        else { return nil }
        self.pipeline = pipeline
        self.lightPipeline = lightPipeline
        self.fields = fields
        self.glasses = glasses
        let width = Float(max(template.width, template.height)) * 0.012
        parameters = Parameters(
            lead: SIMD4(GlassPicture.lead, width),
            warm: SIMD4(GlassTexture.warm, GlassTexture.unlitTint),
            unlit: SIMD4(GlassTexture.unlitBase, 0))
    }

    /// The value a piece's region state carries: the glass in it (nil: none) and the one it pours
    /// over (nil: unlit glass). See `glassFillFragment`.
    static func code(glass: Int?, replacing before: Int?) -> Float {
        Float((glass.map { $0 + 1 } ?? 0) + 1024 * (before.map { $0 + 1 } ?? 0))
    }

    func drawPaint(_ encoder: any MTLRenderCommandEncoder, frame: CanvasModeFrame) {
        let scene = frame.scene
        guard scene.indexCount > 0 else { return }
        var u = frame.uniforms, p = parameters
        let size = MemoryLayout<CanvasUniforms>.stride
        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBuffer(scene.positions, offset: 0, index: 0)
        encoder.setVertexBuffer(scene.vertexRegions, offset: 0, index: 1)
        encoder.setVertexBytes(&u, length: size, index: 2)
        encoder.setFragmentBuffer(scene.regionColors, offset: 0, index: 0)
        encoder.setFragmentBuffer(frame.states, offset: 0, index: 1)
        encoder.setFragmentBytes(&u, length: size, index: 2)
        encoder.setFragmentBuffer(glasses, offset: 0, index: 3)
        encoder.setFragmentBytes(&p, length: MemoryLayout<Parameters>.stride, index: 4)
        encoder.setFragmentTexture(fields, index: 0)
        encoder.drawIndexedPrimitives(
            type: .triangle, indexCount: scene.indexCount, indexType: .uint32,
            indexBuffer: scene.indices, indexBufferOffset: 0)
    }

    /// The sun starts across the window at `time` (the renderer's clock, `CanvasView.canvasTime`),
    /// or stays held `held` of the way across (demos); `passes` false (Reduce Motion, a window
    /// no longer whole) keeps it away.
    func sun(at time: Float, held: Float? = nil, passes: Bool) {
        sunState.withLock { $0 = SIMD4(time, Self.sunDuration, held ?? -1, passes ? 1 : 0) }
    }

    func isAnimating(at time: Float) -> Bool {
        let s = sunState.withLock { $0 }
        return s.w > 0.5 && s.z < 0 && time >= s.x && time <= s.x + s.y
    }

    func drawOver(_ encoder: any MTLRenderCommandEncoder, frame: CanvasModeFrame) {
        var u = frame.uniforms, s = sunState.withLock { $0 }, margin: Float = 0
        let size = MemoryLayout<CanvasUniforms>.stride
        encoder.setRenderPipelineState(lightPipeline)
        encoder.setVertexBytes(&u, length: size, index: 0)
        encoder.setVertexBytes(&margin, length: MemoryLayout<Float>.size, index: 1)
        encoder.setFragmentBytes(&u, length: size, index: 0)
        encoder.setFragmentBytes(&s, length: MemoryLayout<SIMD4<Float>>.stride, index: 1)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
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
