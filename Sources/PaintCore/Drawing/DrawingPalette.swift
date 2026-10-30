import Foundation

/// The paints of a template made from a drawing (`DrawingSettings`): a palette set, laid over
/// the areas so that no two neighbours share a paint.
///
/// A set is twelve paints in a fixed order: the first the paper's own light tint, for the
/// largest area (the ground around the figure), the rest mid-toned, so black ink reads on all
/// of them. `assign` lays them greedily, largest area first: each area takes the paint none
/// of its already painted neighbours has, the one used on the fewest areas so far, ties broken
/// by the seed; an area with more painted neighbours than there are paints takes the paint
/// used least among them. The palette is the set's paints that ended up used, in the set's
/// order, so the numbers run light to dark as the set does.
public enum DrawingPalette {
    public enum Set: String, Sendable, Codable, CaseIterable {
        /// Bright and primary, a child's box.
        case crayons
        /// Soft and pale.
        case pastels
        /// Ochres, umbers and olive.
        case earth
        /// Blues, teals and sand.
        case sea
        /// Pinks, greens and lilac.
        case garden
    }

    /// The fewest paints a drawing is laid with, and the areas per paint past which a set's
    /// next paint joins in (`paintCount`).
    public static let minimumPaints = 6
    static let areasPerPaint = 3

    /// A set's paints in order, as sRGB hex.
    static func hex(of set: Set) -> [String] {
        switch set {
        case .crayons:
            ["fbf5e6", "e8453c", "f4932a", "f6d23d", "6cbd4f", "2c9c7a", "4aa3df", "3a5fc4", "8a5bc4", "f088b6", "a9713e", "6f6f6f"]
        case .pastels:
            ["fdf8ee", "f6b8b0", "f9d5a7", "fbeeb0", "c7e5b4", "b3e0d4", "b7d5ef", "c6c3ea", "e5c1e0", "f2c9d5", "e2d2bd", "d2d2cf"]
        case .earth:
            ["f7f1e3", "b8432f", "d98b2b", "e2c04c", "7f8f3b", "4f7a5c", "6b8fa3", "5d5b8a", "9a6b4f", "c4a07a", "7a5a44", "8e8a80"]
        case .sea:
            ["f4f7f2", "e9d7a5", "f1b57f", "e07f6a", "9fc98f", "5fb3a6", "3c8fb6", "2d5f9c", "6c7fb6", "b5a8d2", "c9b79c", "7c8a90"]
        case .garden:
            ["fbf6ef", "e86f7e", "f2a36b", "f5d57c", "9bc96c", "4f9d75", "7cc3c9", "6b8fd1", "b08ad3", "f0b3cb", "c09a76", "8c8c8c"]
        }
    }

    /// A set's paints, in order, in sRGB.
    public static func colors(of set: Set) -> [PaletteColor] {
        hex(of: set).map { hex in
            let value = UInt32(hex, radix: 16)!
            let rgb = SIMD3<Float>(Float((value >> 16) & 255), Float((value >> 8) & 255), Float(value & 255)) / 255
            return PaletteColor(oklab: ColorScience.encodedToOKLab(rgb, space: .sRGB), rgb: rgb)
        }
    }

    /// How many of a set's paints `areas` areas are laid with: one more for every
    /// `areasPerPaint` areas, from `minimumPaints` up to the set's.
    public static func paintCount(areas: Int, available: Int) -> Int {
        min(available, max(minimumPaints, (areas + areasPerPaint - 1) / areasPerPaint))
    }

    /// The ink's own paint, for the areas a solid fill makes (`DrawingScan.solids`): a dark
    /// grey, so the drawing's lines still read on it, the last paint of every palette it is in.
    public static let ink = PaletteColor(oklab: ColorScience.encodedToOKLab(SIMD3(0.16, 0.15, 0.17), space: .sRGB), rgb: SIMD3(0.16, 0.15, 0.17))
    /// The paints laid over the areas of `labels` (above): a palette index per area, and the
    /// palette of the paints used. `inked`: per area, whether it is a solid fill, painted `ink`.
    static func assign(
        labels: RegionMap, areaCount: Int, set: Set, paints: Int?, seed: UInt64, inked: [Bool] = []
    ) -> (regionColor: [UInt32], palette: [PaletteColor]) {
        let colors = colors(of: set)
        let w = labels.width, h = labels.height
        var area = [Int](repeating: 0, count: areaCount)
        var neighbours = [Swift.Set<Int32>](repeating: [], count: areaCount)
        labels.storage.withUnsafeBufferPointer { l in
            for y in 0..<h {
                for x in 0..<w {
                    let i = y * w + x
                    let a = Int(l[i])
                    area[a] += 1
                    if x + 1 < w, l[i + 1] != l[i] { neighbours[a].insert(Int32(l[i + 1])); neighbours[Int(l[i + 1])].insert(Int32(a)) }
                    if y + 1 < h, l[i + w] != l[i] { neighbours[a].insert(Int32(l[i + w])); neighbours[Int(l[i + w])].insert(Int32(a)) }
                }
            }
        }
        let k = paints.map { min(max($0, 1), colors.count) } ?? paintCount(areas: areaCount, available: colors.count)
        var rng = SplitMix64(seed: seed ^ 0xd7a3_1a9e_5c0b_77f1)
        let order = (0..<areaCount).sorted { area[$0] != area[$1] ? area[$0] > area[$1] : $0 < $1 }
        var paint = [Int](repeating: -1, count: areaCount)
        var uses = [Int](repeating: 0, count: k + 1)
        // The solid fills take the ink, before any other area is laid.
        var anyInked = false
        for a in order where !inked.isEmpty && inked[a] {
            paint[a] = k
            uses[k] += 1
            anyInked = true
        }
        for a in order where paint[a] < 0 {
            var taken = [Bool](repeating: false, count: k)
            var takenCount = [Int](repeating: 0, count: k)
            for n in neighbours[a] where paint[Int(n)] >= 0 && paint[Int(n)] < k {
                taken[paint[Int(n)]] = true
                takenCount[paint[Int(n)]] += 1
            }
            var candidates = (0..<k).filter { !taken[$0] }
            if candidates.isEmpty {
                let fewest = takenCount.min()!
                candidates = (0..<k).filter { takenCount[$0] == fewest }
            }
            // The ground, the first and largest area, is the set's light tint; every other
            // area stays off it unless nothing else is free.
            if paint.allSatisfy({ $0 < 0 || $0 == k }) {
                candidates = [0]
            } else if candidates.count > 1, candidates[0] == 0 {
                candidates.removeFirst()
            }
            let fewest = candidates.map { uses[$0] }.min()!
            let best = candidates.filter { uses[$0] == fewest }
            let pick = best.count == 1 ? best[0] : best[Int(rng.next() % UInt64(best.count))]
            paint[a] = pick
            uses[pick] += 1
        }
        var index = [Int](repeating: -1, count: k + 1)
        var palette: [PaletteColor] = []
        for c in 0..<k where uses[c] > 0 {
            index[c] = palette.count
            palette.append(colors[c])
        }
        if anyInked {
            index[k] = palette.count
            palette.append(ink)
        }
        return (paint.map { UInt32(index[$0]) }, palette)
    }
}
