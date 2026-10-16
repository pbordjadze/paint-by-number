import PaintCore

/// Where step 3 drops a seed of k-means++: a pixel of the smoothed picture, the moment it lands
/// and the paint it is nearest to.
public struct PaintSeed: Sendable, Equatable {
    public var time: Double
    public var x: Double
    public var y: Double
    /// An index into `PaintColors.keys`.
    public var paint: Int

    public init(time: Double, x: Double, y: Double, paint: Int) {
        self.time = time
        self.x = x
        self.y = y
        self.paint = paint
    }
}

/// The paints of the palette picture: its distinct colors, ascending as `r << 16 | g << 8 | b`,
/// and for each pixel the index of its color among them (an `Int32` like every area label, so
/// `PaintFlow` takes it as it is).
struct PaintColors: Sendable, Equatable {
    var keys: [UInt32]
    var index: Plane<Int32>

    /// The most colors a palette picture may have: it holds dozens, and a picture with this many
    /// is not one.
    static let maximum = 1 << 16

    init(palette: Plane<SIMD4<UInt8>>) throws {
        var seen = Set<UInt32>()
        var previous: UInt32?
        for c in palette.data {
            let key = ExactMath.colorKey(c)
            if key != previous { seen.insert(key) }
            previous = key
        }
        guard seen.count <= Self.maximum else { throw ShowPicturesError(description: "the palette picture has \(seen.count) colors") }
        keys = seen.sorted()
        let place = Dictionary(uniqueKeysWithValues: keys.enumerated().map { ($1, Int32($0)) })
        index = Plane(width: palette.width, height: palette.height, data: palette.data.map { place[ExactMath.colorKey($0)]! })
    }

    /// The color of paint `i`.
    func rgb(_ i: Int) -> SIMD3<UInt8> {
        SIMD3(UInt8(keys[i] >> 16 & 255), UInt8(keys[i] >> 8 & 255), UInt8(keys[i] & 255))
    }
}

enum PaintSeeds {
    /// The chroma axes' stretch, as in the segmentation grid.
    static let chroma = 1.6

    /// k-means++ seeding (Arthur and Vassilvitskii 2007) over the rows of `lab`: the first seed at
    /// random, each next one drawn with probability proportional to its squared distance to the
    /// nearest seed so far, by one draw of `rng` each (`kmeanspp` in `making_of_inputs.py`). Returns
    /// the chosen indices in order, at most one per row; once every row is a seed's twin, a seed is
    /// any row.
    static func kmeansPlusPlus(_ lab: [SIMD3<Double>], count k: Int, rng: inout SplitMix64) -> [Int] {
        let n = lab.count
        guard n > 0 else { return [] }
        let first = rng.below(n)
        var order = [first]
        var d2 = lab.map { ExactMath.distance2($0, lab[first]) }
        for _ in 0..<max(min(k, n) - 1, 0) {
            let cdf = ExactMath.cumulative(d2)
            let total = cdf[n - 1]
            let c = total > 0 ? ExactMath.bisectRight(cdf, rng.nextDouble() * total) : rng.below(n)
            order.append(c)
            for i in 0..<n { d2[i] = min(d2[i], ExactMath.distance2(lab[i], lab[c])) }
        }
        return order
    }

    /// The seeds a show drops: `seeds(smoothed:...)` from the show's own `.seeds` stream, dropping
    /// from the paints step of the spec's timing as the plan file keeps it (4 decimals), so the crew's
    /// show and the field show drop the same ones.
    static func seeds(pictures: ShowPictures, paints: PaintColors, spec: ShowSpec, seed: UInt64) -> [PaintSeed] {
        let intro = ExactMath.quantize(spec.timing.intro, decimals: 4)
        let step = ExactMath.quantize(spec.timing.step, decimals: 4)
        var stream = ShowStreams(seed: seed).stream(.seeds, 0)
        return seeds(
            smoothed: pictures.smoothed, paints: paints, rng: &stream, start: intro + 2 * step,
            dropEvery: spec.seeds.dropEvery)
    }

    /// Step 3's seeds: pixels of the smoothed picture on a grid 6 px apart, below the sketch's top
    /// and off the sides, chosen by k-means++ in OKLab for as many seeds as there are paints, each
    /// snapped to the paint nearest in color. They drop one after another from `start`, `dropEvery`
    /// apart or faster, to fill a second.
    static func seeds(
        smoothed: Plane<SIMD4<UInt8>>, paints: PaintColors, rng: inout SplitMix64, start: Double, dropEvery: Double
    ) -> [PaintSeed] {
        let w = smoothed.width, h = smoothed.height
        let rows = Array(stride(from: truncated(0.12 * Double(h)) + 4, to: h - 8, by: 6))
        let columns = Array(stride(from: truncated(0.05 * Double(w)), to: w - truncated(0.05 * Double(w)), by: 6))
        func lab(_ c: SIMD4<UInt8>) -> SIMD3<Double> { ExactMath.oklab(c.x, c.y, c.z, chroma: chroma) }
        let samples = rows.flatMap { y in columns.map { x in lab(smoothed.data[y * w + x]) } }
        let paintLab = (0..<paints.keys.count).map { i -> SIMD3<Double> in
            let c = paints.rgb(i)
            return ExactMath.oklab(c.x, c.y, c.z, chroma: chroma)
        }
        let picks = kmeansPlusPlus(samples, count: paints.keys.count, rng: &rng)
        let gap = picks.isEmpty ? 0 : min(dropEvery, 1.0 / Double(picks.count))
        return picks.enumerated().map { j, c in
            var nearest = 0
            var best = ExactMath.distance2(paintLab[0], samples[c])
            for i in 1..<paintLab.count {
                let d = ExactMath.distance2(paintLab[i], samples[c])
                if d < best { (best, nearest) = (d, i) }
            }
            return PaintSeed(
                time: start + 0.12 + Double(j) * gap, x: Double(columns[c % columns.count]), y: Double(rows[c / columns.count]),
                paint: nearest)
        }
    }
}
