#if canImport(FoundationEssentials) && !canImport(Darwin)
import FoundationEssentials
#else
import Foundation
#endif

/// The cave's stick figure (Paul's choice, November 20, 2026: animals done properly, any other
/// subject comical): a child's first try on the wall, with a big round head, a wobbly body, one
/// arm waving and the other out, legs of not quite the same length, two dots for eyes and a grin.
/// Two areas, the head in yellow ochre and the rest in red ochre, so it is blown as easily as it
/// was drawn.
public enum CaveFigure {
    /// A figure about as wide as `aspect` (width over height) suggests, its wobble from `seed`;
    /// with a `pose` (the photo's person, found on the device), its arms and legs where theirs are.
    public static func plan(aspect: Float, seed: UInt64, pose: CavePose? = nil) -> CavePlan {
        let maxSize = CavePlan.maxSize
        var random = SplitMix64(seed: seed ^ 0xCA7E_F16E)
        func jitter(_ amount: Float) -> Float { (random.nextFloat() - 0.5) * 2 * amount }
        // The child's figure, in a unit box: one arm waving, the other out.
        var unit = CavePose.Skeleton(
            head: SIMD2(0.5 + jitter(0.04), 0.17), neck: SIMD2(0.5, 0.3), shoulder: SIMD2(0.5, 0.38),
            hips: SIMD2(0.48 + jitter(0.03), 0.63),
            hands: (SIMD2(0.1, 0.16 + jitter(0.04)), SIMD2(0.9, 0.46 + jitter(0.05))),
            elbows: (nil, nil),
            feet: (SIMD2(0.27 + jitter(0.03), 0.97), SIMD2(0.68 + jitter(0.03), 0.9 + jitter(0.02))),
            knees: (nil, nil), aspect: min(1.0, max(0.62, aspect)))
        if let posed = pose?.skeleton() { unit = posed }
        let h = Int(maxSize.y * 0.92)
        let w = Int(min(maxSize.x, Float(h) * unit.aspect))
        let W = Float(w), H = Float(h)
        func at(_ p: SIMD2<Float>) -> SIMD2<Float> { SIMD2(p.x * W, p.y * H) }
        let head = at(unit.head), headRadius = H * 0.135
        let neck = at(unit.neck), hips = at(unit.hips), shoulder = at(unit.shoulder)
        let limb = H * 0.075
        // Each stroke: from, to, and the thickness at each end; an elbow or a knee bends its limb.
        var strokes: [(SIMD2<Float>, SIMD2<Float>, Float, Float)] = [(neck, hips, limb * 1.2, limb * 1.05)]
        func limbStrokes(from a: SIMD2<Float>, bend: SIMD2<Float>?, to b: SIMD2<Float>, thick: Float, thin: Float) {
            if let bend {
                let m = at(bend), mid = (thick + thin) / 2
                strokes.append((a, m, thick, mid))
                strokes.append((m, at(b), mid, thin))
            } else {
                strokes.append((a, at(b), thick, thin))
            }
        }
        limbStrokes(from: shoulder, bend: unit.elbows.0, to: unit.hands.0, thick: limb, thin: limb * 0.8)
        limbStrokes(from: shoulder, bend: unit.elbows.1, to: unit.hands.1, thick: limb, thin: limb * 0.8)
        limbStrokes(from: hips, bend: unit.knees.0, to: unit.feet.0, thick: limb, thin: limb * 0.85)
        limbStrokes(from: hips, bend: unit.knees.1, to: unit.feet.1, thick: limb, thin: limb * 0.85)
        let phase = random.nextFloat() * 6.28
        var areas = [UInt16](repeating: 0, count: w * h)
        var lines = [Bool](repeating: false, count: w * h)
        for y in 0..<h {
            for x in 0..<w {
                let p = SIMD2(Float(x) + 0.5, Float(y) + 0.5)
                // A wobbling line, as drawn by a hand not yet sure of itself.
                let wobble = 1 + 0.12 * sin(p.x * 0.05 + p.y * 0.031 + phase)
                let d = p - head
                if (d.x * d.x + d.y * d.y).squareRoot() < headRadius * wobble {
                    areas[y * w + x] = 1
                    continue
                }
                for (a, b, ta, tb) in strokes {
                    let v = b - a, l2 = max(1, (v * v).sum())
                    let t = min(1, max(0, ((p - a) * v).sum() / l2))
                    let q = a + v * t - p
                    if (q * q).sum() < pow((ta + (tb - ta) * t) * wobble * 0.5, 2) {
                        areas[y * w + x] = 2
                        break
                    }
                }
            }
        }
        // Two dots for eyes and a grin, in charcoal.
        let eyes = [head + SIMD2(-headRadius * 0.36, -headRadius * 0.12), head + SIMD2(headRadius * 0.34, -headRadius * 0.16)]
        let dot = headRadius * 0.13, grin = headRadius * 0.55, ink = headRadius * 0.07
        for y in max(0, Int(head.y - headRadius))..<min(h, Int(head.y + headRadius) + 1) {
            for x in max(0, Int(head.x - headRadius))..<min(w, Int(head.x + headRadius) + 1) {
                let p = SIMD2(Float(x) + 0.5, Float(y) + 0.5)
                var on = eyes.contains { e in ((p - e) * (p - e)).sum() < dot * dot }
                let m = p - (head + SIMD2(0, -headRadius * 0.05))
                let r = (m * m).sum().squareRoot()
                if m.y > grin * 0.25, abs(r - grin) < ink { on = true }
                if on && areas[y * w + x] == 1 { lines[y * w + x] = true }
            }
        }
        return CavePlan(kind: .figure, width: w, height: h, mask: areas.map { $0 != 0 }, areas: areas,
                        pigments: [.yellowOchre, .redOchre], lines: lines)
    }
}

/// A person's pose as Vision finds it on the device, its joints in the photo's unit square (y
/// down), any of them missing: what the stick figure copies. Read as hostile input: a joint
/// that isn't finite and inside the photo is left out.
public struct CavePose: Sendable, Equatable {
    public enum Joint: Hashable, Sendable, CaseIterable {
        case nose, neck, leftShoulder, rightShoulder, leftElbow, rightElbow, leftWrist, rightWrist
        case root, leftKnee, rightKnee, leftAnkle, rightAnkle
    }

    public var joints: [Joint: SIMD2<Float>]

    public init(joints: [Joint: SIMD2<Float>]) {
        self.joints = joints.filter { $0.value.x.isFinite && $0.value.y.isFinite && (0...1).contains($0.value.x) && (0...1).contains($0.value.y) }
    }

    /// The figure's joints in its own unit box, and its width over height.
    struct Skeleton {
        var head, neck, shoulder, hips: SIMD2<Float>
        var hands: (SIMD2<Float>, SIMD2<Float>)
        var elbows: (SIMD2<Float>?, SIMD2<Float>?)
        var feet: (SIMD2<Float>, SIMD2<Float>)
        var knees: (SIMD2<Float>?, SIMD2<Float>?)
        var aspect: Float
    }

    /// The pose drawn as the child would: a neck, hips and at least two hands or feet are needed,
    /// or nil (the figure keeps its own pose). A missing hand or foot hangs straight down.
    func skeleton() -> Skeleton? {
        let j = joints
        let shoulders = [j[.leftShoulder], j[.rightShoulder]].compactMap { $0 }
        guard let neck = j[.neck] ?? (shoulders.count == 2 ? (shoulders[0] + shoulders[1]) / 2 : nil),
              let hips = j[.root], (hips.y - neck.y) > 0.02 else { return nil }
        let ends = [j[.leftWrist], j[.rightWrist], j[.leftAnkle], j[.rightAnkle]].compactMap { $0 }
        guard ends.count >= 2 else { return nil }
        let torso = hips.y - neck.y
        let head = j[.nose].map { SIMD2($0.x, min($0.y, neck.y - torso * 0.35)) } ?? neck - SIMD2(0, torso * 0.45)
        let shoulder = neck + (hips - neck) * 0.25
        func hanging(_ from: SIMD2<Float>, _ side: Float, _ length: Float) -> SIMD2<Float> { from + SIMD2(side * torso * 0.25, torso * length) }
        // The person's left is the figure's right as seen: the photo's own left and right are kept.
        let hands = (j[.rightWrist] ?? hanging(shoulder, -1, 0.9), j[.leftWrist] ?? hanging(shoulder, 1, 0.9))
        let feet = (j[.rightAnkle] ?? hanging(hips, -1, 1.1), j[.leftAnkle] ?? hanging(hips, 1, 1.1))
        let elbows = (j[.rightWrist] == nil ? nil : j[.rightElbow], j[.leftWrist] == nil ? nil : j[.leftElbow])
        let knees = (j[.rightAnkle] == nil ? nil : j[.rightKnee], j[.leftAnkle] == nil ? nil : j[.leftKnee])
        // The box round every point, the big head with room, in the photo's proportions.
        var points = [head, neck, shoulder, hips, hands.0, hands.1, feet.0, feet.1] + [elbows.0, elbows.1, knees.0, knees.1].compactMap { $0 }
        let radius = torso * 0.55
        points += [head - SIMD2(radius, radius), head + SIMD2(radius, 0)]
        let lo = points.reduce(SIMD2<Float>(repeating: .infinity)) { pointwiseMin($0, $1) }
        let hi = points.reduce(SIMD2<Float>(repeating: -.infinity)) { pointwiseMax($0, $1) }
        let pad = torso * 0.12
        let origin = lo - pad, size = pointwiseMax(hi - lo + 2 * pad, SIMD2(repeating: 0.001))
        // The head drawn at the figure's own size: 0.17 of the height down, wherever the box puts it.
        func unit(_ p: SIMD2<Float>) -> SIMD2<Float> { (p - origin) / size }
        let aspect = min(1.45, max(0.5, size.x / size.y))
        func u(_ p: SIMD2<Float>?) -> SIMD2<Float>? { p.map(unit) }
        return Skeleton(head: unit(head), neck: unit(neck), shoulder: unit(shoulder), hips: unit(hips),
                        hands: (unit(hands.0), unit(hands.1)), elbows: (u(elbows.0), u(elbows.1)),
                        feet: (unit(feet.0), unit(feet.1)), knees: (u(knees.0), u(knees.1)), aspect: aspect)
    }
}
