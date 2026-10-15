import Foundation
import PaintCore
import Testing
@testable import MakingOf

/// `frames-small.json`, which `tools/tests/test_making_of_show.py --write-goldens` writes: the small
/// show fixture built by `making_of_show.py` and fourteen moments of it, each frame and its
/// composite picture on a lattice.
struct FramesGolden: Decodable {
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
            }

            var lines: [Line]
            var fingerprint: String
        }

        struct Ring: Decodable {
            var x, y, radius, alpha: Double
        }

        struct Sprite: Decodable {
            struct Shadow: Decodable {
                var x, y, halfWidth, height, alpha: Double
            }

            var id: String
            var row: String
            var frame: Int
            var x, y, scaleX, scaleY, rotation, alpha: Double
            var shadow: Shadow
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
        var sprites: [Sprite]
        var card: Card?
        var coverageFingerprint: String?
        var rgb: [Double]
    }

    var size: [Int]
    var seed: UInt64
    var lineWidth: Double
    var duration: Double
    var xs: [Int]
    var ys: [Int]
    var frames: [Frame]

    static func load() throws -> FramesGolden {
        let url = try #require(Bundle.module.url(forResource: "frames-small.json", withExtension: nil, subdirectory: "Fixtures"))
        return try JSONDecoder().decode(FramesGolden.self, from: Data(contentsOf: url))
    }
}

/// The small show fixture built into a `Show` as the app would, once for all the tests that read it.
enum ShowFixture {
    static func sprites() throws -> [String: SpriteMetrics] {
        try SpriteMetrics.table(json: shippedMetricsData())
    }

    static func make(seed: UInt64 = SmallShow.seed, sprites: [String: SpriteMetrics]? = nil, cancel: CancellationCheck = .none) throws -> Show {
        let small = try SmallShow()
        return try Show(
            pictures: small.pictures, template: small.show, spec: small.spec, seed: seed,
            sprites: sprites ?? ShowFixture.sprites(), cancel: cancel)
    }

    private static let built = Result { try make() }

    static var small: Show {
        get throws { try built.get() }
    }
}

@Suite struct ShowTests {
    // Swift against making_of_show.py on the small fixture, over fourteen moments (Linux x86-64,
    // numpy 2.5, glibc libm). Everything the schedule makes is exact, bit for bit: the lines (the
    // fixture's fingerprints, also of their ink coverage), the numbers' alphas. The cards', rings' and
    // guardians' scalars come from sines, cosines and exponentials and measured 0.0 apart here,
    // but another libm's last bit is allowed: `scalarTolerance`. The composite picture is computed
    // from float32 layers, cube roots and powers the two languages compute differently: measured
    // 9.2e-7 apart in 0...1 (the sum of the layers' and the fields' roundings; the compositor alone
    // was 4.2e-7 in `CompositorTests`), and `pictureTolerance` is about twice that.
    private static let scalarTolerance = 1e-9
    /// A composite byte is the golden's float rounded to eight bits: half a step, plus this much in 0...1.
    private static let pictureTolerance = 2e-6

    @Test func framesMatchPython() throws {
        let g = try FramesGolden.load()
        let show = try ShowFixture.small
        #expect(g.size == [show.size.width, show.size.height] && g.duration == show.duration && g.lineWidth == show.lineWidth)
        var worst = 0.0
        for expected in g.frames {
            let frame = show.frame(at: expected.time)
            let at = "t = \(expected.time)"
            #expect(frame.time == expected.time && frame.step == expected.step, "\(at)")
            #expect(frame.picture == PictureRecipe(stage: expected.picture.stage, time: expected.picture.time, handoff: expected.picture.handoff), "\(at)")
            // the lines: exactly
            #expect(frame.ink.map(\.stroke) == expected.ink.lines.map(\.stroke), "\(at)")
            #expect(frame.ink.map(\.points.count) == expected.ink.lines.map(\.points), "\(at)")
            #expect(frame.ink.map(\.value) == expected.ink.lines.map(\.value), "\(at)")
            #expect(fingerprint(frame.ink.flatMap(\.points)) == expected.ink.fingerprint, "\(at)")
            #expect(frame.numbers == expected.numbers, "\(at)")
            // the overlays: exactly the same moments, within a libm's last bits
            #expect(frame.seedRings.count == expected.seedRings.count, "\(at)")
            for (ring, want) in zip(frame.seedRings, expected.seedRings) {
                for (got, wanted) in [(ring.x, want.x), (ring.y, want.y), (ring.radius, want.radius), (ring.alpha, want.alpha)] {
                    worst = max(worst, abs(got - wanted))
                    #expect(abs(got - wanted) <= Self.scalarTolerance, "ring at \(at)")
                }
            }
            #expect(frame.sprites.map(\.id) == expected.sprites.map(\.id), "\(at)")
            for (sprite, want) in zip(frame.sprites, expected.sprites) {
                #expect(sprite.row.rawValue == want.row && sprite.frame == want.frame, "\(sprite.id) at \(at)")
                let pairs = [
                    (sprite.x, want.x), (sprite.y, want.y), (sprite.scaleX, want.scaleX), (sprite.scaleY, want.scaleY),
                    (sprite.rotation, want.rotation), (sprite.alpha, want.alpha), (sprite.shadow.x, want.shadow.x),
                    (sprite.shadow.y, want.shadow.y), (sprite.shadow.halfWidth, want.shadow.halfWidth),
                    (sprite.shadow.height, want.shadow.height), (sprite.shadow.alpha, want.shadow.alpha),
                ]
                for (got, wanted) in pairs {
                    worst = max(worst, abs(got - wanted))
                    #expect(abs(got - wanted) <= Self.scalarTolerance, "\(sprite.id) at \(at): \(got) against \(wanted)")
                }
            }
            #expect((frame.card == nil) == (expected.card == nil), "\(at)")
            if let card = frame.card, let want = expected.card {
                #expect(card.step == want.step && card.caption == want.caption && card.methods == want.methods, "\(at)")
                worst = max(worst, abs(card.opacity - want.opacity), abs(card.footnoteOpacity - want.footnoteOpacity))
                #expect(abs(card.opacity - want.opacity) <= Self.scalarTolerance && abs(card.footnoteOpacity - want.footnoteOpacity) <= Self.scalarTolerance, "\(at)")
            }
        }
        Self.measured("frame scalars", worst)
    }

    @Test func compositesMatchPython() throws {
        let g = try FramesGolden.load()
        let show = try ShowFixture.small
        let (w, h) = (show.size.width, show.size.height)
        var pixels = Plane<SIMD4<UInt8>>(width: w, height: h, repeating: .zero)
        var worst = 0.0
        for expected in g.frames {
            let frame = show.frame(at: expected.time)
            show.composite(frame, into: &pixels)
            // the lines' coverage is exact, to the last bit
            if let want = expected.coverageFingerprint {
                let coverage = InkCoverage.plane(frame.ink, width: w, height: h, lineWidth: show.lineWidth)
                #expect(fingerprint(coverage.data.map(Double.init)) == want, "coverage at t = \(expected.time)")
            } else {
                #expect(frame.ink.isEmpty, "t = \(expected.time)")
            }
            let coverage = InkCoverage.plane(frame.ink, width: w, height: h, lineWidth: show.lineWidth)
            for (j, y) in g.ys.enumerated() {
                for (i, x) in g.xs.enumerated() {
                    let pixel = pixels[x, y]
                    #expect(pixel.w == 255)
                    let exact = show.compositor.pixel(x: x, y: y, at: expected.time, ink: Double(coverage[x, y]))
                    for (c, byte) in [pixel.x, pixel.y, pixel.z].enumerated() {
                        // the golden is the float picture: the byte is that rounded half up
                        let want = expected.rgb[(j * g.xs.count + i) * 3 + c]
                        worst = max(worst, abs(exact[c] - want))
                        #expect(abs(Double(byte) / 255 - want) <= 0.5 / 255 + Self.pictureTolerance, "t = \(expected.time) at (\(x), \(y)) channel \(c)")
                    }
                }
            }
        }
        Self.measured("composite", worst)
        #expect(worst <= Self.pictureTolerance)
    }

    /// What the last run measured, printed for the tolerances above (Swift Testing has no log of its own).
    private static func measured(_ what: String, _ value: Double) {
        print("ShowTests measured \(what): \(value)")
    }

    @Test func aFrameIsAFunctionOfTheTime() throws {
        let show = try ShowFixture.small
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
        let a = try ShowFixture.small
        let b = try ShowFixture.make()
        #expect(a.crew == b.crew)
        var pa = Plane<SIMD4<UInt8>>(width: a.size.width, height: a.size.height, repeating: .zero)
        var pb = pa
        for t in stride(from: 0.2, to: a.duration, by: 1.9) {
            let frame = a.frame(at: t)
            #expect(frame == b.frame(at: t))
            a.composite(frame, into: &pa)
            b.composite(frame, into: &pb)
            #expect(pa == pb, "t = \(t)")
        }
    }

    @Test func aDifferentSeedMakesADifferentShow() throws {
        let other = try ShowFixture.make(seed: 8)
        let show = try ShowFixture.small
        #expect(other.crew != show.crew)
    }

    @Test func theStagesComeInOrderWithTheirCards() throws {
        let show = try ShowFixture.small
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
                #expect(card.caption == spec.steps[card.step].caption && card.methods == spec.steps[card.step].methods)
                #expect(card.opacity > 0 && card.opacity <= spec.cards.opacity)
                #expect(abs(card.footnoteOpacity - card.opacity * spec.cards.footnote) < 1e-15)
            }
            #expect((frame.card == nil) == (frame.step == nil || show.timeline.cardFade(step: frame.step!, at: t) == 0))
            #expect(frame.numbers.isEmpty == (frame.picture.stage < 5))
            #expect(frame.seedRings.isEmpty || frame.picture.stage == 2)
            #expect(frame.ink.isEmpty || frame.picture.stage >= 4)
        }
        #expect(seen == Set(-1...6))
        #expect(show.frame(at: -5).picture.stage == -1 && show.frame(at: show.duration + 99).picture.stage == 6)
    }

    @Test func theWholeSpecifiedTimeIsPlayed() throws {
        let show = try ShowFixture.small
        let spec = try SmallShow().spec
        #expect(show.duration == spec.timing.intro + 6 * spec.timing.step + spec.timing.outro)
        #expect(show.size.width == 216 && show.size.height == 144)
        // by the end the crew is gone, and the hand-off has completed
        let end = show.frame(at: show.duration)
        #expect(end.sprites.isEmpty && end.picture.handoff == 1 && end.numbers.allSatisfy { $0 == 1 })
    }

    @Test func eachStepsChangeReachesEveryPixelBeforeItEnds() throws {
        let show = try ShowFixture.small
        let times = show.compositor.times
        let spec = try SmallShow().spec
        let planes = [times.sketch, times.shading, times.paints, times.merged, times.lift, times.clear]
        for (k, plane) in planes.enumerated() {
            let start = spec.timing.intro + Double(k) * spec.timing.step
            let end = start + spec.timing.step
            let low = plane.data.min()!, high = plane.data.max()!
            #expect(Double(low) >= start - 1e-6 && Double(high) <= end - 0.2 + 1e-5, "step \(k + 1): \(low) to \(high)")
            // the change spreads: not everywhere at once
            #expect(Double(high - low) > 0.2, "step \(k + 1)")
        }
    }

    @Test func guardiansWorkInsideThePicture() throws {
        let show = try ShowFixture.small
        let spec = try SmallShow().spec
        let end = spec.timing.intro + 6 * spec.timing.step
        var any = false
        for t in stride(from: 0.0, to: end, by: 0.05) {
            for sprite in show.frame(at: t).sprites {
                any = true
                #expect(sprite.x >= 0 && sprite.x <= Double(show.size.width), "\(sprite.id) at \(t): x = \(sprite.x)")
                #expect(sprite.y >= 0 && sprite.y <= Double(show.size.height) + 1, "\(sprite.id) at \(t): y = \(sprite.y)")
                #expect(sprite.shadow.y > sprite.y - 1e-9 && sprite.alpha > 0 && sprite.alpha <= 1)
                #expect(sprite.frame >= 0 && sprite.frame < sprite.row.frameCount)
            }
        }
        #expect(any)
        // and they leave the picture by the nearest edge, as the plan sent them
        let leaving = (0..<1200).flatMap { show.frame(at: end + Double($0) * 0.01).sprites }
        let (w, h) = (Double(show.size.width), Double(show.size.height))
        #expect(leaving.contains { $0.x < 0 || $0.x > w || $0.y < 0 || $0.y > h })
    }

    @Test func guardiansAreDrawnBackToFront() throws {
        let show = try ShowFixture.small
        for t in stride(from: 0.5, to: show.duration, by: 0.1) {
            let ys = show.frame(at: t).sprites.map(\.shadow.y)
            #expect(ys == ys.sorted(), "t = \(t)")
        }
    }

    @Test func aGuardianWithoutMetricsIsNamed() throws {
        var sprites = try ShowFixture.sprites()
        sprites["dinotopia"] = nil
        do {
            _ = try ShowFixture.make(sprites: sprites)
            Issue.record("a show was made without dinotopia's metrics")
        } catch let error as ShowError {
            #expect(error.description.contains("dinotopia"))
        }
    }

    @Test func buildingCanBeCancelled() throws {
        #expect(throws: CancellationError.self) { try ShowFixture.make(cancel: CancellationCheck { true }) }
    }

    @Test func theRealPipelineMakesAShow() throws {
        let recorder = InputsSnapshotRecorder()
        let output = try TemplateGenerator(settings: GenerationSettings(colorCount: 8, detail: 0.5))
            .generate(from: InputsTestPhoto.make(), cancel: .none, observer: recorder.receive)
        let pictures = try ShowPictures(snapshots: recorder.values)
        let template = ShowTemplate(output.template, width: pictures.width, height: pictures.height)
        let spec = try ShowSpec(json: shippedSpecData())
        let show = try Show(pictures: pictures, template: template, spec: spec, seed: 5, sprites: ShowFixture.sprites())
        #expect(show.size.width == pictures.width && show.size.height == pictures.height)
        var pixels = Plane<SIMD4<UInt8>>(width: pictures.width, height: pictures.height, repeating: .zero)
        var distinct = Set<SIMD4<UInt8>>()
        for t in stride(from: 0.0, through: show.duration, by: 0.5) {
            let frame = show.frame(at: t)
            show.composite(frame, into: &pixels)
            distinct.formUnion(pixels.data)
            #expect(frame.sprites.count <= 3)
        }
        #expect(distinct.count > 50)
        // the finished drawing has every number, and a line for each of the template's
        let last = show.frame(at: show.duration - 0.5)
        #expect(last.numbers.count == template.numbers.count && last.ink.count == template.strokes.count)
    }
}
