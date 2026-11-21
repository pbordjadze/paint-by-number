import Foundation

/// The cave's stick figure (Paul's choice, November 20, 2026: animals done properly, any other
/// subject comical): a child's first try on the wall, with a big round head, a wobbly body, one
/// arm waving and the other out, legs of not quite the same length, two dots for eyes and a grin.
/// Two areas, the head in yellow ochre and the rest in red ochre, so it is blown as easily as it
/// was drawn.
public enum CaveFigure {
    /// A figure about as wide as `aspect` (width over height) suggests, its wobble from `seed`.
    public static func plan(aspect: Float, seed: UInt64) -> CavePlan {
        let maxSize = CavePlan.maxSize
        let h = Int(maxSize.y * 0.92)
        let w = Int(min(maxSize.x, Float(h) * min(1.0, max(0.62, aspect))))
        var random = SplitMix64(seed: seed ^ 0xCA7E_F16E)
        func jitter(_ amount: Float) -> Float { (random.nextFloat() - 0.5) * 2 * amount }
        let W = Float(w), H = Float(h)
        let head = SIMD2(W * (0.5 + jitter(0.04)), H * 0.17), headRadius = H * 0.135
        let neck = SIMD2(W * 0.5, H * 0.3), hips = SIMD2(W * (0.48 + jitter(0.03)), H * 0.63)
        let shoulder = SIMD2(W * 0.5, H * 0.38)
        let limb = H * 0.075
        // Each stroke: from, to, and the thickness at each end.
        let strokes: [(SIMD2<Float>, SIMD2<Float>, Float, Float)] = [
            (neck, hips, limb * 1.2, limb * 1.05),
            (shoulder, SIMD2(W * 0.1, H * (0.16 + jitter(0.04))), limb, limb * 0.8),
            (shoulder, SIMD2(W * 0.9, H * (0.46 + jitter(0.05))), limb, limb * 0.8),
            (hips, SIMD2(W * (0.27 + jitter(0.03)), H * 0.97), limb, limb * 0.85),
            (hips, SIMD2(W * (0.68 + jitter(0.03)), H * (0.9 + jitter(0.02))), limb, limb * 0.85),
        ]
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
