import CoreGraphics
import Foundation
import Metal
import os
import PaintCore

/// Process-wide Metal state shared by every canvas and offscreen render: device, queue,
/// pipelines and the digit atlas. Immutable after creation, so it is safe to use from any
/// thread (the Metal objects it holds are thread-safe).
nonisolated final class RenderContext: @unchecked Sendable {
    static let shared: RenderContext? = RenderContext()

    /// Every canvas pass renders into this format; blending happens in linear light and the
    /// stored values are Display P3 with the sRGB curve.
    static let colorFormat: MTLPixelFormat = .bgra8Unorm_srgb
    /// A canvas drawing past white (`CanvasMode.wantsExtendedRange`, `ExtendedRange`) renders
    /// into this instead: half floats, linear Display P3 as every pass writes it, its values above
    /// 1 shown brighter than white where the screen has the headroom. Offscreen pictures never
    /// use it.
    static let extendedFormat: MTLPixelFormat = .rgba16Float
    /// The outline coverage target: the ink's opacity (r) and the share of it in the light tone
    /// (g, writing over a dark paint).
    static let outlineFormat: MTLPixelFormat = .rg16Float

    let device: any MTLDevice
    let queue: any MTLCommandQueue
    let sampleCount: Int
    let atlas: DigitAtlas
    let atlasTexture: any MTLTexture
    /// The shaders, for a mode's own pipelines (`makePipeline`).
    let library: any MTLLibrary

    let outlinePipeline: any MTLRenderPipelineState
    /// The color pass's pipelines in `colorFormat`.
    private let standard: Pipelines
    /// The same in `extendedFormat`, made the first time a canvas asks for them.
    private let extended = OSAllocatedUnfairLock<Pipelines?>(initialState: nil)

    /// Warms up the device, pipelines and atlas off the main thread so the first canvas
    /// opens instantly.
    static func prewarm() {
        Task.detached(priority: .userInitiated) { _ = RenderContext.shared }
    }

    /// `shared`, waited for off the caller's thread. Making it compiles the pipelines and waits on
    /// the GPU, which on a busy device (CI's simulator) has taken long enough that a canvas made
    /// on the main thread before then stopped the app answering; the painting screen awaits this
    /// before it shows one.
    @concurrent
    static func ready() async -> RenderContext? { shared }

    private init?() {
        let start = ContinuousClock.now
        defer { Log.canvas.notice("Making the render context took \(String(describing: ContinuousClock.now - start), privacy: .public)") }
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let library = try? device.makeDefaultLibrary(bundle: Bundle(for: RenderContext.self)),
              let atlas = DigitAtlas.make()
        else { return nil }
        self.device = device
        self.queue = queue
        self.atlas = atlas
        self.library = library
        let samples = device.supportsTextureSampleCount(4) ? 4 : 1
        sampleCount = samples

        guard let standard = Pipelines(library: library, device: device, format: RenderContext.colorFormat, samples: samples),
              let outline = Self.pipeline(
                library, device, "outlineVertex", "outlineFragment", format: RenderContext.outlineFormat, samples: 1, blend: .max),
              let texture = RenderContext.upload(atlas: atlas, device: device, queue: queue)
        else { return nil }
        self.standard = standard
        outlinePipeline = outline
        atlasTexture = texture
    }

    /// The color pass's pipelines for one pixel format.
    nonisolated struct Pipelines: @unchecked Sendable {
        let paper, fill, composite, glyph, brush, photo: any MTLRenderPipelineState

        init?(library: any MTLLibrary, device: any MTLDevice, format f: MTLPixelFormat, samples n: Int) {
            func make(_ vertex: String, _ fragment: String, _ blend: Blend) -> (any MTLRenderPipelineState)? {
                RenderContext.pipeline(library, device, vertex, fragment, format: f, samples: n, blend: blend)
            }
            guard let paper = make("canvasRectVertex", "paperFragment", .premultiplied),
                  let fill = make("fillVertex", "fillFragment", .none),
                  let composite = make("canvasRectVertex", "outlineCompositeFragment", .premultiplied),
                  let glyph = make("glyphVertex", "glyphFragment", .premultiplied),
                  let brush = make("brushVertex", "brushFragment", .premultiplied),
                  let photo = make("canvasRectVertex", "photoFragment", .premultiplied)
            else { return nil }
            self.paper = paper
            self.fill = fill
            self.composite = composite
            self.glyph = glyph
            self.brush = brush
            self.photo = photo
        }
    }

    /// The pipelines that draw into `format`: `colorFormat`'s, or `extendedFormat`'s (made once,
    /// on first use; a mode that wants them makes them off the main actor with
    /// `prepareExtendedRange`). Nil for a format nothing draws into, or extended pipelines
    /// Metal wouldn't make: the canvas then stays within white (`hasExtendedRange`).
    func pipelines(for format: MTLPixelFormat) -> Pipelines? {
        if format == Self.colorFormat { return standard }
        guard format == Self.extendedFormat else { return nil }
        return extended.withLock { made in
            if made == nil { made = Pipelines(library: library, device: device, format: format, samples: sampleCount) }
            return made
        }
    }

    /// Makes the extended range's pipelines now, so the first frame that asks has them at hand.
    func prepareExtendedRange() { _ = pipelines(for: Self.extendedFormat) }

    /// Whether the canvas can draw past white at all (its pipelines made).
    var hasExtendedRange: Bool { pipelines(for: Self.extendedFormat) != nil }

    fileprivate static func pipeline(
        _ library: any MTLLibrary, _ device: any MTLDevice, _ vertex: String, _ fragment: String,
        format: MTLPixelFormat, samples: Int, blend: Blend
    ) -> (any MTLRenderPipelineState)? {
        let d = MTLRenderPipelineDescriptor()
        d.vertexFunction = library.makeFunction(name: vertex)
        d.fragmentFunction = library.makeFunction(name: fragment)
        d.rasterSampleCount = samples
        let c = d.colorAttachments[0]!
        c.pixelFormat = format
        switch blend {
        case .none:
            c.isBlendingEnabled = false
        case .premultiplied:
            c.isBlendingEnabled = true
            c.rgbBlendOperation = .add
            c.alphaBlendOperation = .add
            c.sourceRGBBlendFactor = .one
            c.sourceAlphaBlendFactor = .one
            c.destinationRGBBlendFactor = .oneMinusSourceAlpha
            c.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        case .max:
            c.isBlendingEnabled = true
            c.rgbBlendOperation = .max
            c.alphaBlendOperation = .max
            c.sourceRGBBlendFactor = .one
            c.sourceAlphaBlendFactor = .one
            c.destinationRGBBlendFactor = .one
            c.destinationAlphaBlendFactor = .one
        }
        return try? device.makeRenderPipelineState(descriptor: d)
    }

    nonisolated fileprivate enum Blend { case none, premultiplied, max }

    /// A pipeline drawing into the canvas's color pass, for a mode (`CanvasMode`): `vertex` and
    /// `fragment` name functions of `Shaders.metal`; `blends` premultiplied over what is drawn,
    /// else it replaces it; `format` the target's (`CanvasModeFrame.format`).
    func makePipeline(
        vertex: String, fragment: String, blends: Bool, format: MTLPixelFormat = RenderContext.colorFormat
    ) -> (any MTLRenderPipelineState)? {
        let d = MTLRenderPipelineDescriptor()
        d.vertexFunction = library.makeFunction(name: vertex)
        d.fragmentFunction = library.makeFunction(name: fragment)
        d.rasterSampleCount = sampleCount
        let c = d.colorAttachments[0]!
        c.pixelFormat = format
        c.isBlendingEnabled = blends
        if blends {
            c.rgbBlendOperation = .add
            c.alphaBlendOperation = .add
            c.sourceRGBBlendFactor = .one
            c.sourceAlphaBlendFactor = .one
            c.destinationRGBBlendFactor = .oneMinusSourceAlpha
            c.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        }
        return try? device.makeRenderPipelineState(descriptor: d)
    }

    /// Private textures work on every GPU (including the simulator); upload via a blit.
    private static func upload(atlas: DigitAtlas, device: any MTLDevice, queue: any MTLCommandQueue) -> (any MTLTexture)? {
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r8Unorm, width: atlas.width, height: atlas.height, mipmapped: false)
        desc.usage = .shaderRead
        desc.storageMode = .private
        let rowBytes = (atlas.width + 255) / 256 * 256
        var staged = [UInt8](repeating: 0, count: rowBytes * atlas.height)
        for y in 0..<atlas.height {
            for x in 0..<atlas.width { staged[y * rowBytes + x] = atlas.pixels[y * atlas.width + x] }
        }
        guard let texture = device.makeTexture(descriptor: desc),
              let buffer = device.makeBuffer(bytes: staged, length: staged.count, options: .storageModeShared),
              let commands = queue.makeCommandBuffer(),
              let blit = commands.makeBlitCommandEncoder()
        else { return nil }
        blit.copy(
            from: buffer, sourceOffset: 0, sourceBytesPerRow: rowBytes, sourceBytesPerImage: staged.count,
            sourceSize: MTLSize(width: atlas.width, height: atlas.height, depth: 1),
            to: texture, destinationSlice: 0, destinationLevel: 0, destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
        blit.endEncoding()
        commands.commit()
        commands.waitUntilCompleted()
        return texture
    }

    /// The source photo as a mipmapped texture for the photo overlay. Drawn into Display P3
    /// with the sRGB curve, so sampling the `_srgb` texture yields linear P3 like every other
    /// canvas color; uploaded by blit into private storage. Waits for the GPU: call it off
    /// the main actor.
    func makePhotoTexture(_ image: CGImage) -> (any MTLTexture)? {
        let w = image.width, h = image.height
        guard w > 0, h > 0, let space = CGColorSpace(name: CGColorSpace.displayP3) else { return nil }
        let rowBytes = (w * 4 + 255) / 256 * 256
        guard let staging = device.makeBuffer(length: rowBytes * h, options: .storageModeShared),
              let bitmap = CGContext(
                data: staging.contents(), width: w, height: h, bitsPerComponent: 8, bytesPerRow: rowBytes,
                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        // Row 0 in memory is the photo's top row, matching canvas +y down.
        bitmap.interpolationQuality = .high
        bitmap.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm_srgb, width: w, height: h, mipmapped: true)
        desc.usage = .shaderRead
        desc.storageMode = .private
        guard let texture = device.makeTexture(descriptor: desc),
              let commands = queue.makeCommandBuffer(),
              let blit = commands.makeBlitCommandEncoder()
        else { return nil }
        blit.copy(
            from: staging, sourceOffset: 0, sourceBytesPerRow: rowBytes, sourceBytesPerImage: rowBytes * h,
            sourceSize: MTLSize(width: w, height: h, depth: 1),
            to: texture, destinationSlice: 0, destinationLevel: 0, destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
        blit.generateMipmaps(for: texture)
        blit.endEncoding()
        commands.commit()
        commands.waitUntilCompleted()
        return commands.status == .completed ? texture : nil
    }

    // MARK: Render targets

    func makeColorTarget(width: Int, height: Int) -> (any MTLTexture)? {
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Self.colorFormat, width: width, height: height, mipmapped: false)
        d.usage = [.renderTarget, .shaderRead]
        d.storageMode = .private
        return device.makeTexture(descriptor: d)
    }

    /// The multisampled color target, in `format` (the color target's); memoryless on device (it
    /// never leaves tile memory).
    func makeMultisampleTarget(width: Int, height: Int, format: MTLPixelFormat = RenderContext.colorFormat) -> (any MTLTexture)? {
        guard sampleCount > 1 else { return nil }
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: width, height: height, mipmapped: false)
        d.textureType = .type2DMultisample
        d.sampleCount = sampleCount
        d.usage = .renderTarget
        #if targetEnvironment(simulator)
        d.storageMode = .private
        #else
        d.storageMode = .memoryless
        #endif
        return device.makeTexture(descriptor: d)
    }

    func makeOutlineTarget(width: Int, height: Int) -> (any MTLTexture)? {
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Self.outlineFormat, width: width, height: height, mipmapped: false)
        d.usage = [.renderTarget, .shaderRead]
        d.storageMode = .private
        return device.makeTexture(descriptor: d)
    }

    // MARK: Encoding

    nonisolated struct Targets {
        /// Final color (drawable or offscreen texture).
        var color: any MTLTexture
        var multisample: (any MTLTexture)?
        var outlines: any MTLTexture
    }

    nonisolated struct Content {
        var outlines = true
        var numbers = true
        var brush = false
        /// Margin around the paper for the drop shadow, in px (0 = no shadow).
        var shadowMargin: Float = 0
        var clear = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        /// The source photo, drawn over everything but the brush at `uniforms.photo.x`.
        var photo: (any MTLTexture)? = nil
        /// A mode drawing the painting in place of its own look (`CanvasMode`); nil draws as ever.
        var mode: (any CanvasMode)? = nil
        /// How many times brighter than white the screen can show now (`ExtendedRange`), for a
        /// mode drawing into `extendedFormat`; 1 everywhere else.
        var headroom: Float = 1
    }

    /// The sheet's pixels in the target (`CanvasUniforms`: canvas units times `transform.z` plus
    /// `transform.xy`, the target `viewport.xy`), or nil when none of it is in the target.
    static func sheetScissor(_ u: CanvasUniforms) -> MTLScissorRect? {
        let targetWidth = Double(u.viewport.x), targetHeight = Double(u.viewport.y)
        let scale = Double(u.transform.z)
        let left = Double(u.transform.x), top = Double(u.transform.y)
        let x0 = max(0, left.rounded(.down)), y0 = max(0, top.rounded(.down))
        let x1 = min(targetWidth, (left + Double(u.viewport.z) * scale).rounded(.up))
        let y1 = min(targetHeight, (top + Double(u.viewport.w) * scale).rounded(.up))
        guard [x0, y0, x1, y1].allSatisfy(\.isFinite), x1 > x0, y1 > y0 else { return nil }
        return MTLScissorRect(x: Int(x0), y: Int(y0), width: Int(x1 - x0), height: Int(y1 - y0))
    }

    /// Encodes one frame: outline coverage (RG16F, max blending), then a single multisampled
    /// pass with paper + shadow, all fills in one indexed draw, the outline composite, the
    /// numbers, the source photo while it shows and the brush. A mode (`content.mode`) prepares
    /// first, draws the paint in place of the fills, may leave out the outlines and the numbers,
    /// and draws its light before the brush.
    func encode(
        _ commands: any MTLCommandBuffer, scene: CanvasScene, states: any MTLBuffer,
        uniforms: CanvasUniforms, targets: Targets, content: Content
    ) {
        var u = uniforms
        let uniformSize = MemoryLayout<CanvasUniforms>.stride
        let mode = content.mode
        let format = targets.color.pixelFormat
        guard let p = pipelines(for: format) else { return }
        func frame() -> CanvasModeFrame {
            CanvasModeFrame(context: self, scene: scene, states: states, uniforms: u, format: format, headroom: content.headroom)
        }
        let drawOutlines = content.outlines && scene.segmentCount > 0 && mode?.drawsOutlines != false
        mode?.prepare(commands, frame: frame())

        if drawOutlines {
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = targets.outlines
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].storeAction = .store
            pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
            if let enc = commands.makeRenderCommandEncoder(descriptor: pass) {
                enc.label = "Outline coverage"
                enc.setRenderPipelineState(outlinePipeline)
                enc.setVertexBuffer(scene.points, offset: 0, index: 0)
                enc.setVertexBuffer(scene.segments, offset: 0, index: 1)
                enc.setVertexBuffer(scene.lineRegions, offset: 0, index: 2)
                enc.setVertexBuffer(states, offset: 0, index: 3)
                enc.setVertexBuffer(scene.regionColors, offset: 0, index: 4)
                enc.setVertexBytes(&u, length: uniformSize, index: 5)
                enc.setVertexBuffer(scene.lineLayers, offset: 0, index: 6)
                enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: scene.segmentCount)
                enc.endEncoding()
            }
        }

        let pass = MTLRenderPassDescriptor()
        let color = pass.colorAttachments[0]!
        if let msaa = targets.multisample {
            color.texture = msaa
            color.resolveTexture = targets.color
            color.storeAction = .multisampleResolve
        } else {
            color.texture = targets.color
            color.storeAction = .store
        }
        color.loadAction = .clear
        color.clearColor = content.clear
        guard let enc = commands.makeRenderCommandEncoder(descriptor: pass) else { return }
        enc.label = "Canvas"

        var margin = content.shadowMargin
        enc.setRenderPipelineState(p.paper)
        enc.setVertexBytes(&u, length: uniformSize, index: 0)
        enc.setVertexBytes(&margin, length: MemoryLayout<Float>.size, index: 1)
        enc.setFragmentBytes(&u, length: uniformSize, index: 0)
        enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)

        // The paint keeps to the sheet: an area's smoothed edge along the picture's border can bow
        // past it, and the paint showed beyond the sheet's top as a ragged edge (Paul, November 10).
        let sheet = Self.sheetScissor(u)
        if let mode, let sheet {
            enc.setScissorRect(sheet)
            mode.drawPaint(enc, frame: frame())
            enc.setScissorRect(MTLScissorRect(x: 0, y: 0, width: Int(u.viewport.x), height: Int(u.viewport.y)))
        } else if scene.indexCount > 0, let sheet {
            enc.setScissorRect(sheet)
            enc.setRenderPipelineState(p.fill)
            enc.setVertexBuffer(scene.positions, offset: 0, index: 0)
            enc.setVertexBuffer(scene.vertexRegions, offset: 0, index: 1)
            enc.setVertexBytes(&u, length: uniformSize, index: 2)
            enc.setFragmentBuffer(scene.regionColors, offset: 0, index: 0)
            enc.setFragmentBuffer(states, offset: 0, index: 1)
            enc.setFragmentBytes(&u, length: uniformSize, index: 2)
            enc.drawIndexedPrimitives(
                type: .triangle, indexCount: scene.indexCount, indexType: .uint32,
                indexBuffer: scene.indices, indexBufferOffset: 0)
            enc.setScissorRect(MTLScissorRect(x: 0, y: 0, width: Int(u.viewport.x), height: Int(u.viewport.y)))
        }

        if drawOutlines {
            // Outlines on the sheet's border reach past it.
            var outlineOverhang: Float = 2
            enc.setRenderPipelineState(p.composite)
            enc.setVertexBytes(&u, length: uniformSize, index: 0)
            enc.setVertexBytes(&outlineOverhang, length: MemoryLayout<Float>.size, index: 1)
            enc.setFragmentTexture(targets.outlines, index: 0)
            enc.setFragmentBytes(&u, length: uniformSize, index: 0)
            enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }

        if content.numbers && scene.glyphCount > 0 && mode?.drawsNumbers != false {
            enc.setRenderPipelineState(p.glyph)
            enc.setVertexBuffer(scene.glyphs, offset: 0, index: 0)
            enc.setVertexBuffer(scene.digitRects, offset: 0, index: 1)
            enc.setVertexBuffer(scene.digitUVs, offset: 0, index: 2)
            enc.setVertexBuffer(states, offset: 0, index: 3)
            enc.setVertexBuffer(scene.regionColors, offset: 0, index: 4)
            enc.setVertexBytes(&u, length: uniformSize, index: 5)
            enc.setFragmentTexture(atlasTexture, index: 0)
            enc.setFragmentBytes(&u, length: uniformSize, index: 0)
            enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: scene.glyphCount)
        }

        if let photo = content.photo, u.photo.x > 0 {
            var photoMargin: Float = 0
            enc.setRenderPipelineState(p.photo)
            enc.setVertexBytes(&u, length: uniformSize, index: 0)
            enc.setVertexBytes(&photoMargin, length: MemoryLayout<Float>.size, index: 1)
            enc.setFragmentTexture(photo, index: 0)
            enc.setFragmentBytes(&u, length: uniformSize, index: 0)
            enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }

        mode?.drawOver(enc, frame: frame())

        if content.brush {
            enc.setRenderPipelineState(p.brush)
            enc.setVertexBytes(&u, length: uniformSize, index: 0)
            enc.setFragmentBytes(&u, length: uniformSize, index: 0)
            enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }
        enc.endEncoding()
    }
}
