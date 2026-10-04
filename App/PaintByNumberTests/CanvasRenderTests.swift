import CoreGraphics
import CoreVideo
import Foundation
import Metal
import PaintCore
import Testing
import UIKit
@testable import PaintByNumber

/// Renders the synthetic template offscreen with the canvas shaders and checks pixels.
/// Rendered PNGs are attached to the results for visual inspection.
struct CanvasRenderTests {
    static let template = SyntheticTemplate.make(.init(width: 480, height: 640, columns: 6, rows: 8, seed: 3))

    @Test func shaderStructLayoutsMatchMetal() {
        #expect(MemoryLayout<CanvasUniforms>.stride == 320)
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

    @Test func labelSizesFollowSharedRule() throws {
        let t = Self.template
        let context = try #require(RenderContext.shared)
        let scene = try #require(CanvasScene(template: t, context: context))
        let maxSize = 0.045 * Float(min(t.width, t.height))
        for r in t.regions.indices {
            guard let label = t.labels(ofRegion: r).first else {
                #expect(scene.labelSizes[r] == 0)
                continue
            }
            let digits = LabelSizing.digitCount(colorIndex: t.regions[r].colorIndex)
            #expect(scene.labelSizes[r] == LabelSizing.fontSize(radius: label.radius, digits: digits, maximum: maxSize))
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
        var states = t.regions.indices.map { RegionState.settled(painted: $0 % 2 == 0) }
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
        u.select(scene.paletteLinear[1], palette: .light)
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

    /// The photo overlay fills exactly the canvas rect, the right way up, and blends with the
    /// canvas below at partial opacity.
    @Test func photoOverlayCoversTheCanvasExactly() throws {
        let t = Self.template
        let context = try #require(RenderContext.shared)
        let scene = try #require(CanvasScene(template: t, context: context))
        // Quadrants, top row first: red | green over blue | yellow.
        let pw = 240, ph = 320
        let red = SIMD3<Float>(1, 0, 0), green = SIMD3<Float>(0, 1, 0), blue = SIMD3<Float>(0, 0, 1), yellow = SIMD3<Float>(1, 1, 0)
        var rgba = [UInt8](repeating: 255, count: pw * ph * 4)
        for y in 0..<ph {
            for x in 0..<pw {
                let c = y < ph / 2 ? (x < pw / 2 ? red : green) : (x < pw / 2 ? blue : yellow)
                let i = (y * pw + x) * 4
                rgba[i] = UInt8(c.x * 255)
                rgba[i + 1] = UInt8(c.y * 255)
                rgba[i + 2] = UInt8(c.z * 255)
            }
        }
        let provider = try #require(CGDataProvider(data: Data(rgba) as CFData))
        let photo = try #require(CGImage(
            width: pw, height: ph, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: pw * 4,
            space: CGColorSpace(name: CGColorSpace.displayP3)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let texture = try #require(context.makePhotoTexture(photo))
        #expect(texture.mipmapLevelCount > 1)
        #expect(texture.width == pw && texture.height == ph)

        // Letterboxed: the 480×640 canvas is fitted into 600×700, 37.5 px in from each side.
        let w = 600, h = 700
        var u = CanvasSnapshot.uniforms(scene: scene, width: w, height: h, options: .painting)
        u.photo.x = 1
        let content = RenderContext.Content(outlines: false, numbers: false, photo: texture)
        let shown = try #require(render(scene: scene, uniforms: u, content: content, width: w, height: h))
        record(shown, "photo-overlay")
        let px = Pixels(shown)
        let left = Double(u.transform.x), right = left + Double(u.transform.z) * Double(t.width)
        let midX = Int((left + right) / 2), midY = h / 2
        let expected = [red, green, blue, yellow].map { bytes($0) }
        let centres = [(left + (right - left) / 4, h / 4), (left + 3 * (right - left) / 4, h / 4),
                       (left + (right - left) / 4, 3 * h / 4), (left + 3 * (right - left) / 4, 3 * h / 4)]
        for (i, (x, y)) in centres.enumerated() {
            #expect(maxDifference(px[Int(x), y], expected[i]) <= 2, "quadrant \(i): \(px[Int(x), y])")
        }
        // Just either side of the midlines: not blurred together, not flipped.
        #expect(maxDifference(px[midX - 3, h / 4], expected[0]) <= 4)
        #expect(maxDifference(px[midX + 3, h / 4], expected[1]) <= 4)
        #expect(maxDifference(px[midX - 3, 3 * h / 4], expected[2]) <= 4)
        #expect(maxDifference(px[midX + 3, 3 * h / 4], expected[3]) <= 4)
        #expect(maxDifference(px[Int(left) + 20, midY - 3], expected[0]) <= 4)
        #expect(maxDifference(px[Int(left) + 20, midY + 3], expected[2]) <= 4)
        // Outside the canvas rect there is no photo.
        #expect(maxDifference(px[Int(left) - 3, h / 4], expected[0]) > 100)
        #expect(maxDifference(px[Int(right.rounded(.up)) + 3, 3 * h / 4], expected[3]) > 100)

        // Half faded in: paint and photo mix in linear light.
        u.photo.x = 0.5
        let half = try #require(render(scene: scene, uniforms: u, content: content, width: w, height: h))
        let mixed = encoded(0.5 * red + 0.5 * CanvasPalette.light.paper)
        let (x, y) = centres[0]
        #expect(maxDifference(Pixels(half)[Int(x), y], mixed) <= 3, "\(Pixels(half)[Int(x), y]) vs \(mixed)")
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

    /// Dark paper: the sheet and its numbers swap light for dark, the paint stays as it is, and
    /// the selected color's tint and hatching still show (a dark paint on dark paper would not
    /// without lifting).
    @Test func darkPaperKeepsPaintAndLightensPaperNumbersAndHighlight() throws {
        let t = Self.template
        var progress = PaintProgress(regionCount: t.regions.count)
        for r in t.regions.indices where r % 2 == 0 { progress.paint(r) }
        var options = CanvasSnapshot.Options.preview
        options.palette = .darkPaper
        let image = try #require(CanvasSnapshot.render(template: t, progress: progress, size: size(t, 2), options: options))
        record(image, "dark-paper")
        let px = Pixels(image)
        let paper = encoded(CanvasPalette.darkPaper.paper)
        #expect(luma(paper) < 50)
        var painted = 0, unpainted = 0
        for (r, region) in t.regions.enumerated() {
            guard let label = t.labels(ofRegion: r).first, label.radius >= 10 else { continue }
            let cx = Int(label.position.x * 2), cy = Int(label.position.y * 2)
            if r % 2 == 0 {
                #expect(maxDifference(px[cx, cy], bytes(t.palette[Int(region.colorIndex)].rgb)) <= 3, "region \(r) should keep its paint")
                painted += 1
                continue
            }
            let reach = Int(label.radius * 2 * 0.6)
            var darkest = 255, lightest = 0
            for y in (cy - reach)...(cy + reach) {
                for x in (cx - reach)...(cx + reach) {
                    darkest = min(darkest, luma(px[x, y]))
                    lightest = max(lightest, luma(px[x, y]))
                }
            }
            #expect(abs(darkest - luma(paper)) <= 4, "region \(r) should be dark paper around its number")
            #expect(lightest > luma(paper) + 80, "region \(r) should show a light number")
            unpainted += 1
        }
        #expect(painted > 2 && unpainted > 2)

        let darkestPaint = t.palette.indices.min { t.palette[$0].oklab.x < t.palette[$1].oklab.x }!
        options.numbers = false
        options.highlight = darkestPaint
        let highlighted = try #require(CanvasSnapshot.render(template: t, progress: nil, size: size(t, 2), options: options))
        record(highlighted, "dark-paper-highlight")
        let hpx = Pixels(highlighted)
        var checked = 0
        for (r, region) in t.regions.enumerated() where Int(region.colorIndex) == darkestPaint {
            guard let label = t.labels(ofRegion: r).first, label.radius >= 10 else { continue }
            var sum = SIMD3<Int>(repeating: 0), n = 0
            let cx = Int(label.position.x * 2), cy = Int(label.position.y * 2)
            for y in (cy - 8)...(cy + 8) { for x in (cx - 8)...(cx + 8) { sum &+= hpx[x, y]; n += 1 } }
            #expect(maxDifference(sum / n, paper) > 12, "region \(r) should be highlighted on dark paper")
            checked += 1
        }
        #expect(checked > 0)
    }

    /// Dark paper has no drop shadow: a light rim just outside the sheet outlines it instead.
    @Test func darkPaperDrawsARimInsteadOfAShadow() throws {
        let t = Self.template
        let context = try #require(RenderContext.shared)
        let scene = try #require(CanvasScene(template: t, context: context))
        let w = 600, h = 700
        var u = CanvasSnapshot.uniforms(scene: scene, width: w, height: h, options: .painting)
        u.setChrome(.darkPaper, shadowOpacity: 0, outlineOpacity: 0.5)
        let margin = Float(44)
        let content = RenderContext.Content(
            outlines: false, numbers: false, shadowMargin: margin,
            clear: MTLClearColor(red: Double(CanvasPalette.darkPaper.background.x), green: Double(CanvasPalette.darkPaper.background.y),
                                 blue: Double(CanvasPalette.darkPaper.background.z), alpha: 1))
        let shown = try #require(render(scene: scene, uniforms: u, content: content, width: w, height: h))
        record(shown, "dark-paper-rim")
        let px = Pixels(shown)
        let left = Int(u.transform.x), midY = h / 2
        let backdrop = encoded(CanvasPalette.darkPaper.background)
        // The pixel row just outside the left edge is lighter than the backdrop; further out it is the backdrop.
        #expect(luma(px[left - 1, midY]) > luma(backdrop) + 12, "no rim at the sheet's edge")
        #expect(maxDifference(px[left - 8, midY], backdrop) <= 2, "the rim should be one pixel, with no shadow beyond it")
    }

    // MARK: Helpers

    /// One offscreen frame with explicit uniforms and content (unpainted regions).
    private func render(scene: CanvasScene, uniforms: CanvasUniforms, content: RenderContext.Content, width w: Int, height h: Int) -> CGImage? {
        guard let context = RenderContext.shared else { return nil }
        let device = context.device
        let states = (0..<scene.regionCount).map { _ in RegionState.settled(painted: false) }
        let rowBytes = (w * 4 + 255) / 256 * 256
        guard let stateBuffer = device.makeBuffer(bytes: states, length: MemoryLayout<RegionState>.stride * max(states.count, 1), options: .storageModeShared),
              let color = context.makeColorTarget(width: w, height: h),
              let outlines = context.makeOutlineTarget(width: w, height: h),
              let readback = device.makeBuffer(length: rowBytes * h, options: .storageModeShared),
              let commands = context.queue.makeCommandBuffer()
        else { return nil }
        context.encode(
            commands, scene: scene, states: stateBuffer, uniforms: uniforms,
            targets: RenderContext.Targets(color: color, multisample: context.makeMultisampleTarget(width: w, height: h), outlines: outlines),
            content: content)
        guard let blit = commands.makeBlitCommandEncoder() else { return nil }
        blit.copy(
            from: color, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
            sourceSize: MTLSize(width: w, height: h, depth: 1),
            to: readback, destinationOffset: 0, destinationBytesPerRow: rowBytes, destinationBytesPerImage: rowBytes * h)
        blit.endEncoding()
        commands.commit()
        commands.waitUntilCompleted()
        guard commands.status == .completed,
              let provider = CGDataProvider(data: Data(bytes: readback.contents(), count: rowBytes * h) as CFData),
              let space = CGColorSpace(name: CGColorSpace.displayP3)
        else { return nil }
        return CGImage(
            width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: rowBytes, space: space,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    private func size(_ t: Template, _ scale: Int) -> CGSize {
        CGSize(width: t.width * scale, height: t.height * scale)
    }

    private func record(_ image: CGImage, _ name: String) {
        if let png = ImageCodec.pngData(image) { Attachment.record(png, named: "\(name).png") }
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

/// The canvas palettes: contrast, the accent on dark paper, and how the Paper preference and
/// the system appearance pick one.
@MainActor
struct CanvasPaletteTests {
    /// WCAG relative luminance of a linear Display P3 color.
    private func luminance(_ c: SIMD3<Float>) -> Double {
        0.2289746 * Double(c.x) + 0.6917385 * Double(c.y) + 0.0792869 * Double(c.z)
    }

    private func contrast(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Double {
        let (hi, lo) = (max(luminance(a), luminance(b)), min(luminance(a), luminance(b)))
        return (hi + 0.05) / (lo + 0.05)
    }

    /// Ink (outlines, numbers) reads on its paper at 4.5:1 or better in every palette.
    @Test(arguments: [("light", CanvasPalette.light), ("dark appearance", CanvasPalette.dark), ("dark paper", CanvasPalette.darkPaper)])
    func inkContrastsWithPaper(name: String, palette: CanvasPalette) {
        let ratio = contrast(palette.ink, palette.paper)
        #expect(ratio >= 4.5, "\(name): \(ratio):1")
    }

    @Test func darkPaperIsADeepWarmGreyWithALightRim() {
        let p = CanvasPalette.darkPaper
        #expect(luminance(p.paper) < 0.03 && p.paper.x >= p.paper.z)
        #expect(luminance(p.background) < luminance(p.paper))
        #expect(p.shadowOpacity == 0 && p.rimOpacity > 0)
        #expect(CanvasPalette.light.rimOpacity == 0 && CanvasPalette.dark.rimOpacity == 0)
    }

    /// Light paper keeps the selected paint as its accent, exactly: its frames are unchanged.
    @Test func lightPaperAccentIsThePaintItself() {
        let paints: [SIMD3<Float>] = [.zero, SIMD3(1, 1, 1), SIMD3(0.02, 0.01, 0.05), SIMD3(0.8, 0.1, 0.1), SIMD3(0.3, 0.6, 0.2)]
        for palette in [CanvasPalette.light, .dark] {
            for paint in paints { #expect(palette.accent(for: paint) == paint) }
            var u = CanvasUniforms()
            u.select(paints[2], palette: palette)
            #expect(u.accent == SIMD4(paints[2], 0.4) && u.selected == SIMD4(paints[2], 1))
        }
    }

    /// On dark paper a dark paint is lightened until it reads, a bright one is left alone.
    @Test func darkPaperLightensDarkAccents() {
        let palette = CanvasPalette.darkPaper
        for paint in [SIMD3<Float>.zero, SIMD3(0.02, 0.01, 0.05), SIMD3(0.1, 0.02, 0.02)] {
            let accent = palette.accent(for: paint)
            #expect(luminance(accent) >= Double(palette.accentFloor) - 0.01, "\(paint) → \(accent)")
            #expect(accent.min() >= 0 && accent.max() <= 1)
        }
        let yellow = SIMD3<Float>(0.9, 0.8, 0.1)
        #expect(palette.accent(for: yellow) == yellow)
        var u = CanvasUniforms()
        u.select(.zero, palette: palette)
        #expect(u.selected == SIMD4(0, 0, 0, 1) && u.accent.w == palette.hatchCeiling && u.accent.x > 0)
    }

    /// Thumbnails, share pictures and time-lapses are paper-themed whatever the canvas shows.
    @Test func offscreenRendersStayOnLightPaper() throws {
        for options in [CanvasSnapshot.Options.painting, .preview, .thumbnail] {
            #expect(options.palette.paper == CanvasPalette.light.paper)
        }
        let context = try #require(RenderContext.shared)
        let scene = try #require(CanvasScene(template: CanvasRenderTests.template, context: context))
        let u = CanvasSnapshot.uniforms(scene: scene, width: 240, height: 320, options: .preview)
        #expect(u.paper == SIMD4(CanvasPalette.light.paper, 0) && u.rim.w == 0)
    }

    @Test func paperPreferenceAndAppearancePickThePalette() {
        for dark in [false, true] {
            #expect(CanvasPalette.resolve(.dark, interfaceIsDark: dark).paper == CanvasPalette.darkPaper.paper)
        }
        #expect(CanvasPalette.resolve(.light, interfaceIsDark: false).paper == CanvasPalette.light.paper)
        #expect(CanvasPalette.resolve(.light, interfaceIsDark: true).paper == CanvasPalette.dark.paper)
        #expect(CanvasPalette.resolve(.automatic, interfaceIsDark: false).paper == CanvasPalette.light.paper)
        #expect(CanvasPalette.resolve(.automatic, interfaceIsDark: true).paper == CanvasPalette.darkPaper.paper)
        #expect(PaperAppearance.default == .light)
        #expect(PaperAppearance.allCases.map(\.name) == ["Light", "Dark", "Automatic"])
    }

    /// The canvas resolves its paper from the preference and the trait collection it inherits
    /// from its window, so a system appearance change reaches an Automatic canvas. A view
    /// outside a window never sees an appearance change, hence the window, as in the app.
    @Test func canvasResolvesPaperFromPreferenceAndTraits() throws {
        let canvas = CanvasView(session: PaintingSession(template: CanvasRenderTests.template))
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 700)
        window.overrideUserInterfaceStyle = .light
        window.addSubview(canvas)
        canvas.frame = window.bounds
        window.isHidden = false
        defer { window.isHidden = true }
        canvas.layoutIfNeeded()
        func paper(_ palette: CanvasPalette) -> SIMD4<Float> { SIMD4(palette.paper, palette.shadowOpacity) }
        #expect(canvas.frameUniforms().paper == paper(.light))
        canvas.paperAppearance = .dark
        let dark = canvas.frameUniforms()
        #expect(dark.paper == paper(.darkPaper) && dark.rim.w > 0 && dark.ink == SIMD4(CanvasPalette.darkPaper.ink, dark.ink.w))
        canvas.paperAppearance = .automatic
        #expect(canvas.frameUniforms().paper == paper(.light))
        window.overrideUserInterfaceStyle = .dark
        canvas.updateTraitsIfNeeded()
        #expect(canvas.traitCollection.userInterfaceStyle == .dark)
        #expect(canvas.frameUniforms().paper == paper(.darkPaper))
        canvas.paperAppearance = .light
        #expect(canvas.frameUniforms().paper == paper(.dark))
        window.overrideUserInterfaceStyle = .light
        canvas.updateTraitsIfNeeded()
        #expect(canvas.frameUniforms().paper == paper(.light))
    }
}
