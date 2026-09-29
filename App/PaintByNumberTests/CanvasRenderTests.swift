import CoreGraphics
import Foundation
import PaintCore
import Testing
@testable import PaintByNumber

/// Renders the synthetic template offscreen with the canvas shaders and checks pixels.
/// Rendered PNGs are attached to the results for visual inspection.
struct CanvasRenderTests {
    static let template = SyntheticTemplate.make(.init(width: 480, height: 640, columns: 6, rows: 8, seed: 3))

    @Test func shaderStructLayoutsMatchMetal() {
        #expect(MemoryLayout<CanvasUniforms>.stride == 192)
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
        width = image.width
        height = image.height
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        let space = CGColorSpace(name: CGColorSpace.displayP3)!
        buffer.withUnsafeMutableBytes { raw in
            let ctx = CGContext(
                data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
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
