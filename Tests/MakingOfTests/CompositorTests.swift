import Foundation
import Testing
@testable import MakingOf

/// `compose-small.json`, which `tools/tests/test_making_of_layers.py --write-goldens` writes: the
/// show's pictures at fourteen moments, on a 16 x 11 lattice, from the fixture's layers, reveal
/// times and ink that `CompositorFixture` builds the same closed-form way.
struct ComposeGolden: Decodable {
    struct Picture: Decodable {
        var t: Double
        var stage: Int
        var rgb: [Double]
    }

    var size: [Int]
    var intro: Double
    var step: Double
    var xs: [Int]
    var ys: [Int]
    var times: [String: [Double]]
    var ink: [Double]
    var pictures: [Picture]
}

enum CompositorFixture {
    static let fields = ["sketch", "shading", "paints", "merged", "lift", "clear"]

    /// Six reveal fields shaped like the real ones: step k's sweeps the picture between 0.1 s after
    /// the step starts and 0.3 s before it ends, in a smooth pattern of position. `synthetic_times`
    /// in `tools/tests/test_making_of_layers.py` is the same.
    static func times(width: Int, height: Int, intro: Double, step: Double) -> Compositor.Times {
        func field(_ k: Int) -> Plane<Float> {
            var plane = Plane<Float>(width: width, height: height, repeating: 0)
            for y in 0..<height {
                for x in 0..<width {
                    let u = 0.5 + 0.5 * sin(2.0 * Double(x) / Double(width) + 3.1 * Double(y) / Double(height) + 1.7 * Double(k))
                    // to 1/4096 s, so that no libm's sine can move a time by a Float step
                    plane[x, y] = Float(((intro + Double(k) * step + 0.1 + (step - 0.4) * u) * 4096).rounded(.toNearestOrEven) / 4096)
                }
            }
            return plane
        }
        return Compositor.Times(sketch: field(0), shading: field(1), paints: field(2), merged: field(3), lift: field(4), clear: field(5))
    }

    /// Lines to darken the paper by: ((x + 2 y) mod 7) / 6.
    static func ink(width: Int, height: Int) -> Plane<Float> {
        var plane = Plane<Float>(width: width, height: height, repeating: 0)
        for y in 0..<height {
            for x in 0..<width { plane[x, y] = Float(Double((x + 2 * y) % 7) / 6) }
        }
        return plane
    }

    static func compositor() throws -> (Compositor, ShowSpec) {
        let spec = try LayerFixture.spec()
        let layers = try LayerFixture.layers()
        let times = times(width: layers.width, height: layers.height, intro: spec.timing.intro, step: spec.timing.step)
        return (Compositor(layers: layers, times: times, intro: spec.timing.intro, step: spec.timing.step), spec)
    }
}

@Suite struct CompositorTests {
    // Swift against making_of_compose.py on the fixture, with the layers and the reveal's times
    // in Float as the clip tool runs them. Measured max over fourteen moments on 176 points: 4.2e-7
    // for a whole picture and 4.4e-7 for a single pixel (Linux x86-64, numpy 2.5), from the
    // Python's float32 sums and sine; the tolerance is about twice that. The closed-form times
    // are the same Floats, the ink the same to the golden's 7 decimals.
    private static let pictureTolerance = 9e-7
    private static let timeTolerance = 1e-9

    @Test func timesAreTheClosedFormOfPython() throws {
        let g: ComposeGolden = try LayerFixture.golden("compose-small.json")
        let times = CompositorFixture.times(width: g.size[0], height: g.size[1], intro: g.intro, step: g.step)
        let planes = [times.sketch, times.shading, times.paints, times.merged, times.lift, times.clear]
        let ink = CompositorFixture.ink(width: g.size[0], height: g.size[1])
        var worst = 0.0
        for (name, plane) in zip(CompositorFixture.fields, planes) {
            for (j, y) in g.ys.enumerated() {
                for (i, x) in g.xs.enumerated() {
                    worst = max(worst, abs(Double(plane[x, y]) - g.times[name]![j * g.xs.count + i]))
                }
            }
        }
        #expect(worst <= Self.timeTolerance)
        for (j, y) in g.ys.enumerated() {
            for (i, x) in g.xs.enumerated() { #expect(abs(Double(ink[x, y]) - g.ink[j * g.xs.count + i]) <= 1e-7) }
        }
    }

    @Test func picturesMatchPython() throws {
        let g: ComposeGolden = try LayerFixture.golden("compose-small.json")
        let (compositor, spec) = try CompositorFixture.compositor()
        #expect(g.intro == spec.timing.intro && g.step == spec.timing.step)
        let ink = CompositorFixture.ink(width: g.size[0], height: g.size[1])
        var worstPlane = 0.0
        var worstPixel = 0.0
        for picture in g.pictures {
            #expect(compositor.stage(at: picture.t) == picture.stage)
            let plane = compositor.picture(at: picture.t, ink: ink)
            for (j, y) in g.ys.enumerated() {
                for (i, x) in g.xs.enumerated() {
                    let expected = Array(picture.rgb[(j * g.xs.count + i) * 3..<(j * g.xs.count + i) * 3 + 3])
                    let single = compositor.pixel(x: x, y: y, at: picture.t, ink: Double(ink[x, y]))
                    for c in 0..<3 {
                        worstPlane = max(worstPlane, abs(Double(plane[x, y][c]) - expected[c]))
                        worstPixel = max(worstPixel, abs(single[c] - expected[c]))
                    }
                }
            }
        }
        #expect(worstPlane <= Self.pictureTolerance, "a picture is \(worstPlane) from Python")
        #expect(worstPixel <= Self.pictureTolerance, "a pixel is \(worstPixel) from Python")
    }

    @Test func stagesFollowTheTiming() throws {
        let (compositor, _) = try CompositorFixture.compositor()
        let (intro, step) = (compositor.intro, compositor.step)
        #expect([0, intro - 0.01, intro, intro + step - 0.01, intro + step, intro + 6 * step - 0.01, intro + 6 * step, 99].map { compositor.stage(at: $0) }
                == [-1, -1, 0, 0, 1, 5, 6, 6])
    }

    @Test func eachStepEndsInTheNextLayer() throws {
        let (compositor, _) = try CompositorFixture.compositor()
        let (w, h) = (compositor.layers.width, compositor.layers.height)
        for k in 0..<4 {
            let end = compositor.intro + Double(k + 1) * compositor.step
            for t in [end - 1e-9, end] {
                // the fields finish 0.3 s before the step ends, past every ramp and dip
                var worst = 0.0
                for y in stride(from: 0, to: h, by: 5) {
                    for x in stride(from: 0, to: w, by: 5) {
                        let got = compositor.pixel(x: x, y: y, at: t)
                        let next = compositor.layer(k + 1, y * w + x)
                        worst = max(worst, abs(got.x - next.x), abs(got.y - next.y), abs(got.z - next.z))
                    }
                }
                #expect(worst < 1e-6, "step \(k + 1) at \(t) is \(worst) from layer \(k + 1)")
            }
        }
    }

    @Test func theLastStepsEndInPaper() throws {
        let (compositor, _) = try CompositorFixture.compositor()
        let paper = RevealStyle.standard.paper / 255
        let end = compositor.intro + 6 * compositor.step
        for t in [end - 1e-9, end, end + 3] {
            for (x, y) in [(0, 0), (100, 70), (215, 143)] {
                let got = compositor.pixel(x: x, y: y, at: t)
                #expect(abs(got.x - paper.x) < 1e-12 && abs(got.y - paper.y) < 1e-12 && abs(got.z - paper.z) < 1e-12, "at \(t)")
            }
        }
    }

    @Test func beforeTheFirstStepIsThePhoto() throws {
        let (compositor, _) = try CompositorFixture.compositor()
        let photo = compositor.layers.photo
        for (x, y) in [(0, 0), (100, 70), (215, 143)] {
            #expect(compositor.pixel(x: x, y: y, at: 0.1, ink: 1) == ShowLayers.unit(photo[x, y]))
        }
    }

    @Test func linesOnlyShowWhereTheStepDrawsThem() throws {
        let (compositor, _) = try CompositorFixture.compositor()
        let (w, h) = (compositor.layers.width, compositor.layers.height)
        let ink = CompositorFixture.ink(width: w, height: h)
        let none = Plane<Float>(width: w, height: h, repeating: 0)
        for k in 0...3 {                       // steps without lines
            let t = compositor.intro + Double(k) * compositor.step + 1
            #expect(compositor.picture(at: t, ink: ink) == compositor.picture(at: t))
        }
        for k in 4...6 {
            let t = compositor.intro + Double(k) * compositor.step + 1
            let with = compositor.picture(at: t, ink: ink)
            let without = compositor.picture(at: t)
            #expect(with != without)
            #expect(zip(with.data, without.data).allSatisfy { $0.0.x <= $0.1.x && $0.0.y <= $0.1.y && $0.0.z <= $0.1.z })
            #expect(compositor.picture(at: t, ink: none) == without)
        }
    }

    @Test func fullInkIsTheInkColor() throws {
        let (compositor, _) = try CompositorFixture.compositor()
        let style = RevealStyle.standard
        let inked = compositor.pixel(x: 3, y: 4, at: compositor.intro + 6 * compositor.step + 1, ink: 1)
        let expected = style.paper / 255 * (style.ink / 255)
        #expect(abs(inked.x - expected.x) < 1e-12 && abs(inked.y - expected.y) < 1e-12 && abs(inked.z - expected.z) < 1e-12)
    }

    @Test func settlingOnlyDarkens() throws {
        let (compositor, _) = try CompositorFixture.compositor()
        let (w, h) = (compositor.layers.width, compositor.layers.height)
        let style = RevealStyle.standard
        for k in [2, 3] {
            let t = compositor.intro + Double(k) * compositor.step + 1.2
            let field = k == 2 ? compositor.times.paints : compositor.times.merged
            var darker = 0
            for y in 0..<h {
                for x in 0..<w {
                    let m = Compositor.smoothstep((t - Double(field[x, y])) / style.softLate)
                    let (lower, upper) = (compositor.layer(k, y * w + x), compositor.layer(k + 1, y * w + x))
                    let plain = lower + (upper - lower) * m
                    let got = compositor.pixel(x: x, y: y, at: t)
                    #expect(got.x <= plain.x + 1e-12 && got.y <= plain.y + 1e-12 && got.z <= plain.z + 1e-12)
                    if got.x < plain.x - 1e-6 { darker += 1 }
                }
            }
            #expect(darker > 0, "step \(k + 1) dips somewhere")
        }
    }

    @Test func theSketchStepNeverAddsColor() throws {
        // color drains and the photo fades to paper: the saturation of the picture only falls
        let (compositor, _) = try CompositorFixture.compositor()
        let t0 = compositor.intro
        func saturation(_ c: SIMD3<Double>) -> Double { max(c.x, c.y, c.z) - min(c.x, c.y, c.z) }
        var fell = 0
        for (x, y) in [(10, 10), (60, 40), (120, 90), (200, 130)] {
            let photo = saturation(compositor.pixel(x: x, y: y, at: t0 - 0.1))
            let late = saturation(compositor.pixel(x: x, y: y, at: t0 + compositor.step - 0.01))
            #expect(late <= photo + 1e-9)
            if late < photo - 0.01 { fell += 1 }
        }
        #expect(fell > 0)
    }

    @Test func aPictureIsMadeOfItsPixels() throws {
        let (compositor, _) = try CompositorFixture.compositor()
        let ink = CompositorFixture.ink(width: compositor.layers.width, height: compositor.layers.height)
        for t in [0.2, 1.7, 4.0, 6.6, 9.2, 11.6, 14.0, 17.0] {
            let plane = compositor.picture(at: t, ink: ink)
            for (x, y) in [(0, 0), (77, 31), (215, 143), (1, 142)] {
                #expect(plane[x, y] == SIMD3<Float>(compositor.pixel(x: x, y: y, at: t, ink: Double(ink[x, y]))), "at \(t)")
            }
        }
    }
}
