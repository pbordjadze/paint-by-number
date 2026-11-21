#if UNRELEASED
import Foundation
import Metal
import PaintCore
import QuartzCore
import os
import simd

/// The cave's uniforms, as `CaveShader`'s `CaveUniforms` reads them.
struct CaveUniforms {
    var view: SIMD4<Float>
    var torch: SIMD4<Float>
    var lamp: SIMD4<Float>
    var mouth: SIMD4<Float>
    var misc: SIMD4<Float>
    var slotsA: SIMD4<Int32>
    var slotsB: SIMD4<Int32>
}

/// One thing in the air over the wall, as `CaveShader`'s `Sprite` reads it.
struct CaveSprite {
    enum Kind: Float {
        case glow = 0, dot = 1, stick = 2
    }

    var place: SIMD4<Float>
    var axis: SIMD4<Float>
    var inner: SIMD4<Float>
    var outer: SIMD4<Float>

    /// A circle or an ellipse `radii` wide, turned by `angle`.
    init(_ kind: Kind, at centre: SIMD2<Float>, radii: SIMD2<Float>, angle: Float = 0, inner: SIMD4<Float>, outer: SIMD4<Float>? = nil) {
        let c = cos(angle), s = sin(angle)
        place = SIMD4(centre.x, centre.y, c * radii.x, s * radii.x)
        axis = SIMD4(-s * radii.y, c * radii.y, kind.rawValue, 0)
        self.inner = inner
        self.outer = outer ?? inner
    }
}

/// The pipelines, made once from `CaveShader`'s source (on first use, off the main thread).
nonisolated final class CaveRenderContext: @unchecked Sendable {
    let device: any MTLDevice
    let queue: any MTLCommandQueue
    let wall: any MTLRenderPipelineState
    let sprites: any MTLRenderPipelineState
    static let format: MTLPixelFormat = .bgra8Unorm

    @concurrent
    static func make() async -> CaveRenderContext? {
        do {
            return try CaveRenderContext()
        } catch {
            Log.canvas.error("The cave's shaders failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    init() throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { throw CaveRenderError.noDevice }
        let options = MTLCompileOptions()
        options.mathMode = .fast
        let library = try device.makeLibrary(source: CaveShader.source, options: options)
        let wall = MTLRenderPipelineDescriptor()
        wall.vertexFunction = library.makeFunction(name: "caveWallVertex")
        wall.fragmentFunction = library.makeFunction(name: "caveWall")
        wall.colorAttachments[0].pixelFormat = Self.format
        let sprite = MTLRenderPipelineDescriptor()
        sprite.vertexFunction = library.makeFunction(name: "caveSpriteVertex")
        sprite.fragmentFunction = library.makeFunction(name: "caveSprite")
        let c = sprite.colorAttachments[0]!
        c.pixelFormat = Self.format
        c.isBlendingEnabled = true
        c.rgbBlendOperation = .add
        c.alphaBlendOperation = .add
        c.sourceRGBBlendFactor = .one
        c.sourceAlphaBlendFactor = .one
        c.destinationRGBBlendFactor = .oneMinusSourceAlpha
        c.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        self.device = device
        self.queue = queue
        self.wall = try device.makeRenderPipelineState(descriptor: wall)
        sprites = try device.makeRenderPipelineState(descriptor: sprite)
    }
}

nonisolated enum CaveRenderError: Error {
    case noDevice
    case noTexture
}

/// Draws the cave into a `CAMetalLayer`: the wall's bays held in three textures of
/// `CaveShader.slots` slots each (relief, rock, pigment; a bay in slot `bay % slots`), the wall
/// pass over the whole screen, then the sprites. Up to three frames in flight, each with its own
/// sprite buffer.
final class CaveRenderer {
    static let framesInFlight = 3
    static let maxSprites = 1024

    let context: CaveRenderContext
    private let relief: any MTLTexture
    private let rock: any MTLTexture
    private let pigment: any MTLTexture
    private let spriteBuffers: [any MTLBuffer]
    private var frame = 0
    private let inFlight = DispatchSemaphore(value: CaveRenderer.framesInFlight)
    /// The bay each slot holds, -1 for none.
    private(set) var held = [Int](repeating: -1, count: CaveShader.slots)

    init(context: CaveRenderContext) throws {
        self.context = context
        let slots = CaveShader.slots
        func texture(_ format: MTLPixelFormat, width: Int, height: Int) throws -> any MTLTexture {
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: width, height: height, mipmapped: false)
            d.usage = .shaderRead
            d.storageMode = .shared
            guard let t = context.device.makeTexture(descriptor: d) else { throw CaveRenderError.noTexture }
            return t
        }
        relief = try texture(.r16Float, width: CaveWall.mapWidth * slots, height: CaveWall.mapHeight)
        rock = try texture(.rgba8Unorm, width: CaveWall.mapWidth * slots, height: CaveWall.mapHeight)
        pigment = try texture(.rgba8Unorm, width: CavePigmentLayer.width * slots, height: CavePigmentLayer.height)
        var buffers: [any MTLBuffer] = []
        for _ in 0..<Self.framesInFlight {
            guard let b = context.device.makeBuffer(length: MemoryLayout<CaveSprite>.stride * Self.maxSprites, options: .storageModeShared)
            else { throw CaveRenderError.noTexture }
            buffers.append(b)
        }
        spriteBuffers = buffers
    }

    /// Puts a bay's maps in its slot. The slot's earlier bay is off screen by then (slots hold a
    /// screen and more either side), so no frame in flight is reading it.
    func hold(_ maps: CaveBay.Maps, relief half: [Float16]) {
        let slot = maps.index % CaveShader.slots
        let w = maps.width, h = maps.height
        guard half.count == w * h, maps.rock.count == w * h * 4 else { return }
        half.withUnsafeBytes { bytes in
            relief.replace(region: MTLRegionMake2D(slot * w, 0, w, h), mipmapLevel: 0, withBytes: bytes.baseAddress!, bytesPerRow: w * 2)
        }
        maps.rock.withUnsafeBytes { bytes in
            rock.replace(region: MTLRegionMake2D(slot * w, 0, w, h), mipmapLevel: 0, withBytes: bytes.baseAddress!, bytesPerRow: w * 4)
        }
        held[slot] = maps.index
    }

    /// The relief as the texture holds it: half floats, which every Apple GPU filters (heights
    /// run about -0.6 to 1.5). Made off the main thread with the maps.
    nonisolated static func halfRelief(_ maps: CaveBay.Maps) -> [Float16] {
        maps.relief.map { Float16($0) }
    }

    /// Writes a rectangle of a bay's pigment (RGBA8, `rect`'s size), or clears all of it.
    func paint(bay: Int, rgba: [UInt8]?, minX: Int = 0, minY: Int = 0, width: Int = CavePigmentLayer.width, height: Int = CavePigmentLayer.height) {
        let slot = bay % CaveShader.slots
        let bytes = rgba ?? [UInt8](repeating: 0, count: width * height * 4)
        guard bytes.count == width * height * 4 else { return }
        bytes.withUnsafeBytes { raw in
            pigment.replace(region: MTLRegionMake2D(slot * CavePigmentLayer.width + minX, minY, width, height), mipmapLevel: 0,
                            withBytes: raw.baseAddress!, bytesPerRow: width * 4)
        }
    }

    /// Renders a frame into the layer's next drawable; false when none could be had this tick.
    @discardableResult
    func draw(in layer: CAMetalLayer, uniforms: CaveUniforms, sprites: [CaveSprite]) -> Bool {
        guard layer.drawableSize.width > 0, layer.drawableSize.height > 0 else { return false }
        guard inFlight.wait(timeout: .now() + .milliseconds(2)) == .success else { return false }
        guard let drawable = layer.nextDrawable(), let commands = context.queue.makeCommandBuffer() else {
            inFlight.signal()
            return false
        }
        frame = (frame + 1) % Self.framesInFlight
        var u = uniforms
        u.slotsA = SIMD4(Int32(held[0]), Int32(held[1]), Int32(held[2]), Int32(held[3]))
        u.slotsB = SIMD4(Int32(held[4]), Int32(held[5]), -1, -1)
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = commands.makeRenderCommandEncoder(descriptor: pass) else {
            inFlight.signal()
            return false
        }
        encoder.setRenderPipelineState(context.wall)
        encoder.setFragmentBytes(&u, length: MemoryLayout<CaveUniforms>.stride, index: 0)
        encoder.setFragmentTexture(relief, index: 0)
        encoder.setFragmentTexture(rock, index: 1)
        encoder.setFragmentTexture(pigment, index: 2)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        let count = min(sprites.count, Self.maxSprites)
        if count > 0 {
            let buffer = spriteBuffers[frame]
            sprites.withUnsafeBytes { raw in
                buffer.contents().copyMemory(from: raw.baseAddress!, byteCount: MemoryLayout<CaveSprite>.stride * count)
            }
            encoder.setRenderPipelineState(context.sprites)
            encoder.setVertexBuffer(buffer, offset: 0, index: 0)
            encoder.setVertexBytes(&u, length: MemoryLayout<CaveUniforms>.stride, index: 1)
            encoder.setFragmentBytes(&u, length: MemoryLayout<CaveUniforms>.stride, index: 0)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: count)
        }
        encoder.endEncoding()
        commands.addCompletedHandler(Self.signal(inFlight))
        commands.present(drawable)
        commands.commit()
        return true
    }

    /// Built outside the main actor: Metal calls it on its own completion thread.
    nonisolated private static func signal(_ semaphore: DispatchSemaphore) -> MTLCommandBufferHandler {
        { _ in semaphore.signal() }
    }
}
#endif
