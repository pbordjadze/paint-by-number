import Foundation

/// Photo → region label map + palette.
///
/// PLACEHOLDER implementation: plain k-means in OKLab + connected components. It exists
/// so the rest of the system can be developed against realistic data; the production
/// pipeline replaces it.
public enum Segmenter {
    public static func segment(
        _ image: RGBAImage,
        importance: Grid<Float>?,
        settings: GenerationSettings,
        cancel: CancellationCheck,
        clock: StageClock,
        progress: (Float) -> Void
    ) throws -> Segmentation {
        let lab = clock.measure("segment.oklab") { ColorScience.okLabImage(from: image) }
        let k = settings.colorCount
        var rng = SplitMix64(seed: settings.seed)
        let n = lab.count
        var centers: [SIMD3<Float>] = (0..<k).map { _ in
            let p = lab.storage[Int(rng.next() % UInt64(n))]
            return SIMD3(p.x, p.y, p.z)
        }
        var assignment = [UInt32](repeating: 0, count: n)
        for _ in 0..<8 {
            try cancel.throwIfCancelled()
            var sums = [SIMD3<Float>](repeating: .zero, count: k)
            var counts = [Int](repeating: 0, count: k)
            for i in stride(from: 0, to: n, by: 1) {
                let p = lab.storage[i]
                let c = SIMD3(p.x, p.y, p.z)
                var best = 0
                var bestD = Float.infinity
                for j in 0..<k {
                    let d = c - centers[j]
                    let dd = (d * d).sum()
                    if dd < bestD { bestD = dd; best = j }
                }
                assignment[i] = UInt32(best)
                sums[best] += c
                counts[best] += 1
            }
            for j in 0..<k where counts[j] > 0 { centers[j] = sums[j] / Float(counts[j]) }
        }
        let classes = Grid(width: image.width, height: image.height, storage: assignment)
        let components = ConnectedComponents.label(classes)
        progress(1)
        return Segmentation(
            labels: components.labels,
            regionColor: components.classOf,
            palette: centers.map { PaletteColor(oklab: $0, space: image.colorSpace) },
            colorSpace: image.colorSpace)
    }
}

/// Small, fast, deterministic PRNG (SplitMix64).
public struct SplitMix64: RandomNumberGenerator, Sendable {
    public var state: UInt64

    public init(seed: UInt64) { state = seed }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform float in [0, 1).
    public mutating func nextFloat() -> Float {
        Float(next() >> 40) * (1.0 / Float(1 << 24))
    }
}
