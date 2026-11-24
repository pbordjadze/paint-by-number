#if canImport(FoundationEssentials) && !canImport(Darwin)
import FoundationEssentials
#else
import Foundation
#endif

/// A horse drawn from shapes, standing in for a photo and its subject mask where there is no
/// photo or no Vision: the cave's demo scenarios and tests. A dark mane, legs and muzzle, a mid
/// flank and a pale belly, so its plan has all four pigments.
public enum CaveSample {
    public static func horse() -> (photo: RGBAImage, subject: Grid<Float>) {
        let w = 600, h = 420
        typealias P = SIMD2<Float>
        // Each capsule: from, to, half width, and its light (0 dark to 1 pale).
        let parts: [(P, P, Float, Float)] = [
            (P(470, 92), P(540, 122), 22, 0.42), // head
            (P(530, 112), P(548, 126), 15, 0.16), // muzzle
            (P(478, 70), P(486, 50), 6, 0.3), // ear
            (P(398, 178), P(466, 98), 27, 0.46), // neck
            (P(392, 160), P(458, 84), 11, 0.12), // mane
            (P(206, 240), P(198, 392), 13, 0.15), (P(240, 248), P(246, 390), 13, 0.18),
            (P(370, 248), P(366, 392), 13, 0.15), (P(402, 240), P(410, 388), 13, 0.18), // legs
            (P(152, 180), P(118, 290), 11, 0.1), // tail
        ]
        var light = [Float](repeating: -1, count: w * h)
        for y in 0..<h {
            for x in 0..<w {
                let p = P(Float(x) + 0.5, Float(y) + 0.5)
                // The body: an ellipse, its back darker toward the rump and its belly pale.
                let b = (p - P(300, 200)) / P(155, 72)
                if (b * b).sum() < 1 {
                    let belly = max(0, (p.y - 210) / 60), rump = max(0, (250 - p.x) / 110)
                    light[y * w + x] = 0.48 + 0.34 * belly - 0.16 * rump
                }
                for (a, c, r, l) in parts {
                    let v = c - a, t = min(1, max(0, ((p - a) * v).sum() / (v * v).sum()))
                    let q = a + v * t - p
                    if (q * q).sum() < r * r { light[y * w + x] = l }
                }
            }
        }
        var pixels = [UInt8](repeating: 255, count: w * h * 4)
        var mask = [Float](repeating: 0, count: w * h)
        for i in 0..<(w * h) {
            let y = Float(i / w) / Float(h)
            var rgb: SIMD3<Float>
            if light[i] >= 0 {
                mask[i] = 1
                // A bay horse: brown, warmer where pale.
                let l = light[i]
                rgb = SIMD3(0.25 + 0.75 * l, 0.15 + 0.6 * l, 0.08 + 0.42 * l)
            } else {
                // Sky over grass.
                rgb = y < 0.7 ? SIMD3(0.62, 0.75, 0.9) : SIMD3(0.35, 0.55, 0.25)
            }
            for c in 0..<3 { pixels[i * 4 + c] = CaveBay.byte(rgb[c]) }
        }
        return (RGBAImage(width: w, height: h, pixels: pixels), Grid(width: w, height: h, storage: mask))
    }
}
