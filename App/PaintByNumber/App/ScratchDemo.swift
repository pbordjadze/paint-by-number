#if DEBUG
import Foundation
import PaintCore

/// The From Scratch spike's screens (painting-company row 239): `scratch-<design>-<step>`, with
/// `-dark` too, where the design is `today`, `a`, `b` or `c` (`ScratchDesign`) and the step one
/// of the path:
/// - `entry`: New Painting, where From Scratch is (C: its Samples, with the blank page first);
/// - `blank`: what From Scratch opens (A, B: the drawing space; C: the blank page's preview);
/// - `drawn`: the drawing space with a picture drawn as a painter would, the Pen's lines and
///   the Bucket's pours laid one by one (`drawing(side:)`);
/// - `after`: what the drawing space's finishing button leads to (A, C: the preview; B: the
///   painting);
/// - `picture`: a library picture picked (E: on the easel; S: its preview, Make It Mine).
struct ScratchDemo {
    enum Step: String { case entry, blank, drawn, after, picture }

    let design: ScratchDesign
    let step: Step

    static let current: ScratchDemo? = {
        guard let name = DemoMode.scenario, name.hasPrefix("scratch-") else { return nil }
        let parts = name.split(separator: "-").map(String.init)
        guard parts.count >= 3, let design = ScratchDesign(rawValue: parts[1]), let step = Step(rawValue: parts[2])
        else { return nil }
        return ScratchDemo(design: design, step: step)
    }()

    var draws: Bool { step == .drawn || step == .after }

    /// A house and a tree on a hill under the sun, in canvas units of a `side` × `side` page:
    /// the lines in the order drawn (each a Pen stroke), then a pour per shape (the Bucket).
    static func drawing(side: Float) -> (lines: [TemplateEditor.Edit], pours: [(at: SIMD2<Float>, color: SIMD3<Float>)]) {
        func at(_ x: Float, _ y: Float) -> SIMD2<Float> { SIMD2(x, y) * side }
        func circle(_ cx: Float, _ cy: Float, _ r: Float) -> [SIMD2<Float>] {
            (0..<48).map { k in
                let t = Float(k) / 48 * 2 * Float.pi
                return at(cx + r * cos(t), cy + r * sin(t))
            }
        }
        let hill = (0...24).map { k -> SIMD2<Float> in
            let x = Float(k) / 24
            return at(x, 0.47 - 0.07 * sin(Float.pi * x))
        }
        let crown = (cx: Float(0.76), cy: Float(0.6), r: Float(0.09))
        let trunkTop = crown.cy + (crown.r * crown.r - 0.025 * 0.025).squareRoot()
        let lines: [TemplateEditor.Edit] = [
            .draw(points: hill),
            .draw(points: circle(0.8, 0.18, 0.09), closed: true),
            .draw(points: [at(0.18, 0.64), at(0.5, 0.64), at(0.5, 0.88), at(0.18, 0.88)], closed: true),
            .draw(points: [at(0.18, 0.64), at(0.34, 0.5), at(0.5, 0.64)]),
            .draw(points: [at(0.3, 0.88), at(0.3, 0.74), at(0.38, 0.74), at(0.38, 0.88)]),
            .draw(points: [at(0.41, 0.69), at(0.47, 0.69), at(0.47, 0.76), at(0.41, 0.76)], closed: true),
            .draw(points: circle(crown.cx, crown.cy, crown.r), closed: true),
            .draw(points: [at(0.735, trunkTop), at(0.735, 0.88), at(0.785, 0.88), at(0.785, trunkTop)]),
        ]
        let pours: [(at: SIMD2<Float>, color: SIMD3<Float>)] = [
            (at(0.1, 0.15), SIMD3(0.8, -0.03, -0.09)),    // sky
            (at(0.8, 0.18), SIMD3(0.9, 0.0, 0.16)),       // sun
            (at(0.1, 0.8), SIMD3(0.68, -0.12, 0.11)),     // hill
            (at(0.22, 0.8), SIMD3(0.86, 0.02, 0.07)),     // walls
            (at(0.34, 0.58), SIMD3(0.56, 0.15, 0.08)),    // roof
            (at(0.34, 0.82), SIMD3(0.45, 0.05, 0.08)),    // door
            (at(0.44, 0.72), SIMD3(0.94, -0.01, 0.1)),    // window
            (at(0.76, 0.58), SIMD3(0.5, -0.1, 0.07)),     // crown
            (at(0.76, 0.82), SIMD3(0.42, 0.04, 0.06)),    // trunk
        ]
        return (lines, pours)
    }
}
#endif
