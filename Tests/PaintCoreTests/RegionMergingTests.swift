import Foundation
import Testing
@testable import PaintCore

/// The region rules that keep photos from fragmenting into slivers or posterizing into
/// bands: low-contrast crumbs, transition strips and gradient bands.
@Suite("Region merging")
struct RegionMergingTests {

    // MARK: - Fixtures

    /// Parameters with every merge threshold set explicitly, so the tests pin the rules
    /// rather than the defaults.
    static func parameters(width w: Int, height h: Int) -> SegmentationParameters {
        var p = SegmentationParameters(settings: GenerationSettings(colorCount: 8), width: w, height: h)
        p.minArea = 30
        p.minRadius = 2.7
        p.openingRadiusSquared = 1
        p.boundaryPasses = 0
        p.mergeShareWeight = 0.04
        p.crumbContrast = 0.12
        p.crumbFloor = 0.2
        p.stripCompactness = 0.35
        p.stripWidth = 8.1
        p.stripMixture = 0.4
        p.stripContrast = 0.7
        return p
    }

    static func grey(_ l: Float) -> SIMD3<Float> { SIMD3(l, 0, 0) }

    /// Simplifies a paint map whose pixel colours are given per pixel; returns the paint of
    /// every pixel and the region count.
    static func simplify(
        _ classes: [UInt32], colors: [SIMD3<Float>], width w: Int, height h: Int, palette: [SIMD3<Float>]
    ) throws -> (classes: [UInt32], regions: Int) {
        var classes = classes
        let grid = Grid(width: w, height: h, storage: colors.map { SIMD4($0, 0) })
        let (regions, _) = try RegionSimplifier.simplify(
            classes: &classes, width: w, height: h, colors: grid, areaScale: [Float](repeating: 1, count: w * h),
            palette: palette, parameters: parameters(width: w, height: h), cancel: .none)
        return (classes, regions.count)
    }

    // MARK: - Crumbs

    @Test func lowContrastCrumbsMergeWhileDistinctSpotsStay() throws {
        // Two 8×10 blobs on a field, both well above the minimum area (30) and holding the
        // minimum disc: one barely differs from the field, the other clearly does.
        let w = 80, h = 40
        let palette = [Self.grey(0.5), Self.grey(0.53), Self.grey(0.75)]
        var classes = [UInt32](repeating: 0, count: w * h)
        for y in 15..<25 {
            for x in 10..<18 { classes[y * w + x] = 1 }
            for x in 50..<58 { classes[y * w + x] = 2 }
        }
        let colors = classes.map { palette[Int($0)] }
        let result = try Self.simplify(classes, colors: colors, width: w, height: h, palette: palette)
        #expect(result.regions == 2)
        #expect(!result.classes.contains(1))
        #expect(result.classes[20 * w + 54] == 2)
    }

    // MARK: - Transition strips

    /// A field of paint 0 (left) and paint 1 (right) with a 7-px strip of paint 2 along
    /// their border: wide enough to hold the minimum disc (a 6-px strip would be merged as
    /// too thin before any strip test) and far above the minimum area.
    static func stripScene(colorOf: (_ x: Int, _ paint: UInt32) -> SIMD3<Float>) -> (classes: [UInt32], colors: [SIMD3<Float>]) {
        let w = 90, h = 120
        var classes = [UInt32](repeating: 0, count: w * h)
        var colors = [SIMD3<Float>](repeating: .zero, count: w * h)
        for y in 0..<h {
            for x in 0..<w {
                let paint: UInt32 = x < 42 ? 0 : (x < 49 ? 2 : 1)
                classes[y * w + x] = paint
                colors[y * w + x] = colorOf(x, paint)
            }
        }
        return (classes, colors)
    }

    @Test func blurredEdgeStripMerges() throws {
        // The photo's edge is a ramp over 12 px: the strip's colours are mixes of its two
        // neighbours' paints and no border carries a real step.
        let palette = [Self.grey(0.3), Self.grey(0.7), Self.grey(0.5)]
        let scene = Self.stripScene { x, _ in
            Self.grey(0.3 + 0.4 * min(max((Float(x) - 38.5) / 12, 0), 1))
        }
        let result = try Self.simplify(scene.classes, colors: scene.colors, width: 90, height: 120, palette: palette)
        #expect(result.regions == 2)
        #expect(!result.classes.contains(2))
    }

    @Test func sharpEdgedStripStays() throws {
        // The same strip with hard colour steps on both sides is a real feature (a mid-grey
        // pole between a dark and a light wall).
        let palette = [Self.grey(0.3), Self.grey(0.7), Self.grey(0.5)]
        let scene = Self.stripScene { _, paint in palette[Int(paint)] }
        let result = try Self.simplify(scene.classes, colors: scene.colors, width: 90, height: 120, palette: palette)
        #expect(result.regions == 3)
        #expect(result.classes.contains(2))
    }

    @Test func stripOfItsOwnColourStays() throws {
        // A blurred edge again, but the strip's own colour lies off the line between its
        // neighbours' paints (a coloured whisker between two greys), so it is no mix.
        let palette = [Self.grey(0.3), Self.grey(0.7), SIMD3<Float>(0.5, 0.15, 0)]
        let scene = Self.stripScene { x, paint in
            var c = Self.grey(0.3 + 0.4 * min(max((Float(x) - 38.5) / 12, 0), 1))
            if paint == 2 { c.y = 0.15 }
            return c
        }
        let result = try Self.simplify(scene.classes, colors: scene.colors, width: 90, height: 120, palette: palette)
        #expect(result.regions == 3)
        #expect(result.classes.contains(2))
    }

    // MARK: - Boundary steps

    @Test func boundaryStepsMatchBruteForce() {
        var rng = SplitMix64(seed: 13)
        let w = 70, h = 90
        let coarse = (0..<(14 * 18)).map { _ in UInt32(rng.next() % 4) }
        var classes = [UInt32](repeating: 0, count: w * h)
        for y in 0..<h {
            for x in 0..<w { classes[y * w + x] = coarse[(y / 5) * 14 + x / 5] }
        }
        let colors = (0..<(w * h)).map { _ in SIMD4(rng.nextFloat(), rng.nextFloat(), rng.nextFloat(), 0) }
        let regions = RegionRuns(classes: classes, width: w, height: h)
        let adjacency = RegionAdjacency(regions)
        let metric = SIMD3<Float>(1, 0.5, 0.5)
        let steps = adjacency.boundarySteps(regions, colors: colors, metric: metric)
        #expect(steps.count == adjacency.pairs.count)
        let labels = regions.labelMap()
        var expected = [UInt64: Float]()
        func add(_ i: Int, _ j: Int) {
            let a = labels.storage[i], b = labels.storage[j]
            guard a != b else { return }
            let d = (colors[i] - colors[j]) * SIMD4(metric, 0)
            expected[RegionAdjacency.key(a, b), default: 0] += (d * d).sum().squareRoot()
        }
        for y in 0..<h {
            for x in 0..<w {
                if x + 1 < w { add(y * w + x, y * w + x + 1) }
                if y + 1 < h { add(y * w + x, (y + 1) * w + x) }
            }
        }
        for k in adjacency.pairs.indices {
            #expect(abs(steps[k] - expected[adjacency.pairs[k]]!) < 1e-3 * max(1, expected[adjacency.pairs[k]]!))
        }
    }

    // MARK: - Gradient bands

    /// A ramp sliced into ten 20-px bands of paints 0.02 apart, then a flat region whose
    /// paint is just as close to the last band's but meets it at a hard colour step.
    static func rampScene() -> (classes: [UInt32], colors: [SIMD4<Float>], palette: [SIMD3<Float>]) {
        let w = 240, h = 30
        var classes = [UInt32](repeating: 0, count: w * h)
        var colors = [SIMD4<Float>](repeating: .zero, count: w * h)
        for y in 0..<h {
            for x in 0..<w {
                let band = min(x / 20, 10)
                classes[y * w + x] = UInt32(band)
                let l: Float = band < 10 ? 0.29 + 0.001 * Float(x) : 0.5
                colors[y * w + x] = SIMD4(l, 0, 0, 0)
            }
        }
        let palette = (0...10).map { Self.grey(0.3 + 0.02 * Float($0)) }
        return (classes, colors, palette)
    }

    @Test func rampBandsFuseUpToToleranceAndContoursStay() throws {
        let (classes0, colors, palette) = Self.rampScene()
        let w = 240, h = 30
        for (importance, bandWidth, expectedRegions) in [(Float(1), Float(0), 5), (0, 40, 3)] {
            var classes = classes0
            var labelling = classes0
            var regions = RegionRuns(classes: classes, width: w, height: h)
            var adjacency = RegionAdjacency(regions)
            let merges = try BandMerging.apply(
                classes: &classes, labelling: &labelling, regions: &regions, adjacency: &adjacency, colors: colors,
                importance: [Float](repeating: importance, count: w * h), palette: palette,
                metric: SIMD3(repeating: 1), tolerance: (near: 0.045, band: 0.1), bandWidth: bandWidth, contrast: 0.25)
            // Closest pairs first, so bands fuse in threes (spread 0.04) at the near tolerance
            // and in sixes (spread 0.1) at the band tolerance; the contour never fuses.
            #expect(merges == 11 - expectedRegions)
            #expect(regions.count == expectedRegions)
            #expect(regions.classOf.last == 10)
            #expect(classes[15 * w + 239] == 10 && classes[15 * w + 199] != 10)
            // Absorbed bands report the fused paint as their own, so the palette refit
            // centres the paint on the whole fused ramp.
            for x in 0..<200 { #expect(labelling[15 * w + x] == classes[15 * w + x]) }
            let paints = Set(classes[(15 * w)..<(16 * w)])
            #expect(paints.count == expectedRegions)
            for k in adjacency.pairs.indices {
                let a = Int(adjacency.pairs[k] >> 32), b = Int(adjacency.pairs[k] & 0xFFFF_FFFF)
                #expect(regions.classOf[a] != regions.classOf[b])
            }
        }
    }

    // MARK: - End to end

    /// Regions touching the given pixel box.
    static func regions(of s: Segmentation, x: Range<Int>, y: Range<Int>) -> Set<UInt32> {
        var found = Set<UInt32>()
        for yy in y {
            for xx in x { found.insert(s.labels[xx, yy]) }
        }
        return found
    }

    @Test func linearGradientDoesNotBandBeyondWhatPaintsCanShow() throws {
        // A gentle grey ramp (480 px for 0.6 of lightness) over eight flat colour patches at
        // 150 colours: the palette slices the ramp into some 35 paints a couple of pixels of
        // lightness apart, which read as one smooth band each; the template must fuse them
        // until neighbouring bands are at least a just-noticeable step apart.
        let w = 480, h = 160
        var image = RGBAImage(width: w, height: h, fill: SIMD4(0, 0, 0, 255))
        let patches: [SIMD3<UInt8>] = [
            SIMD3(200, 40, 40), SIMD3(40, 160, 60), SIMD3(40, 80, 220), SIMD3(240, 200, 30),
            SIMD3(150, 60, 200), SIMD3(30, 190, 190), SIMD3(250, 130, 30), SIMD3(120, 80, 40),
        ]
        for y in 0..<h {
            for x in 0..<w {
                if y < 120 {
                    let v = UInt8(40 + 180 * x / (w - 1))
                    image[x, y] = SIMD4(v, v, v, 255)
                } else {
                    let p = patches[min(x / 60, patches.count - 1)]
                    image[x, y] = SIMD4(p.x, p.y, p.z, 255)
                }
            }
        }
        let s = try SegmentationTests.segment(image, settings: GenerationSettings(colorCount: 150))
        SegmentationTests.checkInvariants(s, minRadius: 2.7, minDistance: 0.016)
        // 0.6 of lightness at a tolerance near 0.045 leaves room for about 13 bands.
        let bands = Self.regions(of: s, x: 0..<w, y: 30..<90).count
        #expect(bands >= 6 && bands <= 16)
    }

    @Test func fineStripesNearAFaceDoNotFragment() throws {
        // A face-like disc striped at a period below the minimum disc (feather striations)
        // with a small dark eye, flagged as important: the stripes must not become dozens of
        // slivers or tiny numbered regions, and the eye keeps its own paint.
        let w = 240, h = 180
        var image = RGBAImage(width: w, height: h, fill: SIMD4(70, 110, 60, 255))
        for y in 0..<h {
            for x in 0..<w {
                let dx = x - 120, dy = y - 90
                guard dx * dx + dy * dy < 60 * 60 else { continue }
                var c: SIMD3<Int> = (x / 3) % 2 == 0 ? SIMD3(214, 168, 142) : SIMD3(176, 132, 108)
                let ex = x - 140, ey = y - 78
                if ex * ex + ey * ey < 25 { c = SIMD3(50, 35, 30) }
                image[x, y] = SIMD4(UInt8(c.x), UInt8(c.y), UInt8(c.z), 255)
            }
        }
        var importance = Grid<Float>(width: w, height: h, repeating: 0.2)
        for y in 30..<150 {
            for x in 60..<180 { importance[x, y] = 1 }
        }
        let s = try SegmentationTests.segment(image, settings: GenerationSettings(colorCount: 24), importance: importance)
        SegmentationTests.checkInvariants(s, minRadius: 2.7)
        let face = Self.regions(of: s, x: 70..<170, y: 40..<140)
        #expect(face.count <= 6)
        let eye = s.palette[Int(s.regionColor[Int(s.labels[140, 78])])].oklab
        let skin = s.palette[Int(s.regionColor[Int(s.labels[100, 110])])].oklab
        #expect(ColorScience.distance(eye, skin) > 0.3)
    }
}
