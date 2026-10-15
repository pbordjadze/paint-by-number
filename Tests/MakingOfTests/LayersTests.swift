import Foundation
import Testing
import PaintCore
@testable import MakingOf

/// The stage pictures of `Fixtures/show-small` (216 x 144 snapshots of a parrot crop), read for
/// the layers' and the compositor's tests.
enum LayerFixture {
    static func directory() throws -> URL {
        try #require(Bundle.module.url(forResource: "show-small", withExtension: nil, subdirectory: "Fixtures"))
    }

    static func read(_ name: String) throws -> RGBAImage {
        try Netpbm.read(Data(contentsOf: directory().appendingPathComponent(name)))
    }

    static func rgb(_ name: String) throws -> Plane<SIMD4<UInt8>> {
        let image = try read(name)
        let data = (0..<(image.width * image.height)).map { i in
            SIMD4(image.pixels[i * 4], image.pixels[i * 4 + 1], image.pixels[i * 4 + 2], image.pixels[i * 4 + 3])
        }
        return Plane(width: image.width, height: image.height, data: data)
    }

    static func grey(_ name: String) throws -> Plane<UInt8> {
        let image = try read(name)
        return Plane(width: image.width, height: image.height, data: (0..<(image.width * image.height)).map { image.pixels[$0 * 4] })
    }

    static func spec() throws -> ShowSpec {
        try ShowSpec(json: shippedSpecData())
    }

    static func layers(style: RevealStyle = .standard) throws -> ShowLayers {
        let spec = try spec()
        return try ShowLayers(
            photo: rgb("working-image.ppm"), structure: grey("structure.pgm"), smoothed: rgb("smoothed.ppm"),
            palette: rgb("palette.ppm"), simplified: rgb("simplified.ppm"),
            sketch: spec.sketch, tones: spec.tones, style: style)
    }

    static func golden<T: Decodable>(_ name: String, as type: T.Type = T.self) throws -> T {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures"))
        return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
    }

    /// `rgb` of one flat color, `width` x `height`.
    static func flat(_ color: SIMD4<UInt8>, width: Int, height: Int) -> Plane<SIMD4<UInt8>> {
        Plane(width: width, height: height, repeating: color)
    }

    /// Layers of a made-up photo and structure, with flat stage pictures after it.
    static func layers(photo: Plane<SIMD4<UInt8>>, structure: Plane<UInt8>) throws -> ShowLayers {
        let spec = try spec()
        let flat = flat(SIMD4(128, 128, 128, 255), width: photo.width, height: photo.height)
        return try ShowLayers(photo: photo, structure: structure, smoothed: flat, palette: flat, simplified: flat,
                              sketch: spec.sketch, tones: spec.tones)
    }
}

/// `layers-small.json`, which `tools/tests/test_making_of_layers.py --write-goldens` writes: the
/// layers of the fixture's pictures from `making_of_layers.derive` on a 31 x 21 lattice.
struct LayersGolden: Decodable {
    struct Tone: Decodable {
        var darkest, span, gamma: Double
    }

    struct Lattice: Decodable {
        var coherence, survivors, texture, detextured, smoothedLightness, paletteGrey, simplifiedGrey: [Double]
    }

    struct Statistics: Decodable {
        var coherenceMean, variationMean, variation90, survivorsMean, survivorsMax, textureMean, simplifiedGreyMean: Double
        var detexturedMean: [Double]
    }

    var size: [Int]
    var xs: [Int]
    var ys: [Int]
    var style: [String: Values]
    var tone: Tone
    var lattice: Lattice
    var statistics: Statistics

    /// A style field: a number or a list of them.
    struct Values: Decodable, Equatable {
        var numbers: [Double]

        init(from decoder: any Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let list = try? c.decode([Double].self) { numbers = list } else { numbers = [try c.decode(Double.self)] }
        }
    }
}

@Suite struct LayersTests {
    // Swift against the Python of making_of_layers.py, on the fixture: continuous math, so compared
    // within tolerances, about twice the error measured here (Linux x86-64, Swift 6.2, numpy 2.5).
    // The golden is float64 from the exact 8-bit pictures; the port keeps its planes in Float, so
    // what is left is a step of Float (6e-8 at 1) and, for the texture, its cube and gain on top.
    //   lattice planes: coherence 3.4e-8, survivors 4.5e-8, detextured 4.5e-8, the three greys
    //     and the smoothed lightness 3.4e-8, texture 1.2e-7
    //   tone curve (darkest, span, gamma): 6e-17 absolute at most
    //   whole-plane means and maxima: 2.3e-8 at most (the survivors' maximum)
    // The planes' tolerance leaves two Float steps for a libm that rounds a power or a cube root
    // differently on another platform.
    private static let planeTolerance = 1.2e-7
    private static let textureTolerance = 2.4e-7
    private static let toneTolerance = 1e-9
    private static let statisticsTolerance = 1e-7

    private func error(_ plane: Plane<Float>, _ golden: [Double], _ g: LayersGolden) -> Double {
        var worst = 0.0
        for (j, y) in g.ys.enumerated() {
            for (i, x) in g.xs.enumerated() {
                worst = max(worst, abs(Double(plane[x, y]) - golden[j * g.xs.count + i]))
            }
        }
        return worst
    }

    @Test func latticeMatchesPython() throws {
        let g: LayersGolden = try LayerFixture.golden("layers-small.json")
        let layers = try LayerFixture.layers()
        #expect([layers.width, layers.height] == g.size)
        let errors: [(String, Double, Double)] = [
            ("coherence", error(layers.coherence, g.lattice.coherence, g), Self.planeTolerance),
            ("survivors", error(layers.survivors, g.lattice.survivors, g), Self.planeTolerance),
            ("texture", error(layers.texture, g.lattice.texture, g), Self.textureTolerance),
            ("smoothedLightness", error(layers.smoothedLightness, g.lattice.smoothedLightness, g), Self.planeTolerance),
            ("paletteGrey", error(layers.paletteGrey, g.lattice.paletteGrey, g), Self.planeTolerance),
            ("simplifiedGrey", error(layers.simplifiedGrey, g.lattice.simplifiedGrey, g), Self.planeTolerance),
        ]
        for (name, e, tolerance) in errors {
            #expect(e <= tolerance, "\(name) is \(e) from Python")
        }
        var detextured = 0.0
        for (j, y) in g.ys.enumerated() {
            for (i, x) in g.xs.enumerated() {
                for c in 0..<3 {
                    detextured = max(detextured, abs(Double(layers.detextured[x, y][c]) - g.lattice.detextured[(j * g.xs.count + i) * 3 + c]))
                }
            }
        }
        #expect(detextured <= Self.planeTolerance, "detextured is \(detextured) from Python")
    }

    @Test func toneCurveMatchesPython() throws {
        let g: LayersGolden = try LayerFixture.golden("layers-small.json")
        let tone = try LayerFixture.layers().tone
        let tones = try LayerFixture.spec().tones
        #expect(abs(tone.darkest - g.tone.darkest) <= Self.toneTolerance)
        #expect(abs(tone.span - g.tone.span) <= Self.toneTolerance)
        #expect(abs(tone.gamma - g.tone.gamma) <= Self.toneTolerance)
        #expect(tone.low == tones.low && tone.high == tones.high)
    }

    @Test func statisticsMatchPython() throws {
        let g: LayersGolden = try LayerFixture.golden("layers-small.json")
        let layers = try LayerFixture.layers()
        func mean(_ plane: Plane<Float>) -> Double { plane.data.reduce(0) { $0 + Double($1) } / Double(plane.data.count) }
        let n = Double(layers.width * layers.height)
        let s = g.statistics
        let detextured = (0..<3).map { c in layers.detextured.data.reduce(0) { $0 + Double($1[c]) } / n }
        let measured: [(String, Double, Double)] = [
            ("coherenceMean", mean(layers.coherence), s.coherenceMean),
            ("survivorsMean", mean(layers.survivors), s.survivorsMean),
            ("survivorsMax", Double(layers.survivors.data.max() ?? 0), s.survivorsMax),
            ("textureMean", mean(layers.texture), s.textureMean),
            ("simplifiedGreyMean", mean(layers.simplifiedGrey), s.simplifiedGreyMean),
            ("detexturedR", detextured[0], s.detexturedMean[0]),
            ("detexturedG", detextured[1], s.detexturedMean[1]),
            ("detexturedB", detextured[2], s.detexturedMean[2]),
        ]
        for (name, got, expected) in measured {
            #expect(abs(got - expected) <= Self.statisticsTolerance, "\(name): \(got) against \(expected)")
        }
    }

    @Test func styleIsPythons() throws {
        let g: LayersGolden = try LayerFixture.golden("layers-small.json")
        var seen: Set<String> = []
        for child in Mirror(reflecting: RevealStyle.standard).children {
            let name = try #require(child.label)
            seen.insert(name)
            let numbers: [Double]
            switch child.value {
            case let v as Double: numbers = [v]
            case let v as Int: numbers = [Double(v)]
            case let v as SIMD2<Double>: numbers = [v.x, v.y]
            case let v as SIMD3<Double>: numbers = [v.x, v.y, v.z]
            default: Issue.record("\(name) is of a type this test does not know"); continue
            }
            #expect(g.style[name]?.numbers == numbers, "\(name): \(String(describing: g.style[name]?.numbers)) in Python, \(numbers) here")
        }
        #expect(seen == Set(g.style.keys), "the same fields in both")
    }

    @Test func percentilesAreNumpys() {
        // numpy.percentile of the repeated values: the rank below, the next, and its lerp
        func reference(_ values: [Double], _ counts: [Int], _ q: Double) -> Double {
            let all = zip(values, counts).flatMap { Array(repeating: $0, count: $1) }
            let virtual = q / 100 * Double(all.count - 1)
            let i = Int(virtual.rounded(.down))
            let gamma = virtual - Double(i)
            let (a, b) = (all[i], all[min(i + 1, all.count - 1)])
            return gamma >= 0.5 ? b - (b - a) * (1 - gamma) : a + (b - a) * gamma
        }
        var rng = SplitMix64(seed: 5)
        for n in [1, 2, 5, 40] {
            let values = (0..<n).map { _ in rng.nextDouble() }.sorted()
            let counts = (0..<n).map { _ in 1 + Int(rng.next() % 3000) }
            for q in [0, 1, 33, 50, 90, 99, 99.5, 100] as [Double] {
                #expect(ToneCurve.percentile(values, counts: counts, q) == reference(values, counts, q), "n \(n), q \(q)")
            }
            let single = values.map { Float($0) }
            for q in [0, 1, 33, 50, 90, 99, 99.5, 100] as [Double] {
                #expect(ToneCurve.percentile(of: single.shuffled(using: &rng), q)
                        == reference(single.map { Double($0) }, [Int](repeating: 1, count: n), q))
            }
        }
        #expect(ToneCurve.percentile([0.25, 0.75], counts: [0, 3], 50) == 0.75)         // an absent value is never chosen
    }

    @Test func selectingARankIsSortingAndIndexing() {
        var rng = SplitMix64(seed: 3)
        // zeros, repeats and values over six orders of magnitude, so that buckets of all sizes occur
        let values = (0..<6000).map { i -> Float in
            i % 7 == 0 ? 0 : i % 11 == 0 ? 0.25 : Float(rng.nextDouble() * pow(10, Double(i % 6) - 3))
        }
        let sorted = values.sorted()
        for rank in Array(stride(from: 0, to: 6000, by: 97)) + [1, 5999, 5998, 3000] {
            #expect(ToneCurve.order(rank, of: values) == sorted[rank], "rank \(rank)")
        }
    }

    @Test func toneCurveAveragesTheWantedMean() throws {
        let layers = try LayerFixture.layers()
        let tones = try LayerFixture.spec().tones
        let mean = layers.simplifiedGrey.data.reduce(0) { $0 + Double($1) } / Double(layers.simplifiedGrey.data.count)
        #expect(abs(mean - tones.mean) < 1e-6)                  // Float planes
        #expect(layers.simplifiedGrey.data.allSatisfy { Double($0) >= tones.low - 1e-6 && Double($0) <= tones.high + 1e-6 })
        // greys follow lightness
        var last = -1.0
        for i in 0...100 {
            let grey = layers.tone.grey(lightness: Double(i) / 100)
            #expect(grey >= last)
            last = grey
        }
    }

    @Test func countingPaintsIsTheSameAsBeingTold() throws {
        let simplified = try LayerFixture.rgb("simplified.ppm")
        let tones = try LayerFixture.spec().tones
        var counts: [SIMD4<UInt8>: Int] = [:]
        for color in simplified.data { counts[color, default: 0] += 1 }
        #expect(counts.count > 3 && counts.count < 100)
        let told = ToneCurve(paints: counts.map { (color: $0.key, pixels: $0.value) }, tones: tones)
        #expect(told == ToneCurve(counting: simplified, tones: tones))
    }

    @Test func aFlatPictureGetsTheDarkestGrey() throws {
        let flat = LayerFixture.flat(SIMD4(100, 150, 200, 255), width: 9, height: 6)
        let tones = try LayerFixture.spec().tones
        let tone = ToneCurve(counting: flat, tones: tones)
        #expect(tone.span == RevealStyle.standard.toneSpanFloor)
        #expect(tone.grey(of: SIMD4(100, 150, 200, 255)) == tones.low)
        #expect(tone.gamma.isFinite && tone.gamma > 0)
    }

    @Test func aFlatPhotoHasNothingToFind() throws {
        let photo = LayerFixture.flat(SIMD4(120, 90, 200, 255), width: 40, height: 24)
        let layers = try LayerFixture.layers(photo: photo, structure: Plane(width: 40, height: 24, repeating: 0))
        for plane in [layers.coherence, layers.survivors, layers.texture] {
            #expect(plane.data.allSatisfy { $0 == 0 })
        }
        #expect(layers.detextured.data.allSatisfy { $0 == SIMD3<Float>(120, 90, 200) / 255 })
    }

    @Test func aContourIsCoherentAndAFineTextureIsNot() throws {
        let (w, h) = (128, 64)
        let step = Plane(width: w, height: h, data: (0..<(w * h)).map { $0 % w < w / 2 ? SIMD4<UInt8>(0, 0, 0, 255) : SIMD4(255, 255, 255, 255) })
        let checker = Plane(width: w, height: h, data: (0..<(w * h)).map { ($0 % w + $0 / w) % 2 == 0 ? SIMD4<UInt8>(255, 255, 255, 255) : SIMD4(0, 0, 0, 255) })
        let none = Plane<UInt8>(width: w, height: h, repeating: 0)
        let edge = try LayerFixture.layers(photo: step, structure: none).coherence
        let fine = try LayerFixture.layers(photo: checker, structure: none).coherence
        #expect(edge[w / 2, h / 2] > 0.95)
        #expect(fine[w / 2, h / 2] < 0.2)
    }

    @Test func textureIsSmearedAndTheContourStays() throws {
        let (w, h) = (128, 64)
        // a step edge, the left side busy with a fine checker
        let photo = Plane(width: w, height: h, data: (0..<(w * h)).map { i -> SIMD4<UInt8> in
            let (x, y) = (i % w, i / w)
            if x >= w / 2 { return SIMD4(255, 255, 255, 255) }
            return (x + y) % 2 == 0 ? SIMD4(51, 51, 51, 255) : SIMD4(0, 0, 0, 255)
        })
        let layers = try LayerFixture.layers(photo: photo, structure: Plane(width: w, height: h, repeating: 255))
        #expect(layers.texture[w / 4, h / 2] > 0.5)
        #expect(layers.texture[w / 2, h / 2] < layers.texture[w / 4, h / 2])
        let smear = abs(layers.detextured[w / 4, h / 2][0] - Float(photo[w / 4, h / 2][0]) / 255)
        #expect(smear > 0.05)
    }

    @Test func rowsAskedAtOnceDoNotChangeTheAnswer() throws {
        // bands follow the core count, so every pixel's value must be its own sums, in a fixed
        // order: the variation of all rows at once is bit for bit that of rows in odd pieces
        let photo = try LayerFixture.rgb("working-image.ppm")
        let style = RevealStyle.standard
        for radius in [1, 4] {
            let whole = ShowLayers.relativeTotalVariation(of: photo, rows: 0..<photo.height, radius: radius, style: style)
            var coherence: [Double] = []
            var variation: [Double] = []
            for start in stride(from: 0, to: photo.height, by: 29) {
                let part = ShowLayers.relativeTotalVariation(of: photo, rows: start..<min(start + 29, photo.height), radius: radius, style: style)
                coherence += part.coherence
                variation += part.variation
            }
            #expect(whole.coherence == coherence, "coherence, radius \(radius)")
            #expect(whole.variation == variation, "variation, radius \(radius)")
        }
        for radius in [0, 1, 4, 9] {
            let whole = ShowLayers.smeared(photo, rows: 0..<photo.height, radius: radius)
            var pieces: [Double] = []
            for start in stride(from: 0, to: photo.height, by: 13) {
                pieces += ShowLayers.smeared(photo, rows: start..<min(start + 13, photo.height), radius: radius)
            }
            #expect(whole == pieces, "smear, radius \(radius)")
        }
    }

    @Test func aBoxBlurAveragesItsWindowWithEdgesRepeated() {
        // two channels of a made-up picture, blurred twice by a naive per-pixel average over the
        // clamped window, y then x as making_of_layers.box does
        let (w, h, channels) = (7, 5, 2)
        var rng = SplitMix64(seed: 9)
        let picture = (0..<(w * h * channels)).map { _ in rng.nextDouble() }
        func once(_ a: [Double], r: Int) -> [Double] {
            func average(_ read: (Int) -> Double) -> Double { (-r...r).reduce(0) { $0 + read($1) } / Double(2 * r + 1) }
            var vertical = a
            for y in 0..<h { for x in 0..<w { for c in 0..<channels {
                vertical[(y * w + x) * channels + c] = average { a[(min(max(y + $0, 0), h - 1) * w + x) * channels + c] }
            } } }
            var both = vertical
            for y in 0..<h { for x in 0..<w { for c in 0..<channels {
                both[(y * w + x) * channels + c] = average { vertical[(y * w + min(max(x + $0, 0), w - 1)) * channels + c] }
            } } }
            return both
        }
        for r in [0, 1, 2, 5] {
            let expected = once(once(picture, r: r), r: r)
            let got = ShowLayers.doubleBox(picture, firstRow: 0, rows: 0..<h, width: w, height: h, channels: channels, radius: r)
            #expect(zip(got, expected).allSatisfy { abs($0 - $1) < 1e-12 }, "radius \(r)")
            // and asking for the middle rows of just the rows they need
            let rows = 1..<4
            let need = max(0, rows.lowerBound - 2 * r)..<min(h, rows.upperBound + 2 * r)
            let part = ShowLayers.doubleBox(Array(picture[(need.lowerBound * w * channels)..<(need.upperBound * w * channels)]),
                                            firstRow: need.lowerBound, rows: rows, width: w, height: h, channels: channels, radius: r)
            #expect(part == Array(got[(rows.lowerBound * w * channels)..<(rows.upperBound * w * channels)]), "rows, radius \(r)")
        }
    }

    @Test func theWindowIsThePipelinesAndTiesGoToEven() {
        let style = RevealStyle.standard
        #expect(ShowLayers.windowRadius(forWidth: 1024, style) == 4)
        #expect(ShowLayers.windowRadius(forWidth: 640, style) == 2)         // 2.5 rounds to 2, as Python's round()
        #expect(ShowLayers.windowRadius(forWidth: 216, style) == 1)
        #expect(ShowLayers.windowRadius(forWidth: 1, style) == 1)
        #expect(ShowLayers.windowRadius(forWidth: 1152, style) == 4)
    }

    @Test func buildingTwiceGivesTheSameBytes() throws {
        let a = try LayerFixture.layers()
        let b = try LayerFixture.layers()
        #expect(a.coherence == b.coherence && a.survivors == b.survivors && a.texture == b.texture)
        #expect(a.detextured == b.detextured && a.tone == b.tone)
        #expect(a.paletteGrey == b.paletteGrey && a.simplifiedGrey == b.simplifiedGrey)
    }

    @Test func leavingOutTheAnalysisKeepsEveryPlaneTheCompositorReads() throws {
        let spec = try LayerFixture.spec()
        let kept = try LayerFixture.layers()
        let lean = try ShowLayers(
            photo: LayerFixture.rgb("working-image.ppm"), structure: LayerFixture.grey("structure.pgm"),
            smoothed: LayerFixture.rgb("smoothed.ppm"), palette: LayerFixture.rgb("palette.ppm"),
            simplified: LayerFixture.rgb("simplified.ppm"), sketch: spec.sketch, tones: spec.tones, keepingAnalysis: false)
        #expect(lean.coherence.data.isEmpty && lean.texture.data.isEmpty && !kept.coherence.data.isEmpty)
        #expect(lean.photo == kept.photo && lean.survivors == kept.survivors && lean.detextured == kept.detextured)
        #expect(lean.smoothedLightness == kept.smoothedLightness && lean.tone == kept.tone)
        #expect(lean.paletteGrey == kept.paletteGrey && lean.simplifiedGrey == kept.simplifiedGrey)
    }

    @Test func cancellingStopsTheBuild() throws {
        let spec = try LayerFixture.spec()
        let photo = try LayerFixture.rgb("working-image.ppm")
        #expect(throws: CancellationError.self) {
            try ShowLayers(
                photo: photo, structure: LayerFixture.grey("structure.pgm"), smoothed: photo, palette: photo, simplified: photo,
                sketch: spec.sketch, tones: spec.tones, cancel: CancellationCheck { true })
        }
    }
}
