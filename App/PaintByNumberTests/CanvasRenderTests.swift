import CoreGraphics
import CoreVideo
import Foundation
import Metal
import PaintCore
import Testing
@testable import PaintByNumber

/// Renders the synthetic template offscreen with the canvas shaders and checks pixels.
/// Rendered PNGs are attached to the results for visual inspection.
struct CanvasRenderTests {
    static let template = SyntheticTemplate.make(.init(width: 480, height: 640, columns: 6, rows: 8, seed: 3))

    @Test func shaderStructLayoutsMatchMetal() {
        #expect(MemoryLayout<CanvasUniforms>.stride == 208)
        #expect(MemoryLayout<RegionState>.stride == 32)
        #expect(MemoryLayout<GlyphInstance>.stride == 24)
    }

    @Test func syntheticTemplateIsWatertight() {
        let t = Self.template
        var total: Float = 0
        for r in t.regions {
            var area: Float = 0
            for k in stride(from: Int(r.indexStart), to: Int(r.indexStart + r.indexCount), by: 3) {
                let a = t.mesh.vertices[Int(t.mesh.indices[k])]
                let b = t.mesh.vertices[Int(t.mesh.indices[k + 1])]
                let c = t.mesh.vertices[Int(t.mesh.indices[k + 2])]
                let s = 0.5 * ((b.x - a.x) * (c.y - a.y) - (c.x - a.x) * (b.y - a.y))
                #expect(s > 0)
                area += s
            }
            total += area
            if r.area > 300 { #expect(abs(area - r.area) / r.area < 0.06) }
        }
        #expect(abs(total - Float(t.width * t.height)) < 1)
        let report = t.validate()
        #expect(report.isValid, "\(report)")
        #expect(Set(t.regions.map(\.colorIndex)).count == t.palette.count)
    }

    @Test func paintedRegionsShowTheirPaintAndTheRestIsPaper() throws {
        let t = Self.template
        var progress = PaintProgress(regionCount: t.regions.count)
        for r in t.regions.indices where r % 2 == 0 { progress.paint(r) }
        let image = try #require(CanvasSnapshot.render(template: t, progress: progress, size: size(t, 1), options: .painting))
        record(image, "fills")
        let px = Pixels(image)
        let paper = encoded(CanvasPalette.light.paper)
        var checked = 0
        for (r, region) in t.regions.enumerated() {
            guard let label = t.labels(ofRegion: r).first, label.radius >= 4 else { continue }
            let got = px[Int(label.position.x), Int(label.position.y)]
            let expected = r % 2 == 0 ? bytes(t.palette[Int(region.colorIndex)].rgb) : paper
            #expect(maxDifference(got, expected) <= 3, "region \(r): \(got) vs \(expected)")
            checked += 1
        }
        #expect(checked > 40)
    }

    @Test func outlinesDarkenOpenBoundariesAndDissolveBetweenPaintedRegions() throws {
        let t = Self.template
        let options = CanvasSnapshot.Options(outlines: true, numbers: false, outlineWidth: 1.5)
        let blank = try #require(CanvasSnapshot.render(template: t, progress: nil, size: size(t, 2), options: options))
        var done = PaintProgress(regionCount: t.regions.count)
        for r in t.regions.indices { done.paint(r) }
        let finished = try #require(CanvasSnapshot.render(template: t, progress: done, size: size(t, 2), options: options))
        record(blank, "outlines-blank")
        record(finished, "outlines-finished")
        let open = Pixels(blank), closed = Pixels(finished)
        let paperLuma = luma(encoded(CanvasPalette.light.paper))
        var checked = 0
        for edge in t.edges where edge.right != BoundaryEdge.outside && edge.pointCount >= 3 {
            let p = t.points[Int(edge.pointStart + edge.pointCount / 2)]
            let x = Int(p.x * 2), y = Int(p.y * 2)
            #expect(luma(open[x, y]) < paperLuma - 40, "edge point \(p) should be inked")
            // Painted on both sides: no line art left, only the two paints meeting.
            let left = luma(bytes(t.palette[Int(t.regions[Int(edge.left)].colorIndex)].rgb))
            let right = luma(bytes(t.palette[Int(t.regions[Int(edge.right)].colorIndex)].rgb))
            #expect(luma(closed[x, y]) >= min(left, right) - 8, "edge point \(p) should have dissolved")
            checked += 1
        }
        #expect(checked > 40)
    }

    @Test func numbersAppearWhenLegibleAndVanishOncePainted() throws {
        let t = Self.template
        let blank = try #require(CanvasSnapshot.render(template: t, progress: nil, size: size(t, 2), options: .preview))
        var done = PaintProgress(regionCount: t.regions.count)
        for r in t.regions.indices { done.paint(r) }
        let finished = try #require(CanvasSnapshot.render(template: t, progress: done, size: size(t, 2), options: .preview))
        record(blank, "numbers")
        let open = Pixels(blank), closed = Pixels(finished)
        let paperLuma = luma(encoded(CanvasPalette.light.paper))
        var checked = 0
        for (r, region) in t.regions.enumerated() {
            guard let label = t.labels(ofRegion: r).first, label.radius >= 10 else { continue }
            let cx = Int(label.position.x * 2), cy = Int(label.position.y * 2)
            let reach = Int(label.radius * 2 * 0.6)
            var darkest = 255, lightest = 0, paintSpread = 0
            let paint = luma(bytes(t.palette[Int(region.colorIndex)].rgb))
            for y in (cy - reach)...(cy + reach) {
                for x in (cx - reach)...(cx + reach) {
                    darkest = min(darkest, luma(open[x, y]))
                    lightest = max(lightest, luma(open[x, y]))
                    paintSpread = max(paintSpread, abs(luma(closed[x, y]) - paint))
                }
            }
            #expect(darkest < paperLuma - 60, "region \(r) should show its number")
            #expect(lightest > paperLuma - 4, "region \(r) should still be mostly paper")
            #expect(paintSpread <= 3, "region \(r) number should be gone once painted")
            checked += 1
        }
        #expect(checked > 10)
    }

    @Test func selectedColorIsHighlighted() throws {
        let t = Self.template
        // The darkest paint: its tint must be unmistakable.
        let color = t.palette.indices.min { t.palette[$0].oklab.x < t.palette[$1].oklab.x }!
        var options = CanvasSnapshot.Options.painting
        options.highlight = color
        let image = try #require(CanvasSnapshot.render(template: t, progress: nil, size: size(t, 2), options: options))
        record(image, "highlight")
        let px = Pixels(image)
        let paper = encoded(CanvasPalette.light.paper)
        for (r, region) in t.regions.enumerated() {
            guard let label = t.labels(ofRegion: r).first, label.radius >= 10 else { continue }
            // Average a patch: the hatch alternates, so compare the mean tint against paper.
            var sum = SIMD3<Int>(repeating: 0), n = 0
            let cx = Int(label.position.x * 2), cy = Int(label.position.y * 2)
            for y in (cy - 8)...(cy + 8) { for x in (cx - 8)...(cx + 8) { sum &+= px[x, y]; n += 1 } }
            let mean = sum / n
            if Int(region.colorIndex) == color {
                #expect(maxDifference(mean, paper) > 12, "region \(r) should be highlighted")
            } else {
                #expect(maxDifference(mean, paper) <= 3, "region \(r) should be plain paper")
            }
        }
    }

    @Test func largeTemplateBuildsAndRendersQuickly() throws {
        let clock = ContinuousClock()
        var t0 = clock.now
        let t = SyntheticTemplate.make(.init(width: 1800, height: 2400, columns: 48, rows: 64, seed: 11))
        let build = clock.now - t0
        let context = try #require(RenderContext.shared)
        t0 = clock.now
        let scene = try #require(CanvasScene(template: t, context: context))
        let upload = clock.now - t0
        var progress = PaintProgress(regionCount: t.regions.count)
        for r in t.regions.indices where r % 3 == 0 { progress.paint(r) }
        let painted = t.regions.indices.map(progress.isPainted)
        t0 = clock.now
        let image = try #require(CanvasSnapshot.render(
            scene: scene, template: t, painted: painted, size: CGSize(width: 1800, height: 2400),
            options: .preview, context: context))
        let render = clock.now - t0
        record(image, "large")
        let report = """
            regions \(t.regions.count), mesh vertices \(t.mesh.vertices.count), triangles \(t.mesh.indices.count / 3), \
            segments \(scene.segmentCount), glyphs \(scene.glyphCount)
            synthetic build \(build), scene upload \(upload), offscreen render 1800×2400 \(render)
            """
        Attachment.record(Data(report.utf8), named: "large-timings.txt")
        #expect(upload < .milliseconds(250))
    }

    /// A template from the real pipeline, drawn at iPhone 17 Pro resolution with every pass on
    /// (MSAA fills with highlight, outline coverage + composite, numbers). Timings are attached.
    @Test func realTemplateFrameCost() throws {
        let url = try #require(Bundle.main.url(forResource: "parrots", withExtension: "jpg"))
        let photo = try PhotoLoader.load(url: url, maxPixelSize: 2048)
        let clock = ContinuousClock()
        var t0 = clock.now
        // The most detailed settings a user can pick: the realistic worst case for the canvas.
        let t = try TemplateGenerator(settings: GenerationSettings(colorCount: 48, detail: 1)).generate(from: photo).template
        let generate = clock.now - t0
        let context = try #require(RenderContext.shared)
        t0 = clock.now
        let scene = try #require(CanvasScene(template: t, context: context))
        let upload = clock.now - t0

        let w = 1206, h = 2622
        var states = t.regions.indices.map { RegionState.settled(painted: $0 % 2 == 0, origin: .zero, seed: 0) }
        // A handful of fills mid-animation, like drag painting.
        for r in stride(from: 1, to: min(t.regions.count, 400), by: 40) {
            states[r] = RegionState(origin: t.labels(ofRegion: r).first?.position ?? .zero, start: -0.2, duration: 0.5,
                                    radius: 40, painted: 1, seed: 1)
        }
        let stateBuffer = try #require(context.device.makeBuffer(
            bytes: states, length: MemoryLayout<RegionState>.stride * states.count, options: .storageModeShared))
        var u = CanvasSnapshot.uniforms(scene: scene, width: w, height: h, options: .preview)
        u.transform.w = 3
        u.outline = SIMD4(1.5, 3.2, 1, 1)
        u.labels = SIMD4(19.5, 25.5, 66, 48)
        u.numbers = SIMD4(0.5, 0.9, 0.05, 0)
        u.selected = SIMD4(scene.paletteLinear[1], 1)
        u.ids.x = 1
        let color = try #require(context.makeColorTarget(width: w, height: h))
        let outlines = try #require(context.makeOutlineTarget(width: w, height: h))
        let targets = RenderContext.Targets(
            color: color, multisample: context.makeMultisampleTarget(width: w, height: h), outlines: outlines)
        var gpu: Double = 0
        let frames = 30
        t0 = clock.now
        for frame in 0...frames {
            let commands = try #require(context.queue.makeCommandBuffer())
            context.encode(commands, scene: scene, states: stateBuffer, uniforms: u, targets: targets,
                           content: RenderContext.Content(outlines: true, numbers: true))
            commands.commit()
            commands.waitUntilCompleted()
            if frame == 0 { t0 = clock.now } else { gpu += commands.gpuEndTime - commands.gpuStartTime }
        }
        let wall = (clock.now - t0) / frames
        let report = """
            parrots (48 colors, detail 1): \(t.regions.count) regions, \(t.mesh.indices.count / 3) triangles, \(scene.segmentCount) outline segments, \
            \(scene.glyphCount) digit quads
            generate \(generate), scene upload \(upload)
            frame 1206×2622 MSAA×\(context.sampleCount): wall \(wall), GPU \(String(format: "%.2f", gpu / Double(frames) * 1000)) ms (simulator)
            """
        Attachment.record(Data(report.utf8), named: "real-template-timings.txt")
        #expect(upload < .milliseconds(300))
    }

    @Test func timelapseFramesReplayTheStrokeLog() throws {
        let t = Self.template
        var progress = PaintProgress(regionCount: t.regions.count)
        for r in t.regions.indices.reversed() { progress.paint(r) }
        let renderer = try #require(TimelapseFrameRenderer(template: t, progress: progress))
        #expect(renderer.strokeCount == t.regions.count)
        var buffer: CVPixelBuffer?
        let attributes: [String: Any] = [
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
        ]
        CVPixelBufferCreate(nil, 240, 320, kCVPixelFormatType_32BGRA, attributes as CFDictionary, &buffer)
        let frame = try #require(buffer)
        // Halfway through the log with the next stroke 40 % spread.
        let half = t.regions.count / 2
        try renderer.render(frame: 0, strokes: half, fraction: 0.4, into: frame)()
        CVPixelBufferLockBaseAddress(frame, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(frame, .readOnly) }
        let base = try #require(CVPixelBufferGetBaseAddress(frame))
        let data = Data(bytes: base, count: CVPixelBufferGetBytesPerRow(frame) * 320)
        let provider = try #require(CGDataProvider(data: data as CFData))
        let image = try #require(CGImage(
            width: 240, height: 320, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: CVPixelBufferGetBytesPerRow(frame),
            space: CGColorSpace(name: CGColorSpace.displayP3)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        record(image, "timelapse-frame")
        // Strokes run from the last region backwards: late regions are painted, early ones paper.
        let px = Pixels(image)
        let paper = encoded(CanvasPalette.light.paper)
        let scale = Float(240) / Float(t.width)
        func sample(_ r: Int) -> SIMD3<Int>? {
            guard let l = t.labels(ofRegion: r).first, l.radius * scale >= 3 else { return nil }
            return px[Int(l.position.x * scale), Int(l.position.y * scale)]
        }
        if let last = sample(t.regions.count - 1) {
            #expect(maxDifference(last, bytes(t.palette[Int(t.regions.last!.colorIndex)].rgb)) <= 4)
        }
        if let first = t.regions.indices.lazy.compactMap(sample).first {
            #expect(maxDifference(first, paper) <= 4)
        }
    }

    // MARK: Helpers

    private func size(_ t: Template, _ scale: Int) -> CGSize {
        CGSize(width: t.width * scale, height: t.height * scale)
    }

    private func record(_ image: CGImage, _ name: String) {
        if let png = CanvasSnapshot.pngData(image) { Attachment.record(png, named: "\(name).png") }
    }
}

/// 8-bit RGB pixels of a rendered image, in Display P3.
struct Pixels {
    let width: Int
    let height: Int
    private let data: [UInt8]

    init(_ image: CGImage) {
        let w = image.width, h = image.height
        var buffer = [UInt8](repeating: 0, count: w * h * 4)
        let space = CGColorSpace(name: CGColorSpace.displayP3)!
        buffer.withUnsafeMutableBytes { raw in
            let ctx = CGContext(
                data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        width = w
        height = h
        data = buffer
    }

    subscript(x: Int, y: Int) -> SIMD3<Int> {
        let cx = min(max(x, 0), width - 1), cy = min(max(y, 0), height - 1)
        let i = (cy * width + cx) * 4
        return SIMD3(Int(data[i]), Int(data[i + 1]), Int(data[i + 2]))
    }
}

func bytes(_ encoded: SIMD3<Float>) -> SIMD3<Int> {
    SIMD3(Int((encoded.x * 255).rounded()), Int((encoded.y * 255).rounded()), Int((encoded.z * 255).rounded()))
}

/// Linear P3 → 8-bit encoded P3.
func encoded(_ linear: SIMD3<Float>) -> SIMD3<Int> {
    bytes(SIMD3(ColorScience.encodeSRGB(linear.x), ColorScience.encodeSRGB(linear.y), ColorScience.encodeSRGB(linear.z)))
}

func maxDifference(_ a: SIMD3<Int>, _ b: SIMD3<Int>) -> Int {
    max(abs(a.x - b.x), abs(a.y - b.y), abs(a.z - b.z))
}

func luma(_ c: SIMD3<Int>) -> Int {
    (c.x * 2126 + c.y * 7152 + c.z * 722) / 10000
}
