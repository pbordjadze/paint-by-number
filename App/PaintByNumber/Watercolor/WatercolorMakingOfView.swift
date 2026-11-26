#if UNRELEASED
import CoreGraphics
import Foundation
import Metal
import MetalKit
import Observation
import PaintCore
import QuartzCore
import SwiftUI
import UIKit

/// Watercolor's Making Of (painting-company row 373): the painting's paints tried on a study
/// sheet, fast, by the real simulation, before the painter paints. It shows off the water (a
/// flood running across dry paper, paints bleeding wet in wet, granulation, blooms, the drying)
/// and never the painting, which is the painter's to find (PaintCore's `WatercolorStudy`: the
/// sheet, the painting's size, numbered with its own numbers). PaintCore's `WatercolorMakingOf`
/// is the plan and the time-lapse clock; a simulation of its own steps off the main actor
/// (`WatercolorFilmPlayer`, `WatercolorFilm.produce`), sending what changed as frames to a
/// renderer of its own that draws with the painting screen's shader (Watercolor.metal). It ends
/// on the dried study, held a moment as the camera draws back, which is then set aside: it rises
/// and fades off the bare desk, and then the desk fades, uncovering the painting screen opening
/// beneath, whose bare sheet lies at the same place and scale.
///
/// Short and skippable rather than played over the template's making: the plan needs the
/// finished template, and the making uses every core. It plays about six seconds once the
/// template is made (`pbn watercolor --making-of` measures it) and a tap anywhere ends it at
/// once; the painting screen opens beneath it meanwhile, so it adds no wait. Reduce Motion
/// shows the study's bare sheet while the simulation runs unseen, then crossfades to the
/// finished study and away. VoiceOver skips it (`WatercolorEra.make`).
@MainActor
@Observable
final class WatercolorFilm {
    let template: Template
    @ObservationIgnored let renderer: WatercolorFilmRenderer
    @ObservationIgnored private let player: WatercolorFilmPlayer
    @ObservationIgnored private var producing: Task<Void, Never>?
    /// The finished study is on screen (all but a few damp patches dry).
    private(set) var isSettled = false
    /// The demo's held moment is on screen.
    private(set) var isHeld = false
    /// Every wash is laid and the sheet is drying: the film pushes in toward `focus`.
    private(set) var isDrying = false
    /// Where it pushes in: the first bloom, as a point of the sheet (0…1).
    let focus: UnitPoint
    /// The study's bare sheet with its numbers, as a picture: Reduce Motion's, under the
    /// crossfade.
    private(set) var bare: CGImage?
    /// A demo's moment to hold, seconds into the Making Of (Debug builds' scenario).
    @ObservationIgnored let hold: Double?

    private init(template: Template, renderer: WatercolorFilmRenderer, player: WatercolorFilmPlayer, hold: Double?) {
        self.template = template
        self.renderer = renderer
        self.player = player
        self.hold = hold
        let f = player.plan.focus ?? SIMD2(Float(template.width), Float(template.height)) / 2
        focus = UnitPoint(x: CGFloat(f.x) / CGFloat(max(template.width, 1)), y: CGFloat(f.y) / CGFloat(max(template.height, 1)))
        renderer.onFrame = { [weak self] frame in
            guard let self else { return }
            if frame.settled { isSettled = true }
            if frame.drying { isDrying = true }
            if hold != nil { isHeld = true }
        }
    }

    /// The painting's study sheet (`WatercolorStudy`, on paper of the painting's seed) and what
    /// it is drawn with, made off the main actor; nil without Metal or a study.
    static func prepare(template painting: Template, seed: UInt64, hold: Double? = nil) async -> WatercolorFilm? {
        let made: (WatercolorAssets, WatercolorFilmPlayer, WatercolorFilmFrame, Template)? = await Background.run {
            guard let study = try? WatercolorStudy(painting: painting) else { return nil }
            let template = study.template
            let sheet = WatercolorSheet(template: template, seed: seed)
            let player = WatercolorFilmPlayer(study: study, sheet: sheet)
            return (WatercolorAssets.make(template: template, sheet: sheet), player, player.everything(), template)
        }
        guard let made,
              let renderer = WatercolorFilmRenderer(template: made.3, sheet: made.1.sheet, assets: made.0, first: made.2)
        else { return nil }
        return WatercolorFilm(template: made.3, renderer: renderer, player: made.1, hold: hold)
    }

    /// Starts the simulation: paced to the time-lapse's clock, or, settling at once (Reduce
    /// Motion), as fast as it goes with only the finished painting sent.
    func start(settlingAtOnce: Bool) {
        guard producing == nil else { return }
        // Reduce Motion's alone: the film shows the study over the desk otherwise.
        if settlingAtOnce { bare = renderer.picture(maxPixelSize: 2048) }
        let mode: WatercolorFilmPlayer.Mode
        if let hold {
            mode = .hold(hold)
        } else {
            mode = settlingAtOnce ? .settleAtOnce : .paced
        }
        let player = player
        let renderer = renderer
        let (frames, sink) = AsyncStream.makeStream(of: WatercolorFilmFrame.self)
        producing = Task {
            async let made: Void = Self.produce(player, mode: mode, into: sink)
            for await frame in frames { renderer.receive(frame) }
            await made
        }
    }

    /// Stops the simulation (the Making Of has ended or was left).
    func stop() {
        producing?.cancel()
        producing = nil
    }

    /// The simulation's loop, off the main actor: steps to the clock's step, sends what changed,
    /// and waits for the next frame once caught up. A slow device shows the same film, slower.
    /// It steps on past settling, so the last damp patches dry while the film ends, and stops
    /// once the sheet is dry or it is cancelled.
    @concurrent
    nonisolated private static func produce(_ player: WatercolorFilmPlayer, mode: WatercolorFilmPlayer.Mode,
                                            into sink: AsyncStream<WatercolorFilmFrame>.Continuation) async {
        defer { sink.finish() }
        switch mode {
        case .hold(let seconds):
            player.play(to: player.plan.step(at: seconds), most: .max)
            sink.yield(player.frame())
        case .settleAtOnce:
            while !Task.isCancelled, !player.isSettled {
                player.play(to: player.sim.step + 30, most: 30)
            }
            if !Task.isCancelled { sink.yield(player.frame()) }
        case .paced:
            let clock = ContinuousClock()
            let start = clock.now
            while !Task.isCancelled, !player.isDry {
                let elapsed = (clock.now - start).components
                let shown = Double(elapsed.seconds) + Double(elapsed.attoseconds) * 1e-18
                let target = player.plan.step(at: shown)
                // A frame at least every few steps, however far behind a slow device falls.
                player.play(to: target, most: 8)
                player.follow(shown: shown)
                sink.yield(player.frame())
                if player.sim.step >= target {
                    guard (try? await Task.sleep(for: .milliseconds(12))) != nil else { return }
                }
            }
        }
    }
}

/// What a frame of the Making Of changed, packed off the main actor for the GPU: the cells
/// stepped (pigment and water as half floats, as `WatercolorRenderer` uploads them, and
/// granulation) and the target solve of the areas they touch.
nonisolated struct WatercolorFilmFrame: Sendable {
    var box: WatercolorSim.Box?
    var density: [Float16] = []
    var granulation: [Float16] = []
    var regions: [Int32] = []
    /// Per region of `regions`: the gain (w: when it was painted, or far off) and the aim.
    var gains: [SIMD4<Float>] = []
    var aims: [SIMD4<Float>] = []
    var time: Float = 0
    var settled = false
    /// Every tap laid: the drying.
    var drying = false
    /// How far the pencil has gone from under the painted areas (`WatercolorMakingOf.pencilFade`).
    var pencilFade: Float = 0
    /// Where the drying front stands (`WatercolorMakingOf.dryingFront`).
    var front: Float = -WatercolorMakingOf.frontWidth
}

/// The Making Of's own simulation and its plan, stepped by one task at a time
/// (`WatercolorFilm.produce`), never the main actor's.
nonisolated final class WatercolorFilmPlayer: @unchecked Sendable {
    enum Mode: Sendable {
        case paced
        case settleAtOnce
        case hold(Double)
    }

    let plan: WatercolorMakingOf
    let sim: WatercolorSim
    var sheet: WatercolorSheet { sim.sheet }
    private var cursor = 0
    private var settled = false
    /// The paced film's clock once the drying began: the seconds shown then, the simulation's
    /// time then, and the simulation time the clock has reached since (`follow`).
    private var dryingBegan: (shown: Double, time: Float)?
    private var clockTime: Float = 0

    /// Lets the drying front and the pencil follow the film's clock rather than the simulation,
    /// from the moment the last tap is laid: a device that can't step the drying as fast as the
    /// clock asks (an iPad Air managed about 300 steps a second of the 540 asked) sweeps the
    /// front in the planned time, the simulation's pigment under it catching up as it can. It
    /// begins where the simulation stands, so a flood that ran late never jumps the front.
    func follow(shown: Double) {
        guard plan.isDrying(sim) else { return }
        let began = dryingBegan ?? (shown, sim.time)
        dryingBegan = began
        let steps = plan.step(at: shown) - plan.step(at: began.shown)
        clockTime = began.time + Float(max(steps, 0)) * WatercolorSim.dt
    }

    /// The time the front and the pencil are drawn at: the simulation's, or the film's clock
    /// where it is ahead.
    private var filmTime: Float { max(sim.time, clockTime) }

    init(study: WatercolorStudy, sheet: WatercolorSheet) {
        plan = WatercolorMakingOf(study: study, sheet: sheet)
        sim = WatercolorSim(sheet: sheet)
        sim.roundedFronts = true
    }

    /// Steps toward `step`, at most `most` steps.
    func play(to step: Int, most: Int) {
        let to = most == .max ? step : min(step, sim.step + most)
        plan.play(sim, to: to, cursor: &cursor)
    }

    var isSettled: Bool {
        if !settled {
            settled = plan.isSettled(sim, cursor: cursor)
                || (cursor >= plan.log.taps.count && plan.dryingFront(at: filmTime) >= 1)
        }
        return settled
    }

    /// Every tap laid and nothing wet: nothing more will change.
    var isDry: Bool { cursor >= plan.log.taps.count && !sim.isActive }

    /// What changed since the last frame.
    func frame() -> WatercolorFilmFrame {
        let changes = sim.takeChanges()
        return pack(box: changes.box, regions: changes.regions)
    }

    /// The whole sheet, as it stands: the renderer's first upload.
    func everything() -> WatercolorFilmFrame {
        _ = sim.takeChanges()
        return pack(box: WatercolorSim.Box(x0: 0, y0: 0, x1: sheet.width, y1: sheet.height),
                    regions: Array(0..<Int32(sheet.regionCount)))
    }

    private func pack(box: WatercolorSim.Box?, regions: [Int32]) -> WatercolorFilmFrame {
        var frame = WatercolorFilmFrame(time: sim.time, settled: isSettled, drying: plan.isDrying(sim),
                                        pencilFade: plan.pencilFade(at: filmTime), front: plan.dryingFront(at: filmTime))
        let w = sheet.width
        if let box, box.x1 > box.x0, box.y1 > box.y0 {
            let bw = box.x1 - box.x0, bh = box.y1 - box.y0
            frame.box = box
            frame.density = [Float16](repeating: 0, count: bw * bh * 4)
            frame.granulation = [Float16](repeating: 0, count: bw * bh)
            frame.density.withUnsafeMutableBufferPointer { out in
                frame.granulation.withUnsafeMutableBufferPointer { g in
                    WatercolorRenderer.pack(sim, box: box, width: w, density: out.baseAddress!, grain: g.baseAddress!)
                }
            }
        }
        frame.regions = regions.filter { Int($0) < sheet.regionCount }
        for (_, t) in WatercolorRenderer.targets(sim, of: frame.regions) {
            frame.gains.append(t.gain)
            frame.aims.append(t.aim)
        }
        return frame
    }
}

/// Draws the Making Of's frames with the painting screen's shader (Watercolor.metal), the
/// sheet filling the view, which keeps its proportions.
@MainActor
final class WatercolorFilmRenderer: NSObject, MTKViewDelegate {
    let device: any MTLDevice
    let template: Template
    private let sheet: WatercolorSheet
    private let queue: any MTLCommandQueue
    private let pipeline: any MTLRenderPipelineState
    private let density: any MTLTexture
    private let granulation: any MTLTexture
    private let labels: any MTLTexture
    private let paper: any MTLTexture
    private let pencil: any MTLTexture
    private let numbers: any MTLTexture
    /// No numbers: the film's (the bare sheet it lifts off has them).
    private let noNumbers: any MTLTexture
    private let regions: any MTLBuffer
    /// One frame on the GPU at a time: its textures are written in place.
    private let inFlight = DispatchSemaphore(value: 1)
    private var pending: [WatercolorFilmFrame] = []
    private var time: Float = 0
    private var pencilFade: Float = 0
    private var front: Float = -WatercolorMakingOf.frontWidth
    /// Told of each frame once it is drawn.
    var onFrame: ((WatercolorFilmFrame) -> Void)?

    init?(template t: Template, sheet: WatercolorSheet, assets: WatercolorAssets, first: WatercolorFilmFrame) {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue(),
              let library = try? device.makeDefaultLibrary(bundle: Bundle(for: WatercolorFilmRenderer.self))
        else { return nil }
        let d = MTLRenderPipelineDescriptor()
        d.vertexFunction = library.makeFunction(name: "watercolor_vertex")
        d.fragmentFunction = library.makeFunction(name: "watercolor_fragment")
        d.colorAttachments[0].pixelFormat = WatercolorRenderer.colorFormat
        guard let pipeline = try? device.makeRenderPipelineState(descriptor: d) else { return nil }
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
              let noNumbers = texture(.r8Unorm, 1, 1),
              let regions = device.makeBuffer(length: max(1, t.regions.count) * MemoryLayout<WatercolorRegion>.stride,
                                              options: .storageModeShared)
        else { return nil }
        self.device = device
        self.template = t
        self.sheet = sheet
        self.queue = queue
        self.pipeline = pipeline
        self.density = density
        self.granulation = granulation
        self.labels = labels
        self.paper = paper
        self.pencil = pencil
        self.numbers = numbers
        self.noNumbers = noNumbers
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
        var none: UInt8 = 0
        noNumbers.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: &none, bytesPerRow: 1)
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
        upload(first)
    }

    /// A frame from the simulation, drawn with the next.
    func receive(_ frame: WatercolorFilmFrame) {
        pending.append(frame)
    }

    // MARK: MTKViewDelegate

    nonisolated func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    nonisolated func draw(in view: MTKView) {
        MainActor.assumeIsolated { frame(in: view) }
    }

    private func frame(in view: MTKView) {
        inFlight.wait()
        let arrived = pending
        pending.removeAll(keepingCapacity: true)
        for frame in arrived { upload(frame) }
        guard let pass = view.currentRenderPassDescriptor, let drawable = view.currentDrawable,
              let commands = queue.makeCommandBuffer()
        else {
            inFlight.signal()
            return
        }
        let width = Float(view.drawableSize.width)
        encode(commands, pass: pass, unitsPerPixel: Float(template.width) / max(width, 1))
        commands.present(drawable)
        Self.signal(inFlight, when: commands)
        commands.commit()
        for frame in arrived { onFrame?(frame) }
    }

    /// Releases the frame's hold once the GPU is done with it (formed off the main actor: Metal
    /// calls back on its own thread).
    private nonisolated static func signal(_ semaphore: DispatchSemaphore, when commands: any MTLCommandBuffer) {
        commands.addCompletedHandler { _ in semaphore.signal() }
    }

    private func encode(_ commands: any MTLCommandBuffer, pass: MTLRenderPassDescriptor, unitsPerPixel: Float,
                        numbered: Bool = false) {
        var uniforms = WatercolorUniforms(
            offset: .zero, unitsPerPixel: unitsPerPixel, time: time,
            canvasSize: SIMD2(Float(template.width), Float(template.height)),
            paperTexel: SIMD2(1 / Float(paper.width), 1 / Float(paper.height)),
            simTexel: SIMD2(1 / Float(sheet.width), 1 / Float(sheet.height)),
            film: SIMD2(pencilFade, 1 + front),  // y: the drying front, past 1 (Watercolor.metal)
            paper: WatercolorRenderer.paperColor, background: WatercolorRenderer.paperColor,
            numberInk: WatercolorRenderer.numberInk, sheet: .zero)
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = commands.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<WatercolorUniforms>.stride, index: 0)
        encoder.setFragmentBuffer(regions, offset: 0, index: 1)
        // The painting's hatch reads its paints here; the film hatches nothing (sheet.z is 0).
        encoder.setFragmentBuffer(regions, offset: 0, index: 2)
        encoder.setFragmentTexture(density, index: 0)
        encoder.setFragmentTexture(granulation, index: 1)
        encoder.setFragmentTexture(labels, index: 2)
        encoder.setFragmentTexture(paper, index: 3)
        encoder.setFragmentTexture(pencil, index: 4)
        encoder.setFragmentTexture(numbered ? numbers : noNumbers, index: 5)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }

    private func upload(_ frame: WatercolorFilmFrame) {
        time = frame.time
        pencilFade = frame.pencilFade
        front = frame.front
        if let box = frame.box {
            let bw = box.x1 - box.x0, bh = box.y1 - box.y0
            frame.density.withUnsafeBytes { raw in
                density.replace(region: MTLRegionMake2D(box.x0, box.y0, bw, bh), mipmapLevel: 0,
                                withBytes: raw.baseAddress!, bytesPerRow: bw * 8)
            }
            frame.granulation.withUnsafeBytes { raw in
                granulation.replace(region: MTLRegionMake2D(box.x0, box.y0, bw, bh), mipmapLevel: 0,
                                    withBytes: raw.baseAddress!, bytesPerRow: bw * 2)
            }
        }
        let count = template.regions.count
        let states = regions.contents().bindMemory(to: WatercolorRegion.self, capacity: count)
        for (k, r) in frame.regions.enumerated() where Int(r) < count {
            states[Int(r)] = WatercolorRegion(gain: frame.gains[k], aim: frame.aims[k])
        }
    }

    /// The sheet as it stands with its numbers, `maxPixelSize` on its long side: the bare sheet
    /// the film lifts off, taken before it starts.
    func picture(maxPixelSize: Int) -> CGImage? {
        let scale = Float(maxPixelSize) / Float(max(template.width, template.height, 1))
        let w = max(1, Int((Float(template.width) * scale).rounded())), h = max(1, Int((Float(template.height) * scale).rounded()))
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: WatercolorRenderer.colorFormat, width: w, height: h, mipmapped: false)
        d.usage = [.renderTarget]
        d.storageMode = .shared
        guard let target = device.makeTexture(descriptor: d), let commands = queue.makeCommandBuffer() else { return nil }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        inFlight.wait()
        defer { inFlight.signal() }
        encode(commands, pass: pass, unitsPerPixel: 1 / scale, numbered: true)
        commands.commit()
        commands.waitUntilCompleted()
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

/// The Making Of's sheet on screen: an `MTKView` drawing every frame while it plays.
struct WatercolorFilmCanvas: UIViewRepresentable {
    let renderer: WatercolorFilmRenderer

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: renderer.device)
        view.colorPixelFormat = WatercolorRenderer.colorFormat
        view.framebufferOnly = true
        view.preferredFramesPerSecond = 60
        view.isUserInteractionEnabled = false
        view.delegate = renderer
        if let layer = view.layer as? CAMetalLayer {
            layer.colorspace = CGColorSpace(name: CGColorSpace.displayP3)
        }
        return view
    }

    func updateUIView(_ view: MTKView, context: Context) {}
}

/// The Making Of over the painting screen: the study on the desk, painted; then held, and set
/// aside onto the painting's own sheet. A tap anywhere sets it aside at once.
struct WatercolorMakingOfView: View {
    let film: WatercolorFilm
    let onEnd: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Reduce Motion's finished study shown over its bare sheet.
    @State private var showsFinished = false
    /// The study set aside: risen and faded off the desk.
    @State private var setAside = false
    /// Then the bare desk faded, uncovering the painting screen beneath: the two sheets never
    /// share the frame (critic round 2: the study over the numbered sheet was a muddle).
    @State private var gone = false
    @State private var pushedIn = false

    /// The finished study held as the camera draws back out, then set aside
    /// (`tools/watercolor_making_of.py` films both), and how far it rises as it goes.
    static let hold: Double = 0.5
    static let setAsideSeconds: Double = 0.7
    static let rise: CGFloat = 90
    /// The push in toward a drying bloom while the drying front sweeps: how far, and how long.
    static let pushIn: CGFloat = 1.15
    static let pushSeconds: Double = 1.4

    private var studyShown: Bool { !reduceMotion || showsFinished }

    var body: some View {
        let t = film.template
        ZStack {
            WatercolorEra.desk.ignoresSafeArea()
            ZStack {
                if reduceMotion, let bare = film.bare {
                    Image(decorative: bare, scale: 1)
                        .resizable()
                }
                WatercolorFilmCanvas(renderer: film.renderer)
                    .opacity(studyShown ? 1 : 0)
            }
            .aspectRatio(CGSize(width: t.width, height: t.height), contentMode: .fit)
            .scaleEffect(pushedIn ? Self.pushIn : 1, anchor: film.focus)
            .clipped()
            .padding(20)
            .offset(y: setAside && !reduceMotion ? -Self.rise : 0)
            .opacity(setAside ? 0 : 1)
        }
        .opacity(gone ? 0 : 1)
        .contentShape(.rect)
        .onTapGesture { end(after: 0.3) }
        .accessibilityHidden(true)
        .task {
            film.start(settlingAtOnce: reduceMotion)
            if film.hold != nil { return }
            while !film.isSettled {
                guard (try? await Task.sleep(for: .milliseconds(50))) != nil else { return }
            }
            if reduceMotion {
                withAnimation(.easeInOut(duration: 1)) { showsFinished = true }
                guard (try? await Task.sleep(for: .seconds(2.2))) != nil else { return }
                end(after: 1)
            } else {
                withAnimation(.easeInOut(duration: Self.hold)) { pushedIn = false }
                guard (try? await Task.sleep(for: .seconds(Self.hold))) != nil else { return }
                end(after: Self.setAsideSeconds)
            }
        }
        .onChange(of: film.isDrying) { _, drying in
            guard drying, !reduceMotion, film.hold == nil else { return }
            withAnimation(.easeInOut(duration: Self.pushSeconds)) { pushedIn = true }
        }
        .onDisappear { film.stop() }
    }

    /// The study is set aside over `seconds`, then the bare desk fades over `seconds` × 0.6,
    /// uncovering the painting screen beneath.
    private func end(after seconds: Double) {
        guard !setAside else { return }
        withAnimation(.easeIn(duration: seconds)) { setAside = true }
        Task {
            try? await Task.sleep(for: .seconds(seconds))
            film.stop()
            withAnimation(.easeInOut(duration: seconds * 0.6)) { gone = true }
            try? await Task.sleep(for: .seconds(seconds * 0.6))
            onEnd()
        }
    }
}
#endif
