import Foundation
import PaintCore
import Testing
@testable import MakingOf

/// `fields-small.json`, which `tools/tests/test_making_of_fields.py --write-goldens` writes: pieces of
/// the field show on inputs made from SplitMix64's seed 123, and the small show fixture built by
/// `making_of_fields.py`, whole (`small`, seventeen moments) and cropped to an odd size (`odd`,
/// three), each frame and its composite picture on a lattice.
struct FieldsGolden: Decodable {
    struct Synthetic: Decodable {
        struct Geodesic: Decodable {
            var seeds, start, column, row: String
        }

        struct Paced: Decodable {
            var all, over, few: String
        }

        struct Noise: Decodable {
            var lattices, warped, grain: String
            var mean, deviation: Double
            var rough: [Double]
        }

        struct Resize: Decodable {
            var shrink, grow: String
        }

        var geodesic: Geodesic
        var paced: Paced
        var noise: Noise
        var resize: Resize
        var percentile: Double
    }

    /// A built show: what the golden keeps of it.
    struct Part: Decodable {
        struct Picks: Decodable {
            struct Melting: Decodable {
                var bits: Int
                var areas: [Int]
                var rank: [Double]
            }

            /// [time, x, y] each.
            var sketch, shading, fuse, relax: [[Double]]
            var melting: Melting
        }

        struct Stroke: Decodable {
            var points: Int
            var start, duration: Double
            var fuse, relax: [Double]
        }

        struct Times: Decodable {
            var sketch, shading, paints, merged, lift, clear: [Double]
        }

        struct Frame: Decodable {
            struct Picture: Decodable {
                var stage: Int
                var time: Double
                var handoff: Double
            }

            struct Ink: Decodable {
                struct Line: Decodable {
                    var stroke: Int
                    var points: Int
                    var value: Double
                    /// The first, middle and last point: x, y, x, y, x, y.
                    var ends: [Double]
                }

                var lines: [Line]
                var fingerprint: String
            }

            struct Ring: Decodable {
                var x, y, radius, alpha: Double
            }

            struct Spark: Decodable {
                var x, y, heat: Double
            }

            struct Star: Decodable {
                var x, y, radius, alpha: Double
            }

            struct Card: Decodable {
                var step: Int
                var caption: String
                var methods: [String]
                var opacity, footnoteOpacity: Double
            }

            var time: Double
            var step: Int?
            var picture: Picture
            var ink: Ink
            var numbers: [Double]
            var seedRings: [Ring]
            var sparks: [Spark]
            var stars: [Star]
            var sprites: [Int]
            var card: Card?
            var rgb: [Double]
        }

        var size: [Int]
        var lineWidth: Double
        var duration: Double
        var xs: [Int]
        var ys: [Int]
        /// [time, x, y, paint] each.
        var seeds: [[Double]]
        var picks: Picks
        var times: Times
        var spread: [Double]
        var strokes: [Stroke]
        var numberTimes: [Double]
        var frames: [Frame]
    }

    var seed: UInt64
    var streams: [[Double]]
    var synthetic: Synthetic
    var small: Part
    var odd: Part

    static func load() throws -> FieldsGolden {
        let url = try #require(Bundle.module.url(forResource: "fields-small.json", withExtension: nil, subdirectory: "Fixtures"))
        return try JSONDecoder().decode(FieldsGolden.self, from: Data(contentsOf: url))
    }

    func part(_ kind: FieldFixture.Kind) -> Part {
        kind == .small ? small : odd
    }
}

/// The small show fixture built into a `FieldShow` as the app would, once for all the tests that read it.
enum FieldFixture {
    enum Kind: String, CaseIterable, Sendable {
        case small, odd
    }

    /// The size the fixture is cropped to for `odd`: neither side divides by the fields' scale.
    static let odd = (width: 215, height: 143)

    static func make(_ kind: Kind = .small, seed: UInt64 = SmallShow.seed, cancel: CancellationCheck = .none) throws -> FieldShow {
        let small = try SmallShow()
        switch kind {
        case .small:
            return try FieldShow(pictures: small.pictures, template: small.show, spec: small.spec, seed: seed, cancel: cancel)
        case .odd:
            let pictures = try small.pictures.cropped(width: odd.width, height: odd.height)
            let template = ShowTemplate(small.template, width: odd.width, height: odd.height)
            return try FieldShow(pictures: pictures, template: template, spec: small.spec, seed: seed, cancel: cancel)
        }
    }

    private static let built = Result { try make(.small) }
    private static let builtOdd = Result { try make(.odd) }

    static var small: FieldShow {
        get throws { try built.get() }
    }

    static func show(_ kind: Kind) throws -> FieldShow {
        try kind == .small ? built.get() : builtOdd.get()
    }
}

extension ShowPictures {
    /// The top left `width` by `height` of every picture.
    func cropped(width: Int, height: Int) throws -> ShowPictures {
        func crop<T>(_ plane: Plane<T>) -> Plane<T> {
            var data: [T] = []
            for y in 0..<height { data += plane.data[(y * plane.width)..<(y * plane.width + width)] }
            return Plane(width: width, height: height, data: data)
        }
        return try ShowPictures(
            working: crop(working), structure: crop(structure), smoothed: crop(smoothed), palette: crop(palette),
            simplified: crop(simplified))
    }
}

@Suite struct FieldShowTests {
    // Swift against making_of_fields.py on the small fixture, whole and cropped (Linux x86-64, numpy 2.5,
    // glibc libm). Everything discrete is exact: the streams, the seeds, the picks (spots, orders and
    // counts), the lines of the ink step and of the finished drawing, and so are the geodesic, the
    // pacing, the noise's lattices and its fields before `exp`, bit for bit on inputs both make.
    // What goes through `exp`, `pow` and `log` (the noise's roughness, the sketch's speed, the picks'
    // moments) measured 4.4e-16 apart in the noise alone and 0.0 in every field built from it; the
    // sketch alone, made from the layers' float32 survivors (4e-7 apart in `LayersTests`), measured one
    // float32 step (1.2e-7 s). The tolerances leave room for another libm's last bits: the pace map is
    // continuous, so they stay that size.
    private static let noiseTolerance = 1e-12
    /// For the fields in float64, the picks' moments and a frame's scalars (seconds, pixels, shares).
    private static let fieldTolerance = 1e-9
    /// For the times the compositor reads, which are float32: two steps of one at 16 to 32 s.
    private static let timeTolerance = 4e-6
    /// A composite byte is the golden's float rounded to eight bits: half a step, plus this much in 0...1.
    private static let pictureTolerance = 2e-6

    // MARK: Pieces

    @Test func streamsMatchPython() throws {
        let g = try FieldsGolden.load()
        let streams = ShowStreams(seed: g.seed)
        for (k, pin) in g.streams.enumerated() {
            var rng = streams.field(k)
            #expect((0..<3).map { _ in rng.nextDouble() } == pin, "stream \(k)")
        }
    }

    @Test func geodesicMatchesPythonBitForBit() throws {
        let g = try FieldsGolden.load().synthetic.geodesic
        var rng = SplitMix64(seed: 123)
        func plane(_ h: Int, _ w: Int) -> Plane<Double> {
            Plane(width: w, height: h, data: (0..<h * w).map { _ in 0.5 + 3 * rng.nextDouble() })
        }
        let cost = plane(29, 37)
        let column = plane(5, 1), row = plane(1, 6)
        let seeds = [
            Geodesic.Seed(time: 0.0, x: 3.4, y: 5.9), Geodesic.Seed(time: 2.5, x: 36.0, y: 28.0),
            Geodesic.Seed(time: 1.0, x: 50.7, y: -3.2),     // outside the plane
        ]
        #expect(fingerprint(Geodesic.field(cost: cost, seeds: seeds, sweeps: 3).data) == g.seeds)
        var start = Plane<Double>(width: 37, height: 29, repeating: .infinity)
        start[7, 4] = 0.0
        start[30, 20] = 1.5
        #expect(fingerprint(Geodesic.field(cost: cost, start: start, sweeps: 2).data) == g.start)
        #expect(fingerprint(Geodesic.field(cost: column, seeds: [.init(time: 0, x: 0, y: 3)], sweeps: 2).data) == g.column)
        #expect(fingerprint(Geodesic.field(cost: row, seeds: [.init(time: 0, x: 4, y: 0)], sweeps: 1).data) == g.row)
    }

    @Test func aFrontIsTheDistanceWhereNothingGetsInItsWay() {
        let field = Geodesic.field(
            cost: Plane(width: 41, height: 41, repeating: 1), seeds: [.init(time: 0, x: 20, y: 20)], sweeps: 3)
        let diagonal = 20 * 2.0.squareRoot()
        #expect(field[40, 20] == 20)                                        // straight along a row
        #expect(abs(field[40, 40] - diagonal) < 1e-12)                      // and along a diagonal
        #expect(abs(field[0, 0] - diagonal) < 1e-12)
        // a wall holds it back: through it, never round it
        var walled = Plane<Double>(width: 21, height: 21, repeating: 1)
        for y in 0..<21 { walled[10, y] = 50 }
        let behind = Geodesic.field(cost: walled, seeds: [.init(time: 0, x: 2, y: 10)], sweeps: 3)
        #expect(behind[18, 10] > behind[2, 10] + 50)
    }

    @Test func pacingMatchesPythonBitForBit() throws {
        let g = try FieldsGolden.load().synthetic
        // the draws follow the geodesic's (29 x 37, 5 x 1 and 1 x 6 costs) in the Python
        var rng = SplitMix64(seed: 123)
        for _ in 0..<(29 * 37 + 5 + 6) { _ = rng.nextDouble() }
        var times = (0..<6000).map { _ in rng.nextDouble() * 50 }
        for i in stride(from: 0, to: 6000, by: 97) { times[i] = times[i + 1] }
        for i in stride(from: 0, to: 6000, by: 331) { times[i] = .infinity }
        let over = (0..<6000).map { _ in rng.nextDouble() < 0.7 }
        var all = times, some = times
        FieldMath.paced(&all, from: 3.0, to: 5.5)
        FieldMath.paced(&some, from: 3.0, to: 5.5, over: over)
        var few: [Double] = [0, 1, 2, 3, 4, 100, .infinity]
        FieldMath.paced(&few, from: 0, to: 1, over: [true, true, true, true, true, false, false])
        #expect(fingerprint(all) == g.paced.all)
        #expect(fingerprint(some) == g.paced.over)
        #expect(fingerprint(few) == g.paced.few)
    }

    @Test func pacingSpreadsAnOutlierEvenly() {
        var times = (0..<1000).map(Double.init) + [1e9]
        FieldMath.paced(&times, from: 10, to: 12)
        #expect(times.min() == 10 && times.max() == 12)
        #expect(zip(times, times.dropFirst()).allSatisfy { $0 <= $1 })      // nothing changes order
        #expect(times[500] > 10.7 && times[500] < 11.1)                     // half the cells by about half the time
        var same = [Double](repeating: 0, count: 10)
        same += [Double](repeating: 1, count: 10)
        same += [Double](repeating: 2, count: 10)
        FieldMath.paced(&same, from: 0, to: 1)
        #expect(Set(same[10..<20]).count == 1 && same[15] > 0.3 && same[15] < 0.7)
        var nothing: [Double] = [.infinity, .infinity]
        FieldMath.paced(&nothing, from: 3, to: 4)
        #expect(nothing == [4, 4])
        var flat = [Double](repeating: 2.5, count: 50)
        FieldMath.paced(&flat, from: 3, to: 4)
        #expect(Set(flat).count == 1)
    }

    @Test func noiseMatchesPython() throws {
        let g = try FieldsGolden.load().synthetic.noise
        let noise = FieldNoise(streams: ShowStreams(seed: 7))
        #expect(fingerprint(noise.lattices) == g.lattices)
        let warped = noise.warped(width: 31, height: 23, scale: 5.0)
        #expect(fingerprint(warped) == g.warped)
        #expect(fingerprint(noise.grain(width: 31, height: 23, scale: 6.0)) == g.grain)
        let (mean, deviation) = FieldMath.meanAndDeviation(warped)
        #expect(mean == g.mean && deviation == g.deviation)             // numpy's pairwise sums, to the bit
        let rough = noise.rough(width: 31, height: 23, scale: 5.0, strength: 0.4)
        #expect(rough.count == g.rough.count)
        let worst = zip(rough, g.rough).map { abs($0 - $1) }.max() ?? 0
        Self.measured("noise.rough", worst)
        #expect(worst <= Self.noiseTolerance)
    }

    @Test func resizingMatchesPython() throws {
        let g = try FieldsGolden.load().synthetic
        var rng = SplitMix64(seed: 123)
        for _ in 0..<(29 * 37 + 5 + 6 + 6000 + 6000) { _ = rng.nextDouble() }
        let big = (0..<23 * 31).map { _ in rng.nextDouble() }
        let small = FieldMath.shrink(width: 31, height: 23) { big[$0] }
        #expect(small.width == 15 && small.height == 11)
        #expect(fingerprint(small.data) == g.resize.shrink)
        #expect(fingerprint(FieldMath.grow(small, to: (31, 23))) == g.resize.grow)
        var histogram = [Int](repeating: 0, count: 256)
        for _ in 0..<5000 { histogram[rng.below(256)] += 1 }
        #expect(ExactMath.percentile(counts: histogram, percent: 98) == g.percentile)
    }

    // MARK: The show against the Python

    @Test(arguments: FieldFixture.Kind.allCases)
    func seedsAndPicksMatchPython(_ kind: FieldFixture.Kind) throws {
        let g = try FieldsGolden.load().part(kind)
        let show = try FieldFixture.show(kind)
        #expect(show.seeds.map { [$0.time, $0.x, $0.y, Double($0.paint)] } == g.seeds)
        // the spots and the shuffled order are exact; the moments come through `log`
        let picks = show.picks
        var worst = 0.0
        for (got, want) in [(picks.sketch, g.picks.sketch), (picks.shading, g.picks.shading), (picks.fuse, g.picks.fuse), (picks.relax, g.picks.relax)] {
            #expect(got.count == want.count)
            for (seed, pin) in zip(got, want) {
                #expect([seed.x, seed.y] == [pin[1], pin[2]])
                worst = max(worst, abs(seed.time - pin[0]))
            }
        }
        Self.measured("the picks' moments (\(kind))", worst)
        #expect(worst <= Self.fieldTolerance)
        #expect(picks.sketch.count == FieldShow.sketchSeeds && picks.shading.count == FieldShow.bloomSeeds)
        #expect(picks.fuse.count == FieldShow.fuseSeeds && picks.relax.count == FieldShow.relaxSeeds)
        #expect(picks.bitPixels == g.picks.melting.bits)
        #expect(picks.melting == g.picks.melting.areas)
        #expect(picks.meltingRank == g.picks.melting.rank)
    }

    @Test(arguments: FieldFixture.Kind.allCases)
    func theFieldsMatchPython(_ kind: FieldFixture.Kind) throws {
        let g = try FieldsGolden.load().part(kind)
        let show = try FieldFixture.show(kind)
        #expect(g.size == [show.size.width, show.size.height] && g.duration == show.duration && g.lineWidth == show.lineWidth)
        let (w, h) = (show.size.width, show.size.height)
        let times = show.compositor.times
        let planes: [(String, Plane<Float>, [Double])] = [
            ("sketch", times.sketch, g.times.sketch), ("shading", times.shading, g.times.shading),
            ("paints", times.paints, g.times.paints), ("merged", times.merged, g.times.merged),
            ("lift", times.lift, g.times.lift), ("clear", times.clear, g.times.clear),
        ]
        for (name, plane, want) in planes {
            #expect(plane.width == w && plane.height == h)
            var worst = 0.0
            var n = 0
            for y in g.ys {
                for x in g.xs {
                    worst = max(worst, abs(Double(plane[x, y]) - want[n]))
                    n += 1
                }
            }
            Self.measured("\(name) time (\(kind))", worst)
            #expect(worst <= Self.timeTolerance, "\(name)")
        }
        #expect(show.spread.count == g.spread.count)
        let worstSpread = zip(show.spread, g.spread).map { abs($0 - $1) }.max() ?? 0
        Self.measured("spread (\(kind))", worstSpread)
        #expect(worstSpread <= Self.fieldTolerance)

        #expect(show.strokes.count == g.strokes.count && show.fuses.count == g.strokes.count)
        var worstFuse = 0.0, worstRelax = 0.0, worstSpan = 0.0
        for (n, want) in g.strokes.enumerated() {
            let stroke = show.strokes[n]
            #expect(stroke.index == n && !stroke.walked && stroke.jagged.count == want.points && stroke.smooth.count == want.points)
            #expect(show.fuses[n].count == want.points)
            for (got, pin) in zip(show.fuses[n], want.fuse) { worstFuse = max(worstFuse, abs(got - pin)) }
            for (got, pin) in zip(stroke.relax, want.relax) { worstRelax = max(worstRelax, abs(got - pin)) }
            worstSpan = max(worstSpan, abs(stroke.start - want.start), abs(stroke.duration - want.duration))
        }
        Self.measured("fuse (\(kind))", worstFuse)
        Self.measured("relax (\(kind))", worstRelax)
        Self.measured("fuse spans (\(kind))", worstSpan)
        #expect(worstFuse <= Self.fieldTolerance && worstRelax <= Self.fieldTolerance && worstSpan <= Self.fieldTolerance)

        #expect(show.numberTimes.count == g.numberTimes.count)
        let worstNumbers = zip(show.numberTimes, g.numberTimes).map { abs($0 - $1) }.max() ?? 0
        Self.measured("number times (\(kind))", worstNumbers)
        #expect(worstNumbers <= Self.fieldTolerance)
    }

    @Test(arguments: FieldFixture.Kind.allCases)
    func framesMatchPython(_ kind: FieldFixture.Kind) throws {
        let g = try FieldsGolden.load().part(kind)
        let show = try FieldFixture.show(kind)
        var worst = 0.0
        func near(_ got: Double, _ want: Double, _ what: @autoclosure () -> String) {
            worst = max(worst, abs(got - want))
            #expect(abs(got - want) <= Self.fieldTolerance, "\(what()): \(got) against \(want)")
        }
        for expected in g.frames {
            let frame = show.frame(at: expected.time)
            let at = "t = \(expected.time)"
            #expect(frame.time == expected.time && frame.step == expected.step, "\(at)")
            #expect(frame.picture == PictureRecipe(stage: expected.picture.stage, time: expected.picture.time, handoff: expected.picture.handoff), "\(at)")
            #expect(frame.sprites.isEmpty && expected.sprites.isEmpty, "\(at)")

            // the lines: which, how long and how dark exactly; where within the fuse's tolerance, but
            // exactly in the ink step (a prefix of the stair steps) and once the outlines are smooth
            #expect(frame.ink.map(\.stroke) == expected.ink.lines.map(\.stroke), "\(at)")
            #expect(frame.ink.map(\.points.count) == expected.ink.lines.map(\.points), "\(at)")
            #expect(frame.ink.map(\.value) == expected.ink.lines.map(\.value), "\(at)")
            if expected.picture.stage != 5 {
                #expect(fingerprint(frame.ink.flatMap(\.points)) == expected.ink.fingerprint, "\(at)")
            }
            for (line, want) in zip(frame.ink, expected.ink.lines) {
                let ends = [line.points[0], line.points[line.points.count / 2], line.points[line.points.count - 1]]
                for (point, i) in zip(ends, [0, 2, 4]) {
                    near(point.x, want.ends[i], "line \(line.stroke) at \(at)")
                    near(point.y, want.ends[i + 1], "line \(line.stroke) at \(at)")
                }
            }

            #expect(frame.numbers.count == expected.numbers.count, "\(at)")
            for (got, pin) in zip(frame.numbers, expected.numbers) { near(got, pin, "number at \(at)") }

            #expect(frame.seedRings.count == expected.seedRings.count, "\(at)")
            for (ring, want) in zip(frame.seedRings, expected.seedRings) {
                for (got, pin) in [(ring.x, want.x), (ring.y, want.y), (ring.radius, want.radius), (ring.alpha, want.alpha)] {
                    near(got, pin, "ring at \(at)")
                }
            }
            #expect(frame.sparks.count == expected.sparks.count, "\(at)")
            for (spark, want) in zip(frame.sparks, expected.sparks) {
                #expect(spark.x == want.x && spark.y == want.y, "spark at \(at)")
                near(spark.heat, want.heat, "spark at \(at)")
                #expect(spark.heat > 0 && spark.heat <= 1)
            }
            #expect(frame.stars.count == expected.stars.count, "\(at)")
            for (star, want) in zip(frame.stars, expected.stars) {
                #expect(star.x == want.x && star.y == want.y, "star at \(at)")
                near(star.radius, want.radius, "star at \(at)")
                near(star.alpha, want.alpha, "star at \(at)")
                #expect(star.alpha > 0 && star.alpha <= FieldShow.starAlpha)
            }
            #expect((frame.card == nil) == (expected.card == nil), "\(at)")
            if let card = frame.card, let want = expected.card {
                #expect(card.step == want.step && card.caption == want.caption && card.methods == want.methods, "\(at)")
                near(card.opacity, want.opacity, "card at \(at)")
                near(card.footnoteOpacity, want.footnoteOpacity, "card at \(at)")
            }
        }
        Self.measured("frame scalars (\(kind))", worst)
    }

    @Test(arguments: FieldFixture.Kind.allCases)
    func compositesMatchPython(_ kind: FieldFixture.Kind) throws {
        let g = try FieldsGolden.load().part(kind)
        let show = try FieldFixture.show(kind)
        let (w, h) = (show.size.width, show.size.height)
        var pixels = Plane<SIMD4<UInt8>>(width: w, height: h, repeating: .zero)
        var worst = 0.0
        for expected in g.frames {
            show.composite(show.frame(at: expected.time), into: &pixels)
            for (j, y) in g.ys.enumerated() {
                for (i, x) in g.xs.enumerated() {
                    let pixel = pixels[x, y]
                    #expect(pixel.w == 255)
                    for (c, byte) in [pixel.x, pixel.y, pixel.z].enumerated() {
                        // the golden is the float picture: the byte is that rounded half up
                        let want = expected.rgb[(j * g.xs.count + i) * 3 + c]
                        let apart = abs(Double(byte) / 255 - want) - 0.5 / 255
                        worst = max(worst, apart)
                        #expect(apart <= Self.pictureTolerance, "t = \(expected.time) at (\(x), \(y)) channel \(c)")
                    }
                }
            }
        }
        Self.measured("composite past the rounding (\(kind))", worst)
    }

    /// What the last run measured, printed for the tolerances above (Swift Testing has no log of its own).
    private static func measured(_ what: String, _ value: Double) {
        print("FieldShowTests measured \(what): \(value)")
    }

    // MARK: Behavior

    @Test func theShowIsTimedByItsOwnHold() throws {
        let show = try FieldFixture.small
        let spec = try SmallShow().spec
        #expect(show.duration == spec.timing.intro + 6 * spec.timing.step + FieldShow.outro)
        #expect(show.timeline.timing == ScheduleTiming(spec) && show.timeline.outro == 1.6)
        #expect(show.size.width == 216 && show.size.height == 144)
        // the finished drawing holds with its numbers all in, no guardians, and the hand-off done
        let end = show.frame(at: show.duration)
        #expect(end.sprites.isEmpty && end.picture.handoff == 1 && end.numbers.allSatisfy { $0 == 1 })
        #expect(end.sparks.isEmpty && end.stars.isEmpty && end.card == nil && end.step == nil)
    }

    @Test func theStagesComeInOrderWithTheirCardsAndMarks() throws {
        let show = try FieldFixture.small
        let spec = try SmallShow().spec
        var last = -2
        var seen = Set<Int>()
        for t in stride(from: -0.1, through: show.duration + 0.5, by: 0.05) {
            let frame = show.frame(at: t)
            #expect(frame.picture.stage >= last)
            last = frame.picture.stage
            seen.insert(frame.picture.stage)
            #expect(frame.step == ((0..<6).contains(frame.picture.stage) ? frame.picture.stage : nil))
            if let card = frame.card {
                #expect(card.step == frame.step)
                #expect(card.caption == spec.steps[card.step].caption)
                #expect(card.opacity > 0 && card.opacity <= spec.cards.opacity)
            }
            #expect(frame.sprites.isEmpty)
            #expect(frame.numbers.isEmpty == (frame.picture.stage < 5))
            #expect(frame.seedRings.isEmpty || frame.picture.stage == 2)
            #expect(frame.ink.isEmpty || frame.picture.stage >= 4)
            #expect(frame.sparks.isEmpty || frame.picture.stage == 4)
            #expect(frame.stars.isEmpty || frame.picture.stage >= 5)
        }
        #expect(seen == Set(-1...6))
    }

    @Test func eachStepsChangeReachesEveryPixelBeforeItEnds() throws {
        let show = try FieldFixture.small
        let times = show.compositor.times
        let spec = try SmallShow().spec
        let planes = [times.sketch, times.shading, times.paints, times.merged, times.lift, times.clear]
        for (k, plane) in planes.enumerated() {
            let start = spec.timing.intro + Double(k) * spec.timing.step
            let low = plane.data.min()!, high = plane.data.max()!
            #expect(Double(low) >= start - 1e-6 && Double(high) <= start + spec.timing.step - 0.1 + 1e-5, "step \(k + 1): \(low) to \(high)")
            #expect(Double(high - low) > 0.2, "step \(k + 1)")
        }
    }

    @Test func everyLineBurnsInTheInkStepWithTimeToDarken() throws {
        let show = try FieldFixture.small
        let spec = try SmallShow().spec
        let ink = spec.timing.intro + 4 * spec.timing.step
        for at in show.fuses {
            #expect(at.min()! >= ink && at.max()! + spec.outlines.inkRamp <= ink + spec.timing.step)
        }
        let (lines, _) = show.burning(at: ink + spec.timing.step - 1e-6)
        #expect(Set(lines.map(\.stroke)) == Set(show.strokes.map(\.index)))
        #expect(lines.allSatisfy { $0.value == 1 })
        // and darkens in eighths: only values of the ramp are ever drawn
        var allowed: Set<Double> = []
        for eighths in 3...8 { allowed.insert(min(Double(eighths) / 8 + 0.0625, 1)) }
        for f in stride(from: 0.0, through: 1.0, by: 0.02) {
            let (now, _) = show.burning(at: ink + f * spec.timing.step)
            #expect(now.allSatisfy { allowed.contains($0.value) }, "\(f)")
        }
    }

    @Test func numbersComeOutAfterTheirAreaClears() throws {
        let show = try FieldFixture.small
        let small = try SmallShow()
        let clear = show.compositor.times.clear
        let end = small.spec.timing.intro + 6 * small.spec.timing.step
        for (number, at) in zip(small.show.numbers, show.numberTimes) {
            let x = min(max(truncated(number.x), 0), clear.width - 1)
            let y = min(max(truncated(number.y), 0), clear.height - 1)
            #expect(at > Double(clear[x, y]))
            #expect(at <= end)
        }
    }

    @Test func theSparksCoolAndTheStarsOpenAndFade() throws {
        let show = try FieldFixture.small
        let spec = try SmallShow().spec
        let ink = spec.timing.intro + 4 * spec.timing.step
        var sparks = 0, stars = 0
        for t in stride(from: ink, to: ink + 3 * spec.timing.step, by: 0.02) {
            let frame = show.frame(at: t)
            sparks += frame.sparks.count
            stars += frame.stars.count
            // a line has at most two sparks at once
            #expect(frame.sparks.allSatisfy { $0.heat > 0 && $0.heat <= 1 })
            #expect(frame.sparks.count <= FieldShow.sparksPerLine * show.strokes.count)
            for star in frame.stars {
                #expect(star.radius >= FieldShow.starRadius.least)
                #expect(star.alpha > 0 && star.alpha < FieldShow.starAlpha)
            }
        }
        #expect(sparks > 0 && stars > 0)
        // a ring is opening round the numbers that have just begun to come out, and gone once they are in
        let middle = show.numberTimes.sorted()[show.numberTimes.count / 2]
        #expect(!show.frame(at: middle + 0.1).stars.isEmpty)
        let last = show.numberTimes.max() ?? 0
        #expect(show.frame(at: last + FieldShow.starLife + 0.01).stars.isEmpty)
    }

    @Test func aFrameIsAFunctionOfTheTime() throws {
        let show = try FieldFixture.small
        let times = stride(from: -0.5, through: show.duration + 1, by: 0.37).map { $0 }
        let forward = times.map { show.frame(at: $0) }
        for (t, frame) in zip(times, forward).reversed() { #expect(show.frame(at: t) == frame, "t = \(t)") }
        var rng = SplitMix64(seed: 3)
        for _ in 0..<20 {
            let i = rng.below(times.count)
            #expect(show.frame(at: times[i]) == forward[i])
        }
    }

    @Test func buildingTwiceMakesTheSameShow() throws {
        let a = try FieldFixture.small
        let b = try FieldFixture.make()
        let (ta, tb) = (a.compositor.times, b.compositor.times)
        #expect(ta.sketch == tb.sketch && ta.shading == tb.shading && ta.paints == tb.paints)
        #expect(ta.merged == tb.merged && ta.lift == tb.lift && ta.clear == tb.clear)
        #expect(a.fuses == b.fuses && a.numberTimes == b.numberTimes && a.spread == b.spread)
        #expect(a.picks == b.picks && a.strokes == b.strokes)
    }

    @Test func aDifferentSeedMakesADifferentShow() throws {
        let other = try FieldFixture.make(seed: 8)
        let show = try FieldFixture.small
        #expect(other.picks != show.picks && other.numberTimes != show.numberTimes)
    }

    @Test func theCrewShowHasNoMarks() throws {
        let show = try ShowFixture.small
        for t in stride(from: 0.0, through: show.duration, by: 0.7) {
            let frame = show.frame(at: t)
            #expect(frame.sparks.isEmpty && frame.stars.isEmpty, "t = \(t)")
        }
    }

    @Test func theFieldShowsStyleIsItsOwn() throws {
        #expect(FieldShow.style != RevealStyle.standard)
        #expect(try FieldFixture.small.compositor.layers.style == FieldShow.style)
        #expect(try ShowFixture.small.compositor.layers.style == RevealStyle.standard)
        // only the ramps of the fronts differ, not what the layers are made of
        let standard = RevealStyle.standard
        var same = FieldShow.style
        same.graphiteDelay = standard.graphiteDelay
        same.graphiteByStructure = standard.graphiteByStructure
        same.graphiteRamp = standard.graphiteRamp
        same.drainRamp = standard.drainRamp
        same.washDelay = standard.washDelay
        same.washMargin = standard.washMargin
        same.washRamp = standard.washRamp
        same.softEarly = standard.softEarly
        same.settleDepth = standard.settleDepth
        same.liftRamp = standard.liftRamp
        same.clearRamp = standard.clearRamp
        #expect(same == standard)
    }

    @Test func aTideLinesTheFrontsOfStepsTwoToFour() throws {
        let show = try FieldFixture.small
        let spec = try SmallShow().spec
        let (w, h) = (show.size.width, show.size.height)
        var pixels = Plane<SIMD4<UInt8>>(width: w, height: h, repeating: .zero)
        // just behind the front of the shading step, the picture is darker than the compositor alone
        let t = spec.timing.intro + spec.timing.step + 1.5
        show.composite(show.frame(at: t), into: &pixels)
        var darker = 0
        for y in 0..<h {
            for x in 0..<w {
                let plain = show.compositor.pixel(x: x, y: y, at: t)
                let byte = UInt8(min(max(plain.x * 255 + 0.5, 0), 255).rounded(.down))
                if pixels[x, y].x < byte { darker += 1 }
                #expect(pixels[x, y].x <= byte)
            }
        }
        #expect(darker > 100)
    }

    @Test func buildingCanBeCancelled() throws {
        #expect(throws: CancellationError.self) { try FieldFixture.make(cancel: CancellationCheck { true }) }
    }

    @Test func aTemplateOfAnotherSizeIsRefused() throws {
        let small = try SmallShow()
        let other = ShowTemplate(small.template, width: small.pictures.width + 8, height: small.pictures.height)
        #expect(throws: ShowError.self) {
            try FieldShow(pictures: small.pictures, template: other, spec: small.spec, seed: 1)
        }
    }

    @Test func aPictureTooSmallToShowIsRefused() throws {
        let small = try SmallShow()
        let pictures = try small.pictures.cropped(width: 7, height: 7)
        let template = ShowTemplate(small.template, width: 7, height: 7)
        #expect(throws: ShowError.self) { try FieldShow(pictures: pictures, template: template, spec: small.spec, seed: 1) }
    }

    @Test func aPictureWithNoLinesStillMakesAShow() throws {
        let recorder = InputsSnapshotRecorder()
        let image = RGBAImage(width: 400, height: 40, fill: SIMD4(60, 120, 180, 255))
        let output = try TemplateGenerator(settings: GenerationSettings(colorCount: 8, detail: 0.5))
            .generate(from: image, cancel: .none, observer: recorder.receive)
        let pictures = try ShowPictures(snapshots: recorder.values)
        let template = ShowTemplate(output.template, width: pictures.width, height: pictures.height)
        let spec = try ShowSpec(json: shippedSpecData())
        let show = try FieldShow(pictures: pictures, template: template, spec: spec, seed: 5)
        var pixels = Plane<SIMD4<UInt8>>(width: pictures.width, height: pictures.height, repeating: .zero)
        for t in stride(from: 0.0, through: show.duration, by: 0.4) {
            let frame = show.frame(at: t)
            show.composite(frame, into: &pixels)
        }
        let last = show.frame(at: show.duration)
        #expect(last.numbers.count == template.numbers.count && last.ink.count == template.strokes.count)
    }

    @Test func theRealPipelineMakesAShow() throws {
        let recorder = InputsSnapshotRecorder()
        let output = try TemplateGenerator(settings: GenerationSettings(colorCount: 8, detail: 0.5))
            .generate(from: InputsTestPhoto.make(), cancel: .none, observer: recorder.receive)
        let pictures = try ShowPictures(snapshots: recorder.values)
        let template = ShowTemplate(output.template, width: pictures.width, height: pictures.height)
        let spec = try ShowSpec(json: shippedSpecData())
        let show = try FieldShow(pictures: pictures, template: template, spec: spec, seed: 5)
        #expect(show.size.width == pictures.width && show.size.height == pictures.height)
        var pixels = Plane<SIMD4<UInt8>>(width: pictures.width, height: pictures.height, repeating: .zero)
        var distinct = Set<SIMD4<UInt8>>()
        for t in stride(from: 0.0, through: show.duration, by: 0.5) {
            let frame = show.frame(at: t)
            show.composite(frame, into: &pixels)
            distinct.formUnion(pixels.data)
            #expect(frame.sprites.isEmpty)
        }
        #expect(distinct.count > 50)
        // the finished drawing has every number, and a line for each of the template's
        let last = show.frame(at: show.duration - 0.5)
        #expect(last.numbers.count == template.numbers.count && last.ink.count == template.strokes.count)
    }

    // MARK: Cores

    /// The same bytes on one core and on four (and on any other number): the bands follow the core count
    /// (two for each, `Parallel.bandCount`), so what a show makes must not depend on how they are cut.
    /// The field show's own loops cut into a number of bands a test can fix (`FieldBands`); the layers and
    /// the compositor it shares with the crew's show keep the machine's.
    @Test func theSameBytesOnOneCoreAndOnFour() throws {
        let reference = Self.digest(of: try FieldFixture.small)
        for bands in [1, 2, 3, 8, 64] {
            let digest = try FieldBands.$count.withValue(bands) { Self.digest(of: try FieldFixture.make()) }
            #expect(digest == reference, "\(bands) bands")
        }
        #expect(reference.count > 10)
    }

    /// A fingerprint of the show: its fields, its fuses, its numbers, and the frames and composites of
    /// every quarter second.
    static func digest(of show: FieldShow) -> [UInt64] {
        func hash(_ values: some Sequence<Double>) -> UInt64 { UInt64(fingerprint(values), radix: 16)! }
        func bytes(_ pixels: Plane<SIMD4<UInt8>>) -> [Double] {
            pixels.data.map { pixel in
                let key = UInt32(pixel.x) << 16 | UInt32(pixel.y) << 8 | UInt32(pixel.z)
                return Double(key)
            }
        }
        let times = show.compositor.times
        let planes = [times.sketch, times.shading, times.paints, times.merged, times.lift, times.clear]
        var out = planes.map { hash($0.data.map(Double.init)) }
        out.append(hash(show.fuses.flatMap { $0 }))
        out.append(hash(show.numberTimes))
        out.append(hash(show.spread))
        out.append(hash(show.strokes.flatMap { $0.relax }))
        var pixels = Plane<SIMD4<UInt8>>(width: show.size.width, height: show.size.height, repeating: .zero)
        for t in stride(from: 0.0, through: show.duration, by: 0.25) {
            let frame = show.frame(at: t)
            show.composite(frame, into: &pixels)
            out.append(hash(bytes(pixels)))
            out.append(hash(frame.ink.flatMap { $0.points.flatMap { [$0.x, $0.y] } }))
            let sparks = frame.sparks.flatMap { [$0.x, $0.y, $0.heat] }
            let stars = frame.stars.flatMap { [$0.x, $0.y, $0.radius, $0.alpha] }
            out.append(hash(sparks + stars))
        }
        return out
    }
}
