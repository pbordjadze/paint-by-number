import Foundation
import Testing
@testable import PaintCore

/// Synthetic photos and the invariants a segmentation of one must keep, shared by the suites
/// that need a picture without shipping one.
enum TestScenes {

    /// A small photo-like scene: sky gradient, ground, a few colored discs of different
    /// sizes, a thin dark line and per-pixel noise.
    static func scene(width: Int = 160, height: Int = 120, seed: UInt64 = 7, alpha: Bool = false) -> RGBAImage {
        var rng = SplitMix64(seed: seed)
        var image = RGBAImage(width: width, height: height, fill: SIMD4(0, 0, 0, 255))
        let discs: [(x: Float, y: Float, r: Float, c: SIMD3<Float>)] = [
            (0.3, 0.6, 0.18, SIMD3(200, 40, 40)), (0.7, 0.55, 0.12, SIMD3(240, 200, 30)),
            (0.55, 0.3, 0.07, SIMD3(40, 90, 200)), (0.15, 0.25, 0.04, SIMD3(250, 250, 250)),
        ]
        for y in 0..<height {
            for x in 0..<width {
                let u = Float(x) / Float(width), v = Float(y) / Float(height)
                var c: SIMD3<Float> = v < 0.45
                    ? SIMD3(90 + 100 * v, 140 + 80 * v, 230)  // sky
                    : SIMD3(70 + 40 * u, 120, 50 + 30 * v)  // grass
                for d in discs {
                    let dx = (u - d.x) * Float(width) / Float(height), dy = v - d.y
                    if dx * dx + dy * dy < d.r * d.r { c = d.c }
                }
                if abs(v - 0.8) < 0.012 && u > 0.1 && u < 0.9 { c = SIMD3(20, 20, 20) }
                c += SIMD3(rng.nextFloat(), rng.nextFloat(), rng.nextFloat()) * 24 - 12
                let a: UInt8 = alpha && u < 0.25 ? 0 : 255
                image[x, y] = SIMD4(
                    UInt8(min(max(c.x, 0), 255)), UInt8(min(max(c.y, 0), 255)), UInt8(min(max(c.z, 0), 255)), a)
            }
        }
        return image
    }

    /// A crowded, colourful scene for large palettes: a 12 × 8 grid of tiles covering an
    /// OKLab hue wheel (12 hues × 4 lightnesses × 2 chromas) with a gentle in-tile gradient,
    /// small discs of the complementary hue and per-pixel noise.
    static func colorful(width: Int = 300, height: Int = 200, seed: UInt64 = 13) -> RGBAImage {
        var rng = SplitMix64(seed: seed)
        var image = RGBAImage(width: width, height: height, fill: SIMD4(0, 0, 0, 255))
        let columns = 12, rows = 8
        let lightness: [Float] = [0.42, 0.56, 0.7, 0.84]
        let tileW = Float(width) / Float(columns), tileH = Float(height) / Float(rows)
        for y in 0..<height {
            for x in 0..<width {
                let tx = min(columns - 1, Int(Float(x) / tileW)), ty = min(rows - 1, Int(Float(y) / tileH))
                let u = Float(x) / tileW - Float(tx), v = Float(y) / tileH - Float(ty)
                var hue = Float(tx) / Float(columns) * 2 * .pi
                var chroma: Float = ty < 4 ? 0.07 : 0.14
                var l = lightness[ty % 4] + 0.08 * (u - 0.5)
                let dx = (u - 0.7) * tileW, dy = (v - 0.35) * tileH
                if (tx + ty) % 3 == 0 && dx * dx + dy * dy < 25 {
                    hue += .pi
                    chroma = 0.1
                    l = 1.1 - l
                }
                let lab = SIMD3(l, chroma * cos(hue), chroma * sin(hue))
                var c = ColorScience.okLabToEncoded(lab, space: .sRGB) * 255
                c += SIMD3(rng.nextFloat(), rng.nextFloat(), rng.nextFloat()) * 12 - 6
                image[x, y] = SIMD4(
                    UInt8(min(max(c.x, 0), 255)), UInt8(min(max(c.y, 0), 255)), UInt8(min(max(c.z, 0), 255)), 255)
            }
        }
        return image
    }

    static func segment(
        _ image: RGBAImage, settings: GenerationSettings = GenerationSettings(), importance: Grid<Float>? = nil
    ) throws -> Segmentation {
        try Segmenter.segment(
            image, importance: importance,
            parameters: SegmentationParameters(settings: settings, width: image.width, height: image.height),
            cancel: .none, clock: StageClock(), progress: { _ in }
        ).segmentation
    }

    /// Structural invariants every segmentation made with `settings` must satisfy, the label
    /// room of every number included (the parameters' `minRadius(digits:)`). Pass
    /// `checksRoom: false` where the image is too small to have that guarantee (a 1-px strip
    /// holds no disc) or the test is about something else.
    static func checkInvariants(_ s: Segmentation, settings: GenerationSettings, checksRoom: Bool = true) {
        let p = SegmentationParameters(settings: settings, width: s.width, height: s.height)
        #expect(p.minPaletteDistance >= SegmentationParameters.jnd)
        let n = s.regionCount
        #expect(s.labels.count == s.width * s.height)
        #expect(n > 0 || s.labels.count == 0)
        // Region ids contiguous, every region used and 4-connected (relabelling by
        // components reproduces exactly the same regions).
        var used = [Bool](repeating: false, count: n)
        for l in s.labels.storage {
            #expect(Int(l) < n)
            if Int(l) < n { used[Int(l)] = true }
        }
        #expect(used.allSatisfy { $0 })
        let classes = Grid(width: s.width, height: s.height, storage: s.labels.storage.map { s.regionColor[Int($0)] })
        let cc = ConnectedComponents.label(classes)
        #expect(cc.count == n)
        #expect(cc.labels == s.labels)
        // Palette: every region color valid, every paint used, paints distinct.
        #expect(s.regionColor.allSatisfy { Int($0) < s.palette.count })
        var paintUsed = [Bool](repeating: false, count: s.palette.count)
        for c in s.regionColor { paintUsed[Int(c)] = true }
        #expect(paintUsed.allSatisfy { $0 })
        for i in 0..<s.palette.count {
            for j in (i + 1)..<s.palette.count {
                #expect(ColorScience.distance(s.palette[i].oklab, s.palette[j].oklab) >= p.minPaletteDistance - 1e-4)
            }
        }
        // Size guarantee: largest inscribed disc per region, scaled for multi-digit numbers.
        if checksRoom, n > 1 {
            let d = DistanceTransform.interiorDistance(labels: s.labels)
            var best = [Float](repeating: 0, count: n)
            for i in 0..<d.count { best[Int(s.labels.storage[i])] = max(best[Int(s.labels.storage[i])], d.storage[i]) }
            for r in 0..<n {
                let digits = LabelSizing.digitCount(colorIndex: s.regionColor[r])
                #expect(best[r] >= p.minRadius(digits: digits), "region \(r), \(digits) digits")
            }
        }
    }

    /// Blobby random paint, the shape real regions have: a coarse grid of `kinds` random paints
    /// upsampled by `cell`. Draws one number per coarse cell in raster order; `width` and
    /// `height` are multiples of `cell`.
    static func blobbyClasses(width w: Int, height h: Int, cell: Int, kinds: Int, rng: inout SplitMix64) -> [UInt32] {
        let columns = w / cell
        let coarse = (0..<(columns * (h / cell))).map { _ in UInt32(rng.next() % UInt64(kinds)) }
        var classes = [UInt32](repeating: 0, count: w * h)
        for y in 0..<h {
            for x in 0..<w { classes[y * w + x] = coarse[(y / cell) * columns + x / cell] }
        }
        return classes
    }
}
