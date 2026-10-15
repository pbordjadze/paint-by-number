import Foundation
import PaintCore

/// The picture of the show at a moment, one pixel at a time: a pure CPU reference of what each
/// step does to the layers, which the app's Metal shader transliterates. Nothing is drawn here:
/// the crew, the ink step's pen and the template's outlines, the numbers, the seed rings and the
/// cards belong to the renderer, which passes the lines' coverage in as `ink` where the step has any.
/// `Compositor` in `tools/factory/making_of_compose.py` is the same formulas on the same names;
/// `CompositorTests` compares the two.
///
/// At time t the show is in a `stage(at:)` and shows
///
/// - the photo, before the first step;
/// - step 1 (sketch): where the reveal's time has passed, the photo's texture smears away and its
///   color drains, graphite goes down on the survivors, strongest structure first, and the photo
///   fades to paper behind it;
/// - steps 2 to 4 (shading, paints, merged): layer k becomes layer k + 1 as the time passes, with a
///   soft edge; steps 3 and 4 dip a little darker where much changes, as the paint settles;
/// - step 5 (ink): each merged region's grey lifts as its time passes, under the pen's `ink`;
/// - step 6 (template): regions clear to paper under the smooth outlines' `ink`;
/// - the finished drawing: paper under the outlines.
///
/// The layers are the paper under graphite (1), graphite and a wash of the smoothed picture's
/// lightness (2), the paints' greys and fading graphite (3), and the merged regions' greys (4);
/// layer 0 is the photo. The ink step and the template have no layer here: their lines are the
/// renderer's.
public struct Compositor: Sendable {
    /// When the change of each step reaches each pixel, in seconds, at the pictures' size.
    public struct Times: Sendable {
        public var sketch: Plane<Float>
        public var shading: Plane<Float>
        public var paints: Plane<Float>
        public var merged: Plane<Float>
        /// Step 5: when each merged region's grey lifts.
        public var lift: Plane<Float>
        /// Step 6: when each merged region clears to paper.
        public var clear: Plane<Float>

        public init(
            sketch: Plane<Float>, shading: Plane<Float>, paints: Plane<Float>, merged: Plane<Float>,
            lift: Plane<Float>, clear: Plane<Float>
        ) {
            self.sketch = sketch
            self.shading = shading
            self.paints = paints
            self.merged = merged
            self.lift = lift
            self.clear = clear
        }
    }

    public let layers: ShowLayers
    public let times: Times
    /// The show's timing (`ShowSpec.Timing`): the photo alone for `intro` seconds, then six steps of
    /// `step` seconds.
    public let intro: Double
    public let step: Double

    public init(layers: ShowLayers, times: Times, intro: Double, step: Double) {
        for plane in [times.sketch, times.shading, times.paints, times.merged, times.lift, times.clear] {
            precondition(plane.width == layers.width && plane.height == layers.height, "the times share the pictures' size")
        }
        self.layers = layers
        self.times = times
        self.intro = intro
        self.step = step
    }

    private var style: RevealStyle { layers.style }

    /// -1 before the first step, 0...5 in a step, 6 once the six are over.
    public func stage(at t: Double) -> Int {
        if t < intro { return -1 }
        if t >= intro + 6 * step { return 6 }
        return min(Int(((t - intro) / step).rounded(.down)), 5)
    }

    /// The whole picture at time t; `ink` is the lines' coverage (0 for none, 1 for full ink) in the
    /// steps that draw lines, and is ignored before them.
    public func picture(at t: Double, ink: Plane<Float>? = nil) -> Plane<SIMD3<Float>> {
        if let ink { precondition(ink.width == layers.width && ink.height == layers.height, "the ink shares the pictures' size") }
        let (w, h) = (layers.width, layers.height)
        let k = stage(at: t)
        var result = Plane<SIMD3<Float>>(width: w, height: h, repeating: .zero)
        result.data.withUnsafeMutableBufferPointer { buffer in
            let out = UncheckedSendable(buffer.baseAddress!)
            Parallel.forEachBand(h) { rows in
                for y in rows {
                    for x in 0..<w {
                        let i = y * w + x
                        out.value[i] = SIMD3<Float>(shade(i, at: t, stage: k, ink: Double(ink?.data[i] ?? 0)))
                    }
                }
            }
        }
        return result
    }

    /// One pixel of `picture(at:ink:)`.
    public func pixel(x: Int, y: Int, at t: Double, ink: Double = 0) -> SIMD3<Double> {
        shade(y * layers.width + x, at: t, stage: stage(at: t), ink: ink)
    }

    // MARK: Formulas

    func shade(_ i: Int, at t: Double, stage k: Int, ink: Double) -> SIMD3<Double> {
        let style = style
        let paper = style.paper / 255
        let inkMultiply = SIMD3(repeating: 1) - SIMD3(repeating: ink) * (SIMD3(repeating: 1) - style.ink / 255)
        switch k {
        case ..<0:
            return layer(0, i)
        case 0:
            return sketchStep(i, at: t, paper: paper)
        case 1...3:
            let reveal = Double((k == 1 ? times.shading : k == 2 ? times.paints : times.merged).data[i])
            let lower = layer(k, i)
            let upper = layer(k + 1, i)
            let m = Self.smoothstep((t - reveal) / (k < 2 ? style.softEarly : style.softLate))
            let picture = lower + (upper - lower) * m
            guard k >= 2 else { return picture }
            let change = upper - lower
            let settle = min(max(max(abs(change.x), abs(change.y), abs(change.z)) * style.settleGain, 0), 1)
            let bump = sin(Double.pi * min(max((t - reveal) / style.settleRamp, 0), 1))
            return picture * (1 - style.settleDepth * bump * settle)
        case 4:
            let toned = Double(layers.simplifiedGrey.data[i])
            let lifted = 1 - style.liftShare * (1 - toned)
            let lift = Self.smoothstep((t - Double(times.lift.data[i])) / style.liftRamp)
            return paper * (toned + (lifted - toned) * lift) * inkMultiply
        case 5:
            let toned = Double(layers.simplifiedGrey.data[i])
            let lifted = 1 - style.liftShare * (1 - toned)
            let clear = Self.smoothstep((t - Double(times.clear.data[i])) / style.clearRamp)
            return paper * (lifted + (1 - lifted) * clear) * inkMultiply
        default:
            return paper * inkMultiply
        }
    }

    /// Step 1 at pixel `i`.
    private func sketchStep(_ i: Int, at t: Double, paper: SIMD3<Double>) -> SIMD3<Double> {
        let style = style
        let reveal = Double(times.sketch.data[i])
        let end = intro + step
        let photo = layer(0, i)
        let detextured = SIMD3<Double>(layers.detextured.data[i])
        let smear = Self.smoothstep((t - reveal) / style.smearRamp)
        var base = photo + (detextured - photo) * smear
        let drain = Self.smoothstep((t - reveal - style.drainDelay) / style.drainRamp)
        base += (SIMD3(repeating: (base * style.luma).sum()) - base) * drain
        let drawnAt = min(reveal + style.graphiteDelay - style.graphiteByStructure * Double(layers.survivors.data[i]), end - style.graphiteMargin)
        let drawn = Self.smoothstep((t - drawnAt) / style.graphiteRamp)
        let washed = Self.smoothstep((t - min(reveal + style.washDelay, end - style.washMargin)) / style.washRamp)
        return (base + (paper - base) * washed) * (SIMD3(repeating: 1) - drawn * (SIMD3(repeating: 1) - graphite(i, strength: style.sketchStrengths.x)))
    }

    /// Layer `k` (0...4) at pixel `i`: 0 is the photo, 1 the paper under graphite, 2 also under a
    /// wash of the smoothed picture's lightness, 3 under the paints' greys and weaker graphite, 4
    /// under the merged regions' greys.
    func layer(_ k: Int, _ i: Int) -> SIMD3<Double> {
        let style = style
        let paper = style.paper / 255
        switch k {
        case 0:
            return ShowLayers.unit(layers.photo.data[i])
        case 1:
            return paper * graphite(i, strength: style.sketchStrengths.x)
        case 2:
            let wash = 1 - style.washStrength * (1 - Double(layers.smoothedLightness.data[i]))
            return paper * SIMD3(repeating: wash) * graphite(i, strength: style.sketchStrengths.y)
        case 3:
            return paper * SIMD3(repeating: Double(layers.paletteGrey.data[i])) * graphite(i, strength: style.sketchStrengths.z)
        default:
            return paper * Double(layers.simplifiedGrey.data[i])
        }
    }

    /// A multiply layer: graphite where the survivors are strong, `strength` of the way to the
    /// darkest.
    private func graphite(_ i: Int, strength: Double) -> SIMD3<Double> {
        let style = style
        let structure = Double(layers.survivors.data[i])
        let darkness = pow(min(max((structure - style.graphiteFloor) / style.graphiteSpan, 0), 1), style.graphiteExponent)
            * style.graphiteDensity * strength
        return SIMD3(repeating: 1) - SIMD3(repeating: darkness) * (SIMD3(repeating: 1) - style.graphite)
    }

    static func smoothstep(_ x: Double) -> Double {
        let x = min(max(x, 0), 1)
        return x * x * (3 - 2 * x)
    }
}
