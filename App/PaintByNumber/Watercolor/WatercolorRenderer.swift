#if UNRELEASED
import CoreGraphics
import Foundation
import Metal
import MetalKit
import PaintCore
import QuartzCore
import os

/// What the sheet is drawn with besides the simulation, made once a painting off the main actor:
/// the pencil (the template's drawing, and a fainter line round every area so an area without one
/// still shows its edge), the numbers, each canvas unit's area and the paper's fine tooth.
nonisolated struct WatercolorAssets: Sendable {
    var pencil: [UInt8]
    var numbers: [UInt8]
    var rasterWidth: Int
    var rasterHeight: Int
    var paper: [Float16]
    var paperWidth: Int
    var paperHeight: Int

    /// The pencil and numbers at about twice the canvas, up to 3072 pixels on the long side.
    static func make(template t: Template, sheet: WatercolorSheet) -> WatercolorAssets {
        let long = max(t.width, t.height, 1)
        let side = min(3072, long * 2)
        let size = TemplateRasterizer.pixelSize(of: t, maxPixelSize: side)
        var drawing = TemplateRasterizer.Style()
        drawing.outlineWidth = 0
        drawing.numbers = false
        drawing.lineWeight = .regular
        var pencil = coverage(TemplateRasterizer.image(t, style: drawing, maxPixelSize: side), size: size)
        // Every area's edge, faint: a coloring book draws only its drawing, and a wash needs to
        // know where its area ends.
        let map = t.regionMap
        let sx = Float(map.width) / Float(size.width), sy = Float(map.height) / Float(size.height)
        func region(_ x: Int, _ y: Int) -> UInt32 {
            map[min(map.width - 1, Int((Float(x) + 0.5) * sx)), min(map.height - 1, Int((Float(y) + 0.5) * sy))]
        }
        for y in 0..<(size.height - 1) {
            for x in 0..<(size.width - 1) {
                let here = region(x, y)
                if here != region(x + 1, y) || here != region(x, y + 1) {
                    pencil[y * size.width + x] = max(pencil[y * size.width + x], 110)
                }
            }
        }
        var numbered = TemplateRasterizer.Style()
        numbered.outlineWidth = 0
        numbered.numbers = true
        numbered.drawsDrawing = false
        numbered.numberColor = SIMD4(0, 0, 0, 1)
        let numbers = coverage(TemplateRasterizer.image(t, style: numbered, maxPixelSize: side), size: size)
        let pw = sheet.width * 2, ph = sheet.height * 2
        let fine = WatercolorSheet.paperHeight(width: pw, height: ph, seed: sheet.seed &+ 11)
        return WatercolorAssets(pencil: pencil, numbers: numbers, rasterWidth: size.width, rasterHeight: size.height,
                                paper: fine.map { Float16($0) }, paperWidth: pw, paperHeight: ph)
    }

    /// How dark each pixel of `image` is, 0 on white paper to 255 at its darkest ink.
    private static func coverage(_ image: CGImage?, size: (width: Int, height: Int)) -> [UInt8] {
        var gray = [UInt8](repeating: 255, count: size.width * size.height)
        if let image {
            gray.withUnsafeMutableBytes { buffer in
                guard let ctx = CGContext(
                    data: buffer.baseAddress, width: size.width, height: size.height, bitsPerComponent: 8,
                    bytesPerRow: size.width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
                else { return }
                ctx.setFillColor(gray: 1, alpha: 1)
                ctx.fill(CGRect(x: 0, y: 0, width: size.width, height: size.height))
                ctx.draw(image, in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
            }
        }
        let darkest = gray.min() ?? 0
        let span = Float(max(255 - Int(darkest), 1))
        return gray.map { UInt8(min(255, Float(255 - Int($0)) / span * 255)) }
    }
}

/// Mirrors `WatercolorUniforms` in Watercolor.metal: change both in the same order.
struct WatercolorUniforms {
    var offset: SIMD2<Float>
    var unitsPerPixel: Float
    var time: Float
    var canvasSize: SIMD2<Float>
    var paperTexel: SIMD2<Float>
    var simTexel: SIMD2<Float>
    var pad: SIMD2<Float> = .zero
    var paper: SIMD4<Float>
    var background: SIMD4<Float>
    var numberInk: SIMD4<Float>
}

/// Mirrors `WatercolorRegion` in Watercolor.metal.
struct WatercolorRegion {
    var gain: SIMD4<Float>
    var aim: SIMD4<Float>
}

/// Draws a `WatercolorPainting` with Metal: steps its simulation by the frame's time, sends what
/// changed to the GPU (the pigment and water of the cells stepped, the target solve of the areas
/// they touch) and draws the sheet in one pass (Watercolor.metal). Only while something is wet or
/// a number is fading does it draw every frame; otherwise it waits to be asked (a pan, a zoom).
@MainActor
final class WatercolorRenderer: NSObject, MTKViewDelegate {
    let painting: WatercolorPainting
    let device: any MTLDevice
    private let queue: any MTLCommandQueue
    private let pipeline: any MTLRenderPipelineState
    private let density: any MTLTexture
    private let granulation: any MTLTexture
    private let labels: any MTLTexture
    private let paper: any MTLTexture
    private let pencil: any MTLTexture
    private let numbers: any MTLTexture
    private let regions: any MTLBuffer
    /// One frame on the GPU at a time: its textures are written in place.
    private let inFlight = DispatchSemaphore(value: 1)
    private var lastFrame: CFTimeInterval?
    private var halfBuffer: [Float16] = []
    private var stepTimes: [Double] = []
    /// The time between frames drawn while the sheet runs, for the report.
    private var frameIntervals: [Double] = []

    /// Canvas units at the view's top-left pixel, and per pixel (the canvas view's scroll).
    var offset = SIMD2<Float>(0, 0)
    var unitsPerPixel: Float = 1
    /// Around the sheet: `WatercolorEra.desk`, linear.
    var background = SIMD4<Float>(0.807, 0.768, 0.694, 1)
    /// Told when the sheet stops needing frames, or needs them again.
    var onActivity: ((Bool) -> Void)?

    static let colorFormat: MTLPixelFormat = .bgra8Unorm_srgb
    static let paperColor = SIMD4<Float>(WatercolorSheet.paperColor, 1)
    static let numberInk = SIMD4<Float>(0.19, 0.18, 0.2, 1)

    init?(painting: WatercolorPainting, assets: WatercolorAssets) {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue(),
              let library = try? device.makeDefaultLibrary(bundle: Bundle(for: WatercolorRenderer.self))
        else { return nil }
        let d = MTLRenderPipelineDescriptor()
        d.vertexFunction = library.makeFunction(name: "watercolor_vertex")
        d.fragmentFunction = library.makeFunction(name: "watercolor_fragment")
        d.colorAttachments[0].pixelFormat = Self.colorFormat
        guard let pipeline = try? device.makeRenderPipelineState(descriptor: d) else { return nil }
        let sheet = painting.sim.sheet
        let t = painting.template
        func texture(_ format: MTLPixelFormat, _ w: Int, _ h: Int, mipmapped: Bool = false) -> (any MTLTexture)? {
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: max(w, 1), height: max(h, 1), mipmapped: mipmapped)
            d.usage = .shaderRead
            d.storageMode = .shared
            return device.makeTexture(descriptor: d)
        }
        guard let density = texture(.rgba16Float, sheet.width, sheet.height),
              let granulation = texture(.r16Float, sheet.width, sheet.height),
              let labels = texture(.r32Uint, t.regionMap.width, t.regionMap.height),
              let paper = texture(.r16Float, assets.paperWidth, assets.paperHeight),
              let pencil = texture(.r8Unorm, assets.rasterWidth, assets.rasterHeight, mipmapped: true),
              let numbers = texture(.r8Unorm, assets.rasterWidth, assets.rasterHeight, mipmapped: true),
              let regions = device.makeBuffer(length: max(1, t.regions.count) * MemoryLayout<WatercolorRegion>.stride,
                                              options: .storageModeShared)
        else { return nil }
        self.painting = painting
        self.device = device
        self.queue = queue
        self.pipeline = pipeline
        self.density = density
        self.granulation = granulation
        self.labels = labels
        self.paper = paper
        self.pencil = pencil
        self.numbers = numbers
        self.regions = regions
        super.init()
        t.regionMap.storage.withUnsafeBytes { bytes in
            labels.replace(region: MTLRegionMake2D(0, 0, t.regionMap.width, t.regionMap.height), mipmapLevel: 0,
                           withBytes: bytes.baseAddress!, bytesPerRow: t.regionMap.width * 4)
        }
        assets.paper.withUnsafeBytes { bytes in
            paper.replace(region: MTLRegionMake2D(0, 0, assets.paperWidth, assets.paperHeight), mipmapLevel: 0,
                          withBytes: bytes.baseAddress!, bytesPerRow: assets.paperWidth * 2)
        }
        for (texture, bytes) in [(pencil, assets.pencil), (numbers, assets.numbers)] {
            bytes.withUnsafeBytes { raw in
                texture.replace(region: MTLRegionMake2D(0, 0, assets.rasterWidth, assets.rasterHeight), mipmapLevel: 0,
                                withBytes: raw.baseAddress!, bytesPerRow: assets.rasterWidth)
            }
        }
        if let commands = queue.makeCommandBuffer(), let blit = commands.makeBlitCommandEncoder() {
            blit.generateMipmaps(for: pencil)
            blit.generateMipmaps(for: numbers)
            blit.endEncoding()
            commands.commit()
            commands.waitUntilCompleted()
        }
        let all = WatercolorSim.Box(x0: 0, y0: 0, x1: sheet.width, y1: sheet.height)
        upload(all, regions: Array(0..<Int32(t.regions.count)))
        _ = painting.sim.takeChanges()
    }

    /// Whether the sheet needs a frame every display refresh: water moving, or a number fading.
    var needsFrames: Bool { painting.isRunning }

    // MARK: MTKViewDelegate

    nonisolated func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    nonisolated func draw(in view: MTKView) {
        MainActor.assumeIsolated { frame(in: view) }
    }

    private func frame(in view: MTKView) {
        let now = CACurrentMediaTime()
        if let lastFrame { frameIntervals.append(now - lastFrame) }
        let elapsed = lastFrame.map { min(now - $0, 0.1) } ?? Double(WatercolorSim.dt)
        lastFrame = now
        let wasActive = needsFrames
        inFlight.wait()
        _ = painting.advance(by: elapsed)
        // Settling at once, the sheet shows nothing of a wash until it is done (its changes keep).
        if !(painting.settlesAtOnce && painting.sim.isActive) {
            let changes = painting.sim.takeChanges()
            if let box = changes.box { upload(box, regions: changes.regions) } else if !changes.regions.isEmpty {
                upload(nil, regions: changes.regions)
            }
        }
        guard let pass = view.currentRenderPassDescriptor, let drawable = view.currentDrawable,
              let commands = queue.makeCommandBuffer()
        else {
            inFlight.signal()
            return
        }
        let size = SIMD2<Float>(Float(view.drawableSize.width), Float(view.drawableSize.height))
        encode(commands, pass: pass, size: size, offset: offset, unitsPerPixel: unitsPerPixel)
        commands.present(drawable)
        Self.signal(inFlight, when: commands)
        commands.commit()
        report()
        if wasActive != needsFrames || !needsFrames { onActivity?(needsFrames) }
    }

    /// Releases the frame's hold once the GPU is done with it (formed off the main actor: Metal
    /// calls back on its own thread).
    private nonisolated static func signal(_ semaphore: DispatchSemaphore, when commands: any MTLCommandBuffer) {
        commands.addCompletedHandler { _ in semaphore.signal() }
    }

    /// Starts the frame clock again after a pause, so the first frame steps no stale time.
    func resume() { lastFrame = nil }

    private func encode(_ commands: any MTLCommandBuffer, pass: MTLRenderPassDescriptor, size: SIMD2<Float>,
                        offset: SIMD2<Float>, unitsPerPixel: Float) {
        let t = painting.template
        let sheet = painting.sim.sheet
        var uniforms = WatercolorUniforms(
            offset: offset, unitsPerPixel: unitsPerPixel, time: painting.sim.time,
            canvasSize: SIMD2(Float(t.width), Float(t.height)),
            paperTexel: SIMD2(1 / Float(paper.width), 1 / Float(paper.height)),
            simTexel: SIMD2(1 / Float(sheet.width), 1 / Float(sheet.height)),
            paper: Self.paperColor, background: background, numberInk: Self.numberInk)
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = commands.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<WatercolorUniforms>.stride, index: 0)
        encoder.setFragmentBuffer(regions, offset: 0, index: 1)
        encoder.setFragmentTexture(density, index: 0)
        encoder.setFragmentTexture(granulation, index: 1)
        encoder.setFragmentTexture(labels, index: 2)
        encoder.setFragmentTexture(paper, index: 3)
        encoder.setFragmentTexture(pencil, index: 4)
        encoder.setFragmentTexture(numbers, index: 5)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }

    /// The cells of `box` (pigment, water, granulation) and the target solve of `regions`.
    private func upload(_ box: WatercolorSim.Box?, regions changed: [Int32]) {
        let sim = painting.sim
        let w = sim.sheet.width
        if let box, box.x1 > box.x0, box.y1 > box.y0 {
            let bw = box.x1 - box.x0, bh = box.y1 - box.y0
            if halfBuffer.count < bw * bh * 4 { halfBuffer = Array(repeating: 0, count: bw * bh * 4) }
            halfBuffer.withUnsafeMutableBufferPointer { out in
                for y in 0..<bh {
                    for x in 0..<bw {
                        let i = (box.y0 + y) * w + box.x0 + x
                        let d = sim.D[i] + 0.9 * sim.S[i]
                        let o = (y * bw + x) * 4
                        out[o] = Float16(d.x)
                        out[o + 1] = Float16(d.y)
                        out[o + 2] = Float16(d.z)
                        out[o + 3] = Float16(sim.W[i])
                    }
                }
                density.replace(region: MTLRegionMake2D(box.x0, box.y0, bw, bh), mipmapLevel: 0,
                                withBytes: out.baseAddress!, bytesPerRow: bw * 8)
                for y in 0..<bh {
                    for x in 0..<bw { out[y * bw + x] = Float16(sim.G[(box.y0 + y) * w + box.x0 + x]) }
                }
                granulation.replace(region: MTLRegionMake2D(box.x0, box.y0, bw, bh), mipmapLevel: 0,
                                    withBytes: out.baseAddress!, bytesPerRow: bw * 2)
            }
        }
        let states = regions.contents().bindMemory(to: WatercolorRegion.self, capacity: painting.regionCount)
        for r in changed where Int(r) < painting.regionCount {
            let target = sim.target(of: Int(r))
            let at = sim.paintedAt[Int(r)]
            states[Int(r)] = WatercolorRegion(gain: SIMD4(target.gain, at.isFinite ? at : 1e9), aim: SIMD4(target.aim, 0))
        }
    }

    /// A frame report to the log every few seconds of running: how long the simulation's steps
    /// took, and how far apart the frames came (`tools/perf-tour` reads such lines).
    private func report() {
        stepTimes.append(contentsOf: painting.takeStepTimes())
        guard stepTimes.count >= 240 else { return }
        func ms(_ values: [Double], _ q: Double) -> Double {
            guard !values.isEmpty else { return 0 }
            return values[min(values.count - 1, Int(Double(values.count) * q))] * 1000
        }
        let steps = stepTimes.sorted(), frames = frameIntervals.sorted()
        let late = frames.filter { $0 > 1.5 / 60 }.count
        Log.canvas.notice(
            "watercolor steps: median \(ms(steps, 0.5), format: .fixed(precision: 2)) ms, p95 \(ms(steps, 0.95), format: .fixed(precision: 2)) ms, max \(ms(steps, 1), format: .fixed(precision: 2)) ms over \(steps.count) steps; frames: median \(ms(frames, 0.5), format: .fixed(precision: 1)) ms, p95 \(ms(frames, 0.95), format: .fixed(precision: 1)) ms, max \(ms(frames, 1), format: .fixed(precision: 1)) ms, \(late) late of \(frames.count)")
        stepTimes.removeAll(keepingCapacity: true)
        frameIntervals.removeAll(keepingCapacity: true)
    }

    // MARK: Pictures

    /// The whole sheet as it stands, `maxPixelSize` on its long side (the shelf's picture).
    func picture(maxPixelSize: Int) -> CGImage? {
        let t = painting.template
        let scale = Float(maxPixelSize) / Float(max(t.width, t.height, 1))
        let w = max(1, Int((Float(t.width) * scale).rounded())), h = max(1, Int((Float(t.height) * scale).rounded()))
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Self.colorFormat, width: w, height: h, mipmapped: false)
        d.usage = [.renderTarget]
        d.storageMode = .shared
        guard let target = device.makeTexture(descriptor: d), let commands = queue.makeCommandBuffer() else { return nil }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        inFlight.wait()
        defer { inFlight.signal() }
        encode(commands, pass: pass, size: SIMD2(Float(w), Float(h)), offset: .zero, unitsPerPixel: 1 / scale)
        commands.commit()
        commands.waitUntilCompleted()
        // In the background iOS refuses GPU work: no picture rather than a black one.
        guard commands.status == .completed else { return nil }
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        bytes.withUnsafeMutableBytes { raw in
            target.getBytes(raw.baseAddress!, bytesPerRow: w * 4, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let space = CGColorSpace(name: CGColorSpace.displayP3)
        else { return nil }
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4, space: space,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}
#endif
