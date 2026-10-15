import Foundation
import PaintCore

/// The look of the show's pictures: every number the layers and the `Compositor` use that the
/// spec (`ShowSpec.tones`, `.sketch`) does not set. `tools/factory/making_of_layers.py` has the
/// same struct, field for field (`RevealStyle`, in snake_case), and `LayersTests` compares the two.
/// Seconds are the ramps a change takes to come in; colors are `paper` and `ink` in 0...255 and
/// `graphite` in 0...1.
public struct RevealStyle: Sendable, Equatable {
    public var paper = SIMD3<Double>(247, 244, 238)
    public var graphite = SIMD3<Double>(0.30, 0.29, 0.31)
    public var ink = SIMD3<Double>(0x34, 0x2A, 0x30)
    /// How bright a color looks, for draining it to grey.
    public var luma = SIMD3<Double>(0.2126, 0.7152, 0.0722)

    /// The relative total variation window's radius, in pixels of a 1024 px wide picture.
    public var rtvWindow = 4.0
    /// Chroma is stretched as the segmentation grid is.
    public var rtvChroma = 1.6
    /// Keeps the ratio finite where nothing varies.
    public var rtvEpsilon = 1e-4
    /// The pipeline's: coherence to this power is how structured a pixel is.
    public var structureExponent = 3.0
    /// The survivors are rescaled to reach the structure's own value at this percentile.
    public var survivorPercentile = 99.5
    /// The percentile of the variation that counts as busy.
    public var variationPercentile = 90.0
    public var percentileEpsilon = 1e-6
    public var textureGain = 1.4

    /// Percentiles of lightness that are black and white of the tone curve.
    public var tonePercentiles = SIMD2<Double>(1, 99)
    /// A flat picture still has a span.
    public var toneSpanFloor = 1e-6
    /// What the bisection of the curve's exponent brackets: `t ** g` averages less as g grows.
    public var toneGammaRange = SIMD2<Double>(0.05, 20)
    public var toneBisections = 40

    /// Structure below this leaves no graphite.
    public var graphiteFloor = 0.05
    public var graphiteSpan = 0.45
    public var graphiteExponent = 0.8
    /// The darkest graphite, before a layer's strength.
    public var graphiteDensity = 0.8
    /// The graphite's strength in layers 1 to 3.
    public var sketchStrengths = SIMD3<Double>(1.0, 0.8, 0.35)
    /// How far layer 2 goes to the smoothed picture's lightness.
    public var washStrength = 0.35
    /// How much of the greys the ink step lifts.
    public var liftShare = 0.5

    /// Step 1: the photo's texture smears away.
    public var smearRamp = 0.3
    /// Then its color drains.
    public var drainDelay = 0.1
    public var drainRamp = 0.5
    /// Graphite goes down, strongest structure first.
    public var graphiteDelay = 0.35
    public var graphiteByStructure = 0.25
    /// Graphite is down this long before the step ends.
    public var graphiteMargin = 0.4
    public var graphiteRamp = 0.16
    /// The photo fades to paper behind the graphite.
    public var washDelay = 0.45
    public var washMargin = 0.8
    public var washRamp = 0.7
    /// Step 2's edge is soft.
    public var softEarly = 0.16
    /// Steps 3 and 4 are crisper.
    public var softLate = 0.09
    /// How much a layer changes, to how dark it dips as the paint settles.
    public var settleGain = 12.0
    public var settleRamp = 0.22
    public var settleDepth = 0.1
    /// Step 5: a region's grey lifts.
    public var liftRamp = 0.12
    /// Step 6: a region clears to paper.
    public var clearRamp = 0.12

    public static let standard = RevealStyle()

    public init() {}
}

/// Maps lightness onto greys from `tones.low` to `tones.high`, bent so a picture averages
/// `tones.mean`: the Snow Queen's lighter, clearer greys. Made from the picture's paints and their
/// pixel counts (the simplified picture is flat, so there is one lightness per paint), which is
/// exact, and a few dozen powers instead of forty per pixel. Every stage after it gets the same
/// curve and changes only where the picture does. `ToneCurve` in `making_of_layers.py` is the same.
public struct ToneCurve: Sendable, Equatable {
    /// The greys of the darkest and the lightest.
    public let low: Double
    public let high: Double
    /// The lightness that maps to `low`, and the span to `high`.
    public let darkest: Double
    public let span: Double
    /// The exponent that bends the curve.
    public let gamma: Double

    /// The curve of a picture with these paints, each covering this many pixels.
    public init(paints: [(color: SIMD4<UInt8>, pixels: Int)], tones: ShowSpec.Tones, style: RevealStyle = .standard) {
        let sorted = paints.map { (lightness: LayerColor.lightness($0.color), key: LayerColor.key($0.color), pixels: $0.pixels) }
            .sorted { $0.lightness != $1.lightness ? $0.lightness < $1.lightness : $0.key < $1.key }
        let values = sorted.map(\.lightness)
        let counts = sorted.map(\.pixels)
        precondition(counts.reduce(0, +) > 0, "a tone curve needs a picture")
        let darkest = Self.percentile(values, counts: counts, style.tonePercentiles.x)
        let lightest = Self.percentile(values, counts: counts, style.tonePercentiles.y)
        let span = max(lightest - darkest, style.toneSpanFloor)
        let t = values.map { min(max(($0 - darkest) / span, 0), 1) }
        let want = (tones.mean - tones.low) / (tones.high - tones.low)
        let total = Double(counts.reduce(0, +))
        func average(_ g: Double) -> Double {
            var sum = 0.0
            for (t, count) in zip(t, counts) { sum += Double(count) * pow(t, g) }       // in order
            return sum / total
        }
        var (a, b) = (style.toneGammaRange.x, style.toneGammaRange.y)
        for _ in 0..<style.toneBisections {
            let g = (a * b).squareRoot()
            if average(g) > want { a = g } else { b = g }
        }
        self.low = tones.low
        self.high = tones.high
        self.darkest = darkest
        self.span = span
        self.gamma = (a * b).squareRoot()
    }

    /// The curve of a flat picture, its paints counted.
    public init(counting picture: Plane<SIMD4<UInt8>>, tones: ShowSpec.Tones, style: RevealStyle = .standard) {
        var counts: [UInt32: Int] = [:]
        var run = 0
        var previous: UInt32?
        for color in picture.data {          // most pixels repeat the one before
            let key = LayerColor.key(color)
            if key == previous { run += 1; continue }
            if let previous { counts[previous, default: 0] += run }
            previous = key
            run = 1
        }
        if let previous { counts[previous, default: 0] += run }
        self.init(paints: counts.map { (SIMD4<UInt8>(UInt8($0.key >> 16), UInt8(($0.key >> 8) & 255), UInt8($0.key & 255), 255), $0.value) },
                  tones: tones, style: style)
    }

    /// The grey of a lightness.
    public func grey(lightness: Double) -> Double {
        low + (high - low) * pow(min(max((lightness - darkest) / span, 0), 1), gamma)
    }

    /// The grey of an 8-bit sRGB color (its alpha is ignored).
    public func grey(of color: SIMD4<UInt8>) -> Double {
        grey(lightness: LayerColor.lightness(color))
    }

    /// `numpy.percentile(numpy.repeat(values, counts), q)` (its linear method, with its lerp)
    /// without repeating: `values` ascending, each seen `counts` times.
    static func percentile(_ values: [Double], counts: [Int], _ q: Double) -> Double {
        var cumulative = [Int](repeating: 0, count: counts.count)
        var sum = 0
        for (i, count) in counts.enumerated() { sum += count; cumulative[i] = sum }
        let (index, gamma) = virtualIndex(sum, q)
        func statistic(_ rank: Int) -> Double {      // the first value whose running count passes `rank`
            var lo = 0
            var hi = cumulative.count
            while lo < hi {
                let mid = (lo + hi) / 2
                if cumulative[mid] <= rank { lo = mid + 1 } else { hi = mid }
            }
            return values[lo]
        }
        return lerp(statistic(index), statistic(min(index + 1, sum - 1)), gamma)
    }

    /// `numpy.percentile` of non-negative values, in any order, without sorting them all.
    static func percentile(of values: [Float], _ q: Double) -> Double {
        let (index, gamma) = virtualIndex(values.count, q)
        return lerp(Double(order(index, of: values)), Double(order(min(index + 1, values.count - 1), of: values)), gamma)
    }

    /// The value a full sort would put at `rank` (from 0) among non-negative values: a histogram of
    /// their top 16 bits, which order like the values, finds the bucket it is in, and only that
    /// bucket is sorted.
    static func order(_ rank: Int, of values: [Float]) -> Float {
        var counts = [Int](repeating: 0, count: 1 << 16)
        for value in values { counts[Int(value.bitPattern >> 16)] += 1 }
        var before = 0
        var bucket = 0
        while before + counts[bucket] <= rank {
            before += counts[bucket]
            bucket += 1
        }
        return values.filter { Int($0.bitPattern >> 16) == bucket }.sorted()[rank - before]
    }

    /// Where numpy's linear method looks among `n` sorted values for the percentile `q`: the rank
    /// below, and how far toward the next.
    private static func virtualIndex(_ n: Int, _ q: Double) -> (Int, Double) {
        let virtual = q / 100 * Double(n - 1)
        let index = Int(virtual.rounded(.down))
        return (index, virtual - Double(index))
    }

    private static func lerp(_ a: Double, _ b: Double, _ gamma: Double) -> Double {
        let difference = b - a
        return gamma >= 0.5 ? b - difference * (1 - gamma) : a + difference * gamma
    }
}

/// What the pipeline's stages say about one generation's pictures, and the greys the layers are
/// made of: the relative total variation (how coherent the color steps are over a window, 1 for a
/// contour and 0 for texture), the `survivors` of it on the structure map, the `texture`, the
/// photo with its texture smeared away (`detextured`) and the tone curve of the paints. All at the
/// pictures' own size, in Double and summed in a fixed order, so a result never depends on the
/// core count; `derive` in `making_of_layers.py` is the reference, compared within the tolerances
/// `LayersTests` states (continuous math, never bit for bit).
public struct ShowLayers: Sendable {
    public let width: Int
    public let height: Int
    public let style: RevealStyle
    public let photo: Plane<SIMD4<UInt8>>
    /// How coherent the photo's color steps are over the window: 1 on a contour, 0 on texture.
    public let coherence: Plane<Float>
    /// The structure that survives the coherence, rescaled; 0...1.
    public let survivors: Plane<Float>
    /// Where the steps cancel and there are many of them; 0...1.
    public let texture: Plane<Float>
    public let detextured: Plane<SIMD3<Float>>
    /// OKLab lightness of the smoothed picture.
    public let smoothedLightness: Plane<Float>
    public let tone: ToneCurve
    /// The tone curve's grey of the palette picture, and of the simplified one.
    public let paletteGrey: Plane<Float>
    public let simplifiedGrey: Plane<Float>

    /// Rows a worker takes at once: halos add `4 * radius` rows to each, and the result does not
    /// depend on it.
    private static let chunkRows = 32

    public init(
        photo: Plane<SIMD4<UInt8>>, structure: Plane<UInt8>, smoothed: Plane<SIMD4<UInt8>>,
        palette: Plane<SIMD4<UInt8>>, simplified: Plane<SIMD4<UInt8>>,
        sketch: ShowSpec.Sketch, tones: ShowSpec.Tones,
        style: RevealStyle = .standard, cancel: CancellationCheck = .none
    ) throws {
        let (w, h) = (photo.width, photo.height)
        precondition(w > 0 && h > 0, "the show needs a picture")
        for size in [(structure.width, structure.height), (smoothed.width, smoothed.height),
                     (palette.width, palette.height), (simplified.width, simplified.height)] {
            precondition(size == (w, h), "the stage pictures share one size")
        }
        self.width = w
        self.height = h
        self.style = style
        self.photo = photo

        let radius = Self.windowRadius(forWidth: w, style)
        var coherence = Plane<Float>(width: w, height: h, repeating: 0)
        var variation = Plane<Float>(width: w, height: h, repeating: 0)
        coherence.data.withUnsafeMutableBufferPointer { cohBuffer in
            variation.data.withUnsafeMutableBufferPointer { varBuffer in
                let coh = UncheckedSendable(cohBuffer.baseAddress!)
                let vari = UncheckedSendable(varBuffer.baseAddress!)
                Parallel.forEachChunk(h, chunk: Self.chunkRows) { rows in
                    let part = Self.relativeTotalVariation(of: photo, rows: rows, radius: radius, style: style)
                    for (i, (c, v)) in zip(part.coherence, part.variation).enumerated() {
                        coh.value[rows.lowerBound * w + i] = Float(c)
                        vari.value[rows.lowerBound * w + i] = Float(v)
                    }
                }
            }
        }
        try cancel.throwIfCancelled()

        // graphite only on what survives: structure where the steps agree, as strong as before
        var histogram = [Int](repeating: 0, count: 256)
        for value in structure.data { histogram[Int(value)] += 1 }
        let structureTop = ToneCurve.percentile((0..<256).map { Double($0) / 255 }, counts: histogram, style.survivorPercentile)
        var kept = Plane<Float>(width: w, height: h, repeating: 0)
        Self.fill(&kept) { i in
            let keep = pow(min(max((Double(coherence.data[i]) - sketch.coherenceFrom) / sketch.coherenceSpan, 0), 1), sketch.coherenceExponent)
            return Float(Double(structure.data[i]) / 255 * keep)
        }
        let keptTop = ToneCurve.percentile(of: kept.data, style.survivorPercentile)
        var survivors = Plane<Float>(width: w, height: h, repeating: 0)
        Self.fill(&survivors) { i in
            Float(min(max(Double(kept.data[i]) * structureTop / (keptTop + style.percentileEpsilon), 0), 1))
        }
        try cancel.throwIfCancelled()

        // the photo with its texture smeared away: where steps cancel and there is much of them
        let busyAt = ToneCurve.percentile(of: variation.data, style.variationPercentile) + style.percentileEpsilon
        var texture = Plane<Float>(width: w, height: h, repeating: 0)
        Self.fill(&texture) { i in
            let busy = min(max(Double(variation.data[i]) / busyAt, 0), 1)
            let structured = pow(Double(coherence.data[i]), style.structureExponent)
            return Float(min(max((1 - structured) * busy * style.textureGain, 0), 1))
        }
        var detextured = Plane<SIMD3<Float>>(width: w, height: h, repeating: .zero)
        let smear = Int(sketch.smearRadius)
        detextured.data.withUnsafeMutableBufferPointer { buffer in
            let out = UncheckedSendable(buffer.baseAddress!)
            Parallel.forEachChunk(h, chunk: Self.chunkRows) { rows in
                let part = Self.smeared(photo, rows: rows, radius: smear)
                for i in 0..<(rows.count * w) {
                    let here = Self.unit(photo.data[rows.lowerBound * w + i])
                    let blurred = SIMD3(part[i * 3], part[i * 3 + 1], part[i * 3 + 2])
                    out.value[rows.lowerBound * w + i] = SIMD3<Float>(here + (blurred - here) * Double(texture.data[rows.lowerBound * w + i]))
                }
            }
        }
        try cancel.throwIfCancelled()

        let tone = ToneCurve(counting: simplified, tones: tones, style: style)
        var smoothedLightness = Plane<Float>(width: w, height: h, repeating: 0)
        Self.fill(&smoothedLightness) { Float(LayerColor.lightness(smoothed.data[$0])) }
        self.coherence = coherence
        self.survivors = survivors
        self.texture = texture
        self.detextured = detextured
        self.smoothedLightness = smoothedLightness
        self.tone = tone
        self.paletteGrey = Self.greys(of: palette, tone)
        self.simplifiedGrey = Self.greys(of: simplified, tone)
    }

    /// The pipeline's window radius scaled to a picture this wide; ties go to even like Python's round().
    static func windowRadius(forWidth width: Int, _ style: RevealStyle) -> Int {
        max(1, Int((style.rtvWindow * Double(width) / 1024).rounded(.toNearestOrEven)))
    }

    /// A color as 0...1 doubles.
    static func unit(_ color: SIMD4<UInt8>) -> SIMD3<Double> {
        SIMD3(Double(color.x) / 255, Double(color.y) / 255, Double(color.z) / 255)
    }

    private static func greys(of picture: Plane<SIMD4<UInt8>>, _ tone: ToneCurve) -> Plane<Float> {
        var greys = Plane<Float>(width: picture.width, height: picture.height, repeating: 0)
        greys.data.withUnsafeMutableBufferPointer { buffer in
            let out = UncheckedSendable(buffer.baseAddress!)
            Parallel.forEachBand(picture.height) { rows in
                var lastColor: SIMD4<UInt8>?
                var lastGrey: Float = 0
                for i in (rows.lowerBound * picture.width)..<(rows.upperBound * picture.width) {
                    let color = picture.data[i]          // a flat picture repeats its colors
                    if color != lastColor { lastColor = color; lastGrey = Float(tone.grey(of: color)) }
                    out.value[i] = lastGrey
                }
            }
        }
        return greys
    }

    /// Sets each pixel of `plane` to `value(index)`, rows in parallel.
    private static func fill(_ plane: inout Plane<Float>, _ value: (Int) -> Float) {
        let width = plane.width
        plane.data.withUnsafeMutableBufferPointer { buffer in
            let out = UncheckedSendable(buffer.baseAddress!)
            Parallel.forEachBand(plane.height) { rows in
                for i in (rows.lowerBound * width)..<(rows.upperBound * width) { out.value[i] = value(i) }
            }
        }
    }

    // MARK: Relative total variation

    /// The coherence (0...1) and variation of the pixels in `rows`, row-major, from the photo's
    /// color steps (OKLab with chroma stretched, a pixel minus the one before it along x and along
    /// y), each box blurred twice over `radius` with edges clamped. Every pixel's value is its own
    /// fixed-order sums, so the rows asked for at once never change the answer.
    static func relativeTotalVariation(of photo: Plane<SIMD4<UInt8>>, rows: Range<Int>, radius r: Int, style: RevealStyle)
        -> (coherence: [Double], variation: [Double])
    {
        let (w, h) = (photo.width, photo.height)
        let source = max(0, rows.lowerBound - 2 * r)..<min(h, rows.upperBound + 2 * r)
        let labFirst = max(0, source.lowerBound - 1)
        var lab = [Double](repeating: 0, count: (source.upperBound - labFirst) * w * 3)
        for y in labFirst..<source.upperBound {
            for x in 0..<w {
                let c = LayerColor.oklab(photo.data[y * w + x])
                let i = ((y - labFirst) * w + x) * 3
                lab[i] = c.x
                lab[i + 1] = c.y * style.rtvChroma
                lab[i + 2] = c.z * style.rtvChroma
            }
        }
        var coherent = [Double](repeating: 0, count: rows.count * w)
        var total = [Double](repeating: 0, count: rows.count * w)
        for vertical in [false, true] {
            var steps = [Double](repeating: 0, count: source.count * w * 4)
            for y in source {
                for x in 0..<w {
                    guard vertical ? y > 0 : x > 0 else { continue }       // the first step of a line is none
                    let here = ((y - labFirst) * w + x) * 3
                    let before = vertical ? ((y - 1 - labFirst) * w + x) * 3 : here - 3
                    let i = ((y - source.lowerBound) * w + x) * 4
                    let (a, b, c) = (lab[here] - lab[before], lab[here + 1] - lab[before + 1], lab[here + 2] - lab[before + 2])
                    steps[i] = a
                    steps[i + 1] = b
                    steps[i + 2] = c
                    steps[i + 3] = (a * a + b * b + c * c).squareRoot()
                }
            }
            let blurred = Self.doubleBox(steps, firstRow: source.lowerBound, rows: rows, width: w, height: h, channels: 4, radius: r)
            for i in 0..<(rows.count * w) {
                let (a, b, c) = (blurred[i * 4], blurred[i * 4 + 1], blurred[i * 4 + 2])
                coherent[i] += (a * a + b * b + c * c).squareRoot()
                total[i] += blurred[i * 4 + 3]
            }
        }
        let coherence = zip(coherent, total).map { min(max($0 / ($1 + style.rtvEpsilon), 0), 1) }
        return (coherence, total)
    }

    /// The photo, box blurred twice by `radius` (0...1 doubles, three to a pixel) for `rows`.
    static func smeared(_ photo: Plane<SIMD4<UInt8>>, rows: Range<Int>, radius r: Int) -> [Double] {
        let (w, h) = (photo.width, photo.height)
        let source = max(0, rows.lowerBound - 2 * r)..<min(h, rows.upperBound + 2 * r)
        var values = [Double](repeating: 0, count: source.count * w * 3)
        for y in source {
            for x in 0..<w {
                let c = unit(photo.data[y * w + x])
                let i = ((y - source.lowerBound) * w + x) * 3
                values[i] = c.x
                values[i + 1] = c.y
                values[i + 2] = c.z
            }
        }
        return doubleBox(values, firstRow: source.lowerBound, rows: rows, width: w, height: h, channels: 3, radius: r)
    }

    /// `box(box(a, r), r)` for the rows `rows` of a picture `width` by `height` with `channels`
    /// interleaved values per pixel, as `making_of_layers.box` computes it (each pass along y, then
    /// along x, sums over 2r + 1 samples with the edges repeated), where `source` holds the picture's
    /// rows from `firstRow` to at least `2 * radius` beyond `rows`. The sums run in a fixed order.
    static func doubleBox(_ source: [Double], firstRow: Int, rows: Range<Int>, width: Int, height: Int, channels: Int, radius r: Int)
        -> [Double]
    {
        let rowLength = width * channels
        let window = Double(2 * r + 1)
        let middle = max(0, rows.lowerBound - r)..<min(height, rows.upperBound + r)
        var halfway = [Double](repeating: 0, count: middle.count * rowLength)
        var result = [Double](repeating: 0, count: rows.count * rowLength)
        var padded = [Double](repeating: 0, count: (width + 2 * r) * channels)

        /// Sums `input`'s rows within r of each row of `range` into `output`, and divides.
        func alongY(_ input: UnsafePointer<Double>, from inputFirst: Int, _ range: Range<Int>, into output: UnsafeMutablePointer<Double>, from outputFirst: Int) {
            for y in range {
                let row = output + (y - outputFirst) * rowLength
                row.update(repeating: 0, count: rowLength)
                for j in -r...r {
                    let neighbour = input + (min(max(y + j, 0), height - 1) - inputFirst) * rowLength
                    for i in 0..<rowLength { row[i] += neighbour[i] }
                }
                for i in 0..<rowLength { row[i] /= window }
            }
        }
        /// The same along x, in place, row by row.
        func alongX(_ buffer: UnsafeMutablePointer<Double>, rows count: Int, scratch: UnsafeMutablePointer<Double>) {
            for r0 in 0..<count {
                let row = buffer + r0 * rowLength
                for c in 0..<channels {
                    for k in 0..<r { scratch[k * channels + c] = row[c] }
                    for k in 0..<r { scratch[(r + width + k) * channels + c] = row[(width - 1) * channels + c] }
                }
                (scratch + r * channels).update(from: row, count: rowLength)
                row.update(repeating: 0, count: rowLength)
                for j in 0...(2 * r) {
                    let shifted = scratch + j * channels
                    for i in 0..<rowLength { row[i] += shifted[i] }
                }
                for i in 0..<rowLength { row[i] /= window }
            }
        }

        source.withUnsafeBufferPointer { source in
            halfway.withUnsafeMutableBufferPointer { halfway in
                result.withUnsafeMutableBufferPointer { result in
                    padded.withUnsafeMutableBufferPointer { padded in
                        alongY(source.baseAddress!, from: firstRow, middle, into: halfway.baseAddress!, from: middle.lowerBound)
                        alongX(halfway.baseAddress!, rows: middle.count, scratch: padded.baseAddress!)
                        alongY(UnsafePointer(halfway.baseAddress!), from: middle.lowerBound, rows, into: result.baseAddress!, from: rows.lowerBound)
                        alongX(result.baseAddress!, rows: rows.count, scratch: padded.baseAddress!)
                    }
                }
            }
        }
        return result
    }
}

/// Color math of the layers, in Double: the OKLab of 8-bit sRGB, as `oklab` and `lightness` in
/// `making_of_layers.py`.
enum LayerColor {
    /// sRGB's transfer function, for each 8-bit value.
    private static let decoded: [Double] = (0..<256).map { k in
        let c = Double(k) / 255
        return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    static func key(_ color: SIMD4<UInt8>) -> UInt32 {
        UInt32(color.x) << 16 | UInt32(color.y) << 8 | UInt32(color.z)
    }

    private static func cones(_ color: SIMD4<UInt8>) -> SIMD3<Double> {
        let (r, g, b) = (decoded[Int(color.x)], decoded[Int(color.y)], decoded[Int(color.z)])
        return SIMD3(
            cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b),
            cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b),
            cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b))
    }

    static func oklab(_ color: SIMD4<UInt8>) -> SIMD3<Double> {
        let c = cones(color)
        return SIMD3(
            0.2104542553 * c.x + 0.7936177850 * c.y - 0.0040720468 * c.z,
            1.9779984951 * c.x - 2.4285922050 * c.y + 0.4505937099 * c.z,
            0.0259040371 * c.x + 0.7827717662 * c.y - 0.8086757660 * c.z)
    }

    static func lightness(_ color: SIMD4<UInt8>) -> Double {
        let c = cones(color)
        return 0.2104542553 * c.x + 0.7936177850 * c.y - 0.0040720468 * c.z
    }
}
