#if UNRELEASED
import Metal
import PaintCore
import os

/// Woodblock on the canvas (painting-company row 375): the canvas's mode (`CanvasMode`) for the
/// bench, drawn by `woodblockFragment` (Woodblock.metal) over the picture and a margin of wood
/// around it, from five textures on PaintCore's `WoodblockBench` grid: the block's shape and the
/// key block's, what is carved, the ink and the baren's pressing, and the sheet. The bench's
/// arrays change a few cells at a time: the model copies the cells it changed into staging
/// buffers (`update`), and each frame's `prepare` blits only those into the textures. The canvas
/// draws its own numbers over the kyōgō (the regions this block prints are left unpainted, the
/// rest painted, which hides their numbers); on the print so far the mode draws them itself,
/// faint and mirrored as the print is, over the areas blocks still to come print (`drawOver`),
/// so every area is numbered until it is printed (the frame's rule 8). No outlines.
nonisolated final class WoodblockMode: CanvasMode, @unchecked Sendable {
    /// Must match `WoodblockParameters` (Woodblock.metal).
    nonisolated struct Parameters {
        var grid: SIMD4<Float>
        var view = SIMD4<Float>(0, 0, 0, 0)
        var ink = SIMD4<Float>(0, 0, 0, 1)
        var tint = SIMD4<Float>(0, 0, 0, 0)
        var anim = SIMD4<Float>(0, 1, -100, 0)
    }

    nonisolated enum View: Float { case block = 0, sheet = 1, peeling = 2, print = 3 }

    nonisolated enum Layer: Int, CaseIterable { case carved, inked, sheet }

    let drawsOutlines = false
    var drawsNumbers: Bool { state.withLockUnchecked { $0.numbers } }
    let backdrop: SIMD3<Float>? = WoodblockMode.bench

    /// The dark bench the block lies on (linear Display P3).
    static let bench = SIMD3<Float>(0.018, 0.011, 0.008)
    /// How long the sheet takes to peel.
    static let peelDuration: Float = 1.6

    let width: Int
    let height: Int
    private let pipeline: any MTLRenderPipelineState
    private let context: RenderContext
    private let margin: Float
    /// The canvas's numbers mirrored as the print is (`drawOver`), made from its scene's once.
    private let mirrored = OSAllocatedUnfairLock<(any MTLBuffer)?>(uncheckedState: nil)

    private struct State {
        var parameters: Parameters
        var numbers = false
        var printNumbers = false
        var shape: (any MTLTexture)?
        var key: (any MTLTexture)?
        var dirty: [Layer: WoodblockBench.Dirty] = [:]
    }
    private let state: OSAllocatedUnfairLock<State>
    private let textures: [Layer: any MTLTexture]
    private let staging: [Layer: any MTLBuffer]
    private let rowBytes: [Layer: Int]

    static func bytesPerCell(_ layer: Layer) -> Int { layer == .sheet ? 4 : 2 }

    /// The bench for `plan`, its key block's shape `key`. Uploads to the GPU: make it off the
    /// main actor.
    init?(plan: WoodblockPlan, key: WoodblockField, context: RenderContext) {
        let w = plan.grid.width, h = plan.grid.height
        guard let pipeline = context.makePipeline(vertex: "woodblockVertex", fragment: "woodblockFragment", blends: false)
        else { return nil }
        var textures: [Layer: any MTLTexture] = [:], staging: [Layer: any MTLBuffer] = [:], rows: [Layer: Int] = [:]
        for layer in Layer.allCases {
            let bpc = Self.bytesPerCell(layer)
            let row = (w * bpc + 255) / 256 * 256
            let desc = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: layer == .sheet ? .rgba8Unorm : .rg8Unorm, width: w, height: h, mipmapped: false)
            desc.usage = .shaderRead
            desc.storageMode = .private
            guard let texture = context.device.makeTexture(descriptor: desc),
                  let buffer = context.device.makeBuffer(length: row * h, options: .storageModeShared)
            else { return nil }
            textures[layer] = texture
            staging[layer] = buffer
            rows[layer] = row
        }
        self.textures = textures
        self.staging = staging
        rowBytes = rows
        width = w
        height = h
        self.pipeline = pipeline
        self.context = context
        margin = Float(max(plan.template.width, plan.template.height)) * 0.045
        let keyTexture = Self.upload(key.shape, width: w, height: h, context: context)
        state = OSAllocatedUnfairLock(uncheckedState: State(
            parameters: Parameters(grid: SIMD4(Float(w), Float(h), plan.grid.cellSize, margin)),
            shape: keyTexture, key: keyTexture))
    }

    /// Takes the field of the block now on the bench (its shape), and how the block looks.
    func setBlock(_ field: WoodblockField, kind: WoodblockPlan.Kind, ink: SIMD3<Float>, opacity: Float, tint: SIMD3<Float>) {
        let texture = Self.upload(field.shape, width: width, height: height, context: context)
        state.withLockUnchecked {
            $0.shape = texture
            $0.parameters.view.y = kind == .key ? 0 : (kind == .color ? 1 : 2)
            $0.parameters.ink = SIMD4(ink, opacity)
            $0.parameters.tint = SIMD4(tint, kind == .color ? 0.55 : 0)
        }
    }

    func setColorSpace(p3: Bool) {
        state.withLockUnchecked { $0.parameters.view.z = p3 ? 1 : 0 }
    }

    /// What the canvas shows, from `time` on (the renderer's clock): the sheet laid from then, the
    /// peel started then.
    func show(_ view: View, at time: Float, numbers: Bool, reduceMotion: Bool) {
        state.withLockUnchecked {
            let was = $0.parameters.view.x
            $0.parameters.view.x = view.rawValue
            $0.parameters.anim.w = reduceMotion ? 1 : 0
            $0.numbers = numbers && view != .print
            $0.printNumbers = numbers && view == .print
            if view == .sheet && was != View.sheet.rawValue { $0.parameters.anim.z = time }
            if view == .peeling && was != View.peeling.rawValue { $0.parameters.anim.x = time; $0.parameters.anim.y = Self.peelDuration }
        }
    }

    /// Holds the peel `fraction` of the way (demos).
    func holdPeel(at fraction: Float) {
        state.withLockUnchecked {
            $0.parameters.view.x = View.peeling.rawValue
            $0.parameters.anim.y = -min(max(fraction, 0.001), 1)
            $0.numbers = false
            $0.printNumbers = false
        }
    }

    /// Copies the cells of `bytes` (a bench array for `layer`) inside `dirty` into staging; the
    /// next frame blits them.
    func update(_ layer: Layer, from bytes: [UInt8], dirty: WoodblockBench.Dirty) {
        guard !dirty.isEmpty, let buffer = staging[layer], let row = rowBytes[layer] else { return }
        let bpc = Self.bytesPerCell(layer)
        let x0 = max(0, dirty.x0), x1 = min(width, dirty.x1), y0 = max(0, dirty.y0), y1 = min(height, dirty.y1)
        guard x0 < x1, y0 < y1, bytes.count == width * height * bpc else { return }
        let base = buffer.contents()
        bytes.withUnsafeBytes { raw in
            guard let src = raw.baseAddress else { return }
            for y in y0..<y1 {
                (base + y * row + x0 * bpc).copyMemory(from: src + (y * width + x0) * bpc, byteCount: (x1 - x0) * bpc)
            }
        }
        state.withLockUnchecked {
            var d = $0.dirty[layer] ?? WoodblockBench.Dirty(x0: x0, y0: y0, x1: x1, y1: y1)
            d.x0 = min(d.x0, x0); d.y0 = min(d.y0, y0); d.x1 = max(d.x1, x1); d.y1 = max(d.y1, y1)
            $0.dirty[layer] = d
        }
    }

    /// Every cell of `bytes` for `layer`.
    func replace(_ layer: Layer, with bytes: [UInt8]) {
        update(layer, from: bytes, dirty: WoodblockBench.Dirty(x0: 0, y0: 0, x1: width, y1: height))
    }

    func isAnimating(at time: Float) -> Bool {
        let p = state.withLockUnchecked { $0.parameters }
        guard p.anim.w < 0.5 else { return false }
        return (p.view.x == View.peeling.rawValue && p.anim.y > 0 && time < p.anim.x + p.anim.y + 0.1)
            || (p.view.x == View.sheet.rawValue && time < p.anim.z + 0.6)
    }

    func prepare(_ commands: any MTLCommandBuffer, frame: CanvasModeFrame) {
        let dirty = state.withLockUnchecked { s -> [Layer: WoodblockBench.Dirty] in
            let d = s.dirty
            s.dirty = [:]
            return d
        }
        guard !dirty.isEmpty, let blit = commands.makeBlitCommandEncoder() else { return }
        for (layer, d) in dirty where !d.isEmpty {
            guard let buffer = staging[layer], let texture = textures[layer], let row = rowBytes[layer] else { continue }
            let bpc = Self.bytesPerCell(layer)
            blit.copy(
                from: buffer, sourceOffset: d.y0 * row + d.x0 * bpc, sourceBytesPerRow: row,
                sourceBytesPerImage: row * (d.y1 - d.y0),
                sourceSize: MTLSize(width: d.x1 - d.x0, height: d.y1 - d.y0, depth: 1),
                to: texture, destinationSlice: 0, destinationLevel: 0, destinationOrigin: MTLOrigin(x: d.x0, y: d.y0, z: 0))
        }
        blit.endEncoding()
    }

    func drawPaint(_ encoder: any MTLRenderCommandEncoder, frame: CanvasModeFrame) {
        let s = state.withLockUnchecked { $0 }
        guard let shape = s.shape, let key = s.key, let carved = textures[.carved], let inked = textures[.inked],
              let sheet = textures[.sheet] else { return }
        var u = frame.uniforms, p = s.parameters, m = margin
        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBytes(&u, length: MemoryLayout<CanvasUniforms>.stride, index: 0)
        encoder.setVertexBytes(&m, length: MemoryLayout<Float>.size, index: 1)
        encoder.setFragmentBytes(&u, length: MemoryLayout<CanvasUniforms>.stride, index: 0)
        encoder.setFragmentBytes(&p, length: MemoryLayout<Parameters>.stride, index: 1)
        encoder.setFragmentTexture(shape, index: 0)
        encoder.setFragmentTexture(key, index: 1)
        encoder.setFragmentTexture(carved, index: 2)
        encoder.setFragmentTexture(inked, index: 3)
        encoder.setFragmentTexture(sheet, index: 4)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
    }

    /// The numbers on the print so far: the canvas's own glyphs, each moved to its mirror (the
    /// print is the block's mirror: `woodblockFragment`'s print view), drawn by the canvas's
    /// glyph pipeline over the regions left unpainted, fainter than on the block.
    func drawOver(_ encoder: any MTLRenderCommandEncoder, frame: CanvasModeFrame) {
        let s = state.withLockUnchecked { $0 }
        let scene = frame.scene
        guard s.printNumbers, scene.glyphCount > 0, let glyphs = mirroredGlyphs(of: scene),
              let glyph = context.pipelines(for: frame.format)?.glyph else { return }
        var u = frame.uniforms
        u.numbers.x *= 0.6
        u.numbers.y = u.numbers.x
        u.outline.w = 1
        u.selected.w = 0
        let size = MemoryLayout<CanvasUniforms>.stride
        encoder.setRenderPipelineState(glyph)
        encoder.setVertexBuffer(glyphs, offset: 0, index: 0)
        encoder.setVertexBuffer(scene.digitRects, offset: 0, index: 1)
        encoder.setVertexBuffer(scene.digitUVs, offset: 0, index: 2)
        encoder.setVertexBuffer(frame.states, offset: 0, index: 3)
        encoder.setVertexBuffer(scene.regionColors, offset: 0, index: 4)
        encoder.setVertexBytes(&u, length: size, index: 5)
        encoder.setFragmentTexture(context.atlasTexture, index: 0)
        encoder.setFragmentBytes(&u, length: size, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: scene.glyphCount)
    }

    private func mirroredGlyphs(of scene: CanvasScene) -> (any MTLBuffer)? {
        mirrored.withLockUnchecked { made in
            if let made { return made }
            let count = scene.glyphCount
            guard scene.glyphs.length >= count * MemoryLayout<GlyphInstance>.stride else { return nil }
            let source = scene.glyphs.contents().bindMemory(to: GlyphInstance.self, capacity: count)
            // About the grid's width, as the shader mirrors the print.
            let across = state.withLockUnchecked { $0.parameters.grid.x * $0.parameters.grid.z }
            var list = Array(UnsafeBufferPointer(start: source, count: count))
            for i in list.indices { list[i].center.x = across - list[i].center.x }
            made = CanvasScene.buffer(list, context.device)
            return made
        }
    }

    /// A field's shape as a half-float texture, uploaded by blit into private storage.
    private static func upload(_ values: [Float], width w: Int, height h: Int, context: RenderContext) -> (any MTLTexture)? {
        guard w > 0, h > 0, values.count == w * h else { return nil }
        let rowBytes = (w * 2 + 255) / 256 * 256
        guard let staging = context.device.makeBuffer(length: rowBytes * h, options: .storageModeShared) else { return nil }
        let base = staging.contents()
        for y in 0..<h {
            let row = (base + y * rowBytes).bindMemory(to: Float16.self, capacity: w)
            for x in 0..<w { row[x] = Float16(values[y * w + x]) }
        }
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r16Float, width: w, height: h, mipmapped: false)
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
