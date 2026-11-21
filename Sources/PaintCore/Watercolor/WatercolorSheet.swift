import Foundation

/// The paper a watercolor painting is laid on (painting-company row 373): a template's regions on
/// the simulation's grid, each region's paint as an optical density, the paper's tooth and the
/// slow noise that makes each wash its own. Everything here is fixed for a painting: it is made
/// once from the template and the painting's seed, the same on every launch, and
/// `WatercolorSim` moves the water and pigment over it.
///
/// The grid is the template at most `longSide` cells on its long side (canvas units scaled by
/// `scale`), each cell the region under its centre. Optics are Beer–Lambert's: reflectance is the
/// paper's color times e^(−density), per channel in linear Display P3, so glazes darken as
/// transparent layers do and an even deposit of a region's `want` gives its paint.
public struct WatercolorSheet: Sendable {
    /// The grid's long side: the spike's working size (painting-company
    /// `spikes/2026-11-20-watercolor`), where a wash's rim, bloom and granulation read at the
    /// app's zooms without the whole sheet costing more than a frame's share to step.
    public static let longSide = 800
    /// The paper's own color, linear Display P3: a warm white the paints are measured against.
    public static let paperColor = SIMD3<Float>(0.90, 0.87, 0.80)

    public let width: Int
    public let height: Int
    /// Cells per canvas unit.
    public let scale: Float
    /// The region of each cell, row-major.
    public let labels: [Int32]
    public let regionCount: Int
    /// Each region's paint as a density with the watercolor key laid on it (`density(of:area:)`).
    public let want: [SIMD3<Float>]
    /// Each region's paint encoded 0…1 in the template's space: how it granulates.
    public let encoded: [SIMD3<Float>]
    /// Each region's wash group (`washGroups`): neighbours a painter would lay as one wash.
    public let group: [Int32]
    /// Regions no more than about three cells across anywhere (a trim, a rail, a sliver of
    /// leaves): too narrow to hold a wash of their own on the grid, where each became a blocky
    /// line. They don't stop their neighbours' water, and their paint is laid as a glaze where
    /// they are drawn, at the template's own resolution (`WatercolorSim.glaze(of:)`).
    public let thin: [Bool]
    /// Each region's cells' bounding box on the grid, `x0, y0, x1, y1` (exclusive); empty
    /// (x0 == x1) for a region too small to hold a cell.
    public let bounds: [SIMD4<Int32>]
    /// The cells of each region, in raster order: region `r`'s are
    /// `regionCells[regionStart[r]..<regionStart[r + 1]]` (the target solve reads only its own).
    public let regionCells: [Int32]
    public let regionStart: [Int32]
    /// Each region's area at the app's working size, for the key: big flat areas go thinner.
    public let workingArea: [Float]
    /// The paper's height, 0…1: its tooth (capillarity, granulation's valleys).
    public let paper: [Float]
    /// Slow noise, unit spread: where the pencil line gives way, the tap's front's jitter.
    public let lowFrequency: [Float]
    /// How unevenly water goes on, how pigment loads, how evaporation runs: unit spread each.
    public let waterNoise: [Float]
    public let pigmentNoise: [Float]
    public let evaporationNoise: [Float]
    public let seed: UInt64

    public init(template t: Template, seed: UInt64) {
        let long = max(t.width, t.height, 1)
        let s = min(1, Float(Self.longSide) / Float(long))
        let w = max(1, Int((Float(t.width) * s).rounded())), h = max(1, Int((Float(t.height) * s).rounded()))
        width = w
        height = h
        scale = Float(w) / Float(max(t.width, 1))
        self.seed = seed
        regionCount = t.regions.count

        var labels = [Int32](repeating: 0, count: w * h)
        let map = t.regionMap
        for y in 0..<h {
            let ty = min(map.height - 1, Int((Float(y) + 0.5) / scale))
            for x in 0..<w {
                let tx = min(map.width - 1, Int((Float(x) + 0.5) / scale))
                let r = map.contains(x: tx, y: ty) ? Int32(map[tx, ty]) : 0
                labels[y * w + x] = r < Int32(t.regions.count) ? r : 0
            }
        }
        self.labels = labels

        var bounds = [SIMD4<Int32>](repeating: SIMD4(Int32.max, Int32.max, 0, 0), count: regionCount)
        for y in 0..<h {
            for x in 0..<w {
                let r = Int(labels[y * w + x])
                var b = bounds[r]
                b = SIMD4(min(b.x, Int32(x)), min(b.y, Int32(y)), max(b.z, Int32(x + 1)), max(b.w, Int32(y + 1)))
                bounds[r] = b
            }
        }
        self.bounds = bounds.map { $0.x == Int32.max ? SIMD4(0, 0, 0, 0) : $0 }
        var start = [Int32](repeating: 0, count: regionCount + 1)
        for r in labels { start[Int(r) + 1] += 1 }
        for r in 0..<regionCount { start[r + 1] += start[r] }
        var next = start
        var cells = [Int32](repeating: 0, count: w * h)
        for (i, r) in labels.enumerated() {
            cells[Int(next[Int(r)])] = Int32(i)
            next[Int(r)] += 1
        }
        regionCells = cells
        regionStart = start

        let working = Float(1100) / Float(long)
        workingArea = t.regions.map { $0.area * working * working }
        encoded = t.regions.map { region in
            let i = Int(region.colorIndex)
            return i < t.palette.count ? t.palette[i].rgb : SIMD3(repeating: 1)
        }
        let space = t.colorSpace
        want = zip(encoded, workingArea).map { Self.density(of: Self.linearP3($0.0, space: space), area: $0.1) }

        paper = Self.paperHeight(width: w, height: h, seed: seed &+ 3)
        lowFrequency = Self.field(width: w, height: h, sigma: 6, seed: seed &+ 7)
        waterNoise = Self.mix(Self.field(width: w, height: h, sigma: 10, seed: seed &+ 21), 0.7,
                              Self.field(width: w, height: h, sigma: 3, seed: seed &+ 24), 0.3)
        pigmentNoise = Self.field(width: w, height: h, sigma: 16, seed: seed &+ 22)
        evaporationNoise = Self.mix(Self.field(width: w, height: h, sigma: 12, seed: seed &+ 23), 0.8,
                                    Self.field(width: w, height: h, sigma: 4, seed: seed &+ 25), 0.2)
        group = Self.washGroups(labels: labels, width: w, height: h, want: want)
        thin = Self.thinRegions(labels: labels, width: w, height: h, count: regionCount)
    }

    /// A region is thin when none of its cells lies more than a cell from its edge.
    static func thinRegions(labels: [Int32], width w: Int, height h: Int, count: Int) -> [Bool] {
        var edge = [Bool](repeating: false, count: w * h)
        for y in 0..<h {
            for x in 0..<w {
                let i = y * w + x, r = labels[i]
                if (x > 0 && labels[i - 1] != r) || (x + 1 < w && labels[i + 1] != r)
                    || (y > 0 && labels[i - w] != r) || (y + 1 < h && labels[i + w] != r) { edge[i] = true }
            }
        }
        let inside = WatercolorSim.chamfer(seeds: edge, width: w, height: h)
        var deepest = [Float](repeating: -1, count: count)
        for (i, r) in labels.enumerated() { deepest[Int(r)] = max(deepest[Int(r)], inside[i]) }
        return deepest.map { $0 >= 0 && $0 <= 1 }
    }

    /// The region of a canvas point, nil off the sheet.
    public func cell(at canvas: SIMD2<Float>) -> (x: Int, y: Int)? {
        guard canvas.x.isFinite, canvas.y.isFinite else { return nil }
        let x = Int((canvas.x * scale).rounded(.down)), y = Int((canvas.y * scale).rounded(.down))
        guard x >= 0, y >= 0, x < width, y < height else { return nil }
        return (x, y)
    }

    // MARK: Paint

    /// An encoded color of the template's space as linear Display P3.
    public static func linearP3(_ encoded: SIMD3<Float>, space: RGBColorSpace) -> SIMD3<Float> {
        let linear = SIMD3(ColorScience.decodeSRGB(encoded.x), ColorScience.decodeSRGB(encoded.y), ColorScience.decodeSRGB(encoded.z))
        return space == .displayP3 ? linear : ColorScience.sRGBToP3Linear(linear)
    }

    /// The density that, laid evenly on the paper, gives `color` (linear P3), with the
    /// watercolor key: lights become thin washes the paper glows through and big flat areas go
    /// lighter still, while darks keep their weight, so the picture reads as watercolor and not
    /// as a photo through a filter (the spike's first critic round).
    public static func density(of color: SIMD3<Float>, area: Float) -> SIMD3<Float> {
        var k = SIMD3<Float>(repeating: 0)
        for c in 0..<3 {
            k[c] = -log(min(max(color[c] / paperColor[c], 0.008), 1))
        }
        let mean = (k.x + k.y + k.z) / 3
        var s = min(max(0.22 + 0.32 * mean, 0.3), 1)
        s *= 1 - 0.3 * min(max((area - 2000) / 20000, 0), 1)
        return k * s
    }

    /// How strongly a paint granulates: earths and blues settle into the paper's valleys
    /// (ultramarine, burnt umber); clean brights barely do.
    public static func granulation(of encoded: SIMD3<Float>) -> Float {
        let blue = max(0, encoded.z - max(encoded.x, encoded.y))
        let hi = max(encoded.x, encoded.y, encoded.z), lo = min(encoded.x, encoded.y, encoded.z)
        let mean = (encoded.x + encoded.y + encoded.z) / 3
        return 0.25 + 2.5 * blue + 0.6 * max(0, 0.35 - (hi - lo)) * (1 - mean)
    }

    /// Neighbouring regions whose paints are close enough to be one wash to a painter: a new wash
    /// runs on into a dry one of the group and softens its rim (lost edges), so only the
    /// picture's real edges stay crisp (the spike's second critic round). Union-find over the
    /// grid's adjacent pairs, joined in a fixed order.
    static func washGroups(labels: [Int32], width w: Int, height h: Int, want: [SIMD3<Float>], close: Float = 0.4) -> [Int32] {
        var parent = (0..<want.count).map { Int32($0) }
        func find(_ a: Int32) -> Int32 {
            var a = a
            while parent[Int(a)] != a {
                parent[Int(a)] = parent[Int(parent[Int(a)])]
                a = parent[Int(a)]
            }
            return a
        }
        var pairs = Set<UInt64>()
        for y in 0..<h {
            for x in 0..<w {
                let a = labels[y * w + x]
                if x + 1 < w, labels[y * w + x + 1] != a { pairs.insert(Self.pair(a, labels[y * w + x + 1])) }
                if y + 1 < h, labels[(y + 1) * w + x] != a { pairs.insert(Self.pair(a, labels[(y + 1) * w + x])) }
            }
        }
        for key in pairs.sorted() {
            let a = Int32(truncatingIfNeeded: key >> 32), b = Int32(truncatingIfNeeded: key & 0xFFFF_FFFF)
            let ka = want[Int(a)], kb = want[Int(b)]
            let d = SIMD3<Float>(Swift.abs(ka.x - kb.x), Swift.abs(ka.y - kb.y), Swift.abs(ka.z - kb.z))
            let diff = max(d.x, d.y, d.z) / max(0.35, 0.5 * ((ka.x + ka.y + ka.z) / 3 + (kb.x + kb.y + kb.z) / 3))
            if diff < close {
                let ra = find(a), rb = find(b)
                if ra != rb { parent[Int(ra)] = rb }
            }
        }
        return (0..<want.count).map { find(Int32($0)) }
    }

    private static func pair(_ a: Int32, _ b: Int32) -> UInt64 {
        let lo = UInt64(UInt32(bitPattern: min(a, b))), hi = UInt64(UInt32(bitPattern: max(a, b)))
        return lo << 32 | hi
    }

    // MARK: Paper and noise

    /// Cold-press paper: blurred noise at four scales, fine grain to a slow undulation, 0…1.
    public static func paperHeight(width w: Int, height h: Int, seed: UInt64) -> [Float] {
        var p = [Float](repeating: 0, count: w * h)
        let scales: [(Float, Float)] = [(0.7, 0.45), (1.6, 0.35), (3.5, 0.15), (10, 0.05)]
        for (i, (sigma, weight)) in scales.enumerated() {
            let f = field(width: w, height: h, sigma: sigma, seed: seed &+ UInt64(i) &* 977)
            for j in p.indices { p[j] += weight * f[j] }
        }
        let lo = p.min() ?? 0, hi = p.max() ?? 1
        let span = max(hi - lo, 1e-6)
        return p.map { ($0 - lo) / span }
    }

    /// Gaussian noise blurred to about `sigma` cells, scaled to unit spread.
    public static func field(width w: Int, height h: Int, sigma: Float, seed: UInt64) -> [Float] {
        var rng = SplitMix64(seed: seed)
        var f = [Float](repeating: 0, count: w * h)
        for i in f.indices {
            // Box–Muller.
            let u = max(rng.nextFloat(), 1e-7), v = rng.nextFloat()
            f[i] = (-2 * log(u)).squareRoot() * cos(2 * Float.pi * v)
        }
        blur(&f, width: w, height: h, sigma: sigma)
        var sum: Double = 0, sq: Double = 0
        for x in f { sum += Double(x); sq += Double(x) * Double(x) }
        let n = Double(max(f.count, 1))
        let sd = Float(max((sq / n - (sum / n) * (sum / n)).squareRoot(), 1e-9))
        let mean = Float(sum / n)
        return f.map { ($0 - mean) / sd }
    }

    static func mix(_ a: [Float], _ wa: Float, _ b: [Float], _ wb: Float) -> [Float] {
        zip(a, b).map { wa * $0.0 + wb * $0.1 }
    }

    /// A Gaussian of about `sigma`: one [1 2 1] pass below 1, else three box passes of the radius
    /// whose variance matches (r(r+1) = σ²), edges clamped.
    static func blur(_ a: inout [Float], width w: Int, height h: Int, sigma: Float) {
        if sigma < 1 {
            WatercolorBlur.tent(&a, width: w, height: h)
            return
        }
        let r = max(1, Int(((sigma * sigma + 0.25).squareRoot() - 0.5).rounded()))
        for _ in 0..<3 { WatercolorBlur.box(&a, width: w, height: h, radius: r, box: (0, 0, w, h)) }
    }
}

/// Separable blurs over a part of a grid, edges clamped to that part.
enum WatercolorBlur {
    /// A box of `radius` along rows then columns inside `box` (x0, y0, x1, y1), every row and
    /// column summed in order, so the same input gives the same output on every device.
    static func box(_ a: inout [Float], width w: Int, height: Int, radius r: Int, box: (Int, Int, Int, Int)) {
        let (x0, y0, x1, y1) = box
        let bw = x1 - x0, bh = y1 - y0
        guard bw > 0, bh > 0 else { return }
        let norm = 1 / Float(2 * r + 1)
        var line = [Float](repeating: 0, count: max(bw, bh))
        a.withUnsafeMutableBufferPointer { a in
            for y in y0..<y1 {
                let row = y * w
                for i in 0..<bw { line[i] = a[row + x0 + i] }
                var sum: Float = 0
                for k in -r...r { sum += line[min(max(k, 0), bw - 1)] }
                for i in 0..<bw {
                    a[row + x0 + i] = sum * norm
                    sum += line[min(i + r + 1, bw - 1)] - line[max(i - r, 0)]
                }
            }
            for x in x0..<x1 {
                for i in 0..<bh { line[i] = a[(y0 + i) * w + x] }
                var sum: Float = 0
                for k in -r...r { sum += line[min(max(k, 0), bh - 1)] }
                for i in 0..<bh {
                    a[(y0 + i) * w + x] = sum * norm
                    sum += line[min(i + r + 1, bh - 1)] - line[max(i - r, 0)]
                }
            }
        }
    }

    /// [1 2 1] / 4 along rows then columns over the whole grid.
    static func tent(_ a: inout [Float], width w: Int, height h: Int) {
        var b = a
        for y in 0..<h {
            for x in 0..<w {
                let l = a[y * w + max(x - 1, 0)], c = a[y * w + x], r = a[y * w + min(x + 1, w - 1)]
                b[y * w + x] = 0.25 * l + 0.5 * c + 0.25 * r
            }
        }
        for y in 0..<h {
            for x in 0..<w {
                let u = b[max(y - 1, 0) * w + x], c = b[y * w + x], d = b[min(y + 1, h - 1) * w + x]
                a[y * w + x] = 0.25 * u + 0.5 * c + 0.25 * d
            }
        }
    }
}
