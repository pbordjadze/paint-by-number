import Foundation

/// Whimsical names for palette colors ("Harbor Fog", "Apricot Jam"): each paint is matched to
/// hand-written vocabulary entries whose anchor colors lie near it, and the pick varies with the
/// painting's seed, so the same photo's colors read differently in two paintings and the same
/// painting always reads the same. The structured name (`ColorName`, "dark grayish blue")
/// remains the precise description and the fallback.
///
/// The vocabulary is English data: the app shows these names only while it runs in English and
/// shows the localized structured name otherwise. Its style guide is on `table`.
public enum ColorNickname {
    /// A name and the color it evokes.
    public struct Entry: Sendable, Hashable {
        public let name: String
        /// sRGB color the name was picked for, 0xRRGGBB.
        public let hex: UInt32
        /// `hex` in OKLab.
        public let oklab: SIMD3<Float>
    }

    /// Anchors beyond this OKLab distance (ΔE) from a paint never name it.
    public static let maximumDistance: Float = 0.12
    /// How many of the nearest anchors a paint's name is drawn from.
    public static let poolSize = 6
    /// The draw only considers anchors at most this much (ΔE, about one just noticeable
    /// difference) farther than the nearest one. Without it the sixth anchor of a muted paint,
    /// often 0.04 away and of another hue, weighs nearly as much as an exact match (a warm gray
    /// drew "Morning Lake", a blue-gray, one painting in ten).
    static let window: Float = 0.02
    /// Draw weights fall off as `exp(-distance / falloff)`: the nearest anchors win most often.
    static let falloff: Float = 0.03
    /// Anchors considered per paint, the draw pool first: when a paint's choices are taken by
    /// earlier paints it works down this list before it falls back to its structured name.
    static let candidateLimit = 24

    /// Every entry, in table order.
    public static let vocabulary: [Entry] = table.split(separator: "\n").map { line in
        let hex = UInt32(line.prefix(6), radix: 16) ?? 0
        let rgb = SIMD3(Float((hex >> 16) & 0xFF), Float((hex >> 8) & 0xFF), Float(hex & 0xFF)) / 255
        return Entry(name: String(line.dropFirst(7)), hex: hex, oklab: ColorScience.encodedToOKLab(rgb, space: .sRGB))
    }

    private static let names: Set<String> = Set(vocabulary.map(\.name))

    /// Whether `name` is one of the vocabulary's names (and not a structured fallback).
    public static func isNickname(_ name: String) -> Bool { names.contains(name) }

    /// A nickname per palette color: among the nearest anchors, unique within the palette, and
    /// varied by `seed` (the painting's identity), deterministically.
    ///
    /// Each paint draws one of its `poolSize` nearest anchors (true OKLab distance, none beyond
    /// `maximumDistance`, none more than `window` farther than the nearest) with weight
    /// `exp(-d / 0.03)` from `SplitMix64(seed ^ index)`. Paints
    /// are resolved in palette order: one whose draw is taken moves to its other candidates,
    /// nearest first, and one with none left (or none near) gets its structured name in English
    /// ("Dark grayish green"), so a result is never empty. Weights are rounded to integers
    /// before the draw so a last-bit difference in `exp` cannot change a name.
    public static func assign(_ palette: [PaletteColor], seed: UInt64) -> [String] {
        var taken = Set<Int>()
        var names: [String] = []
        names.reserveCapacity(palette.count)
        for (index, color) in palette.enumerated() {
            let candidates = nearest(to: color.oklab)
            var rng = SplitMix64(seed: seed ^ UInt64(index))
            var order = candidates.map(\.index)
            let pool = candidates.prefix(poolSize).filter { $0.distance <= candidates[0].distance + window }
            if let drawn = draw(pool, using: &rng), let position = order.firstIndex(of: drawn) {
                order.remove(at: position)
                order.insert(drawn, at: 0)
            }
            if let pick = order.first(where: { !taken.contains($0) }) {
                taken.insert(pick)
                names.append(vocabulary[pick].name)
            } else {
                names.append(color.colorName.englishTitle)
            }
        }
        return names
    }

    /// The nearest anchors within `maximumDistance`, closest first (ties by table order).
    static func nearest(to lab: SIMD3<Float>) -> [(index: Int, distance: Float)] {
        guard lab.x.isFinite, lab.y.isFinite, lab.z.isFinite else { return [] }
        var found: [(index: Int, distance: Float)] = []
        for (i, entry) in vocabulary.enumerated() {
            let d = ColorScience.distance(lab, entry.oklab)
            if d <= maximumDistance { found.append((i, d)) }
        }
        found.sort { $0.distance != $1.distance ? $0.distance < $1.distance : $0.index < $1.index }
        return Array(found.prefix(candidateLimit))
    }

    private static func draw(_ pool: [(index: Int, distance: Float)], using rng: inout SplitMix64) -> Int? {
        let weights = pool.map { UInt64(max(1, (Double(exp(-$0.distance / falloff)) * 1_000_000).rounded())) }
        let total = weights.reduce(0, +)
        guard total > 0 else { return nil }
        var ticket = rng.next() % total
        for (entry, weight) in zip(pool, weights) {
            if ticket < weight { return entry.index }
            ticket -= weight
        }
        return pool.last?.index
    }

    /// Folds a UUID (an artwork's identity) into the 64-bit seed `assign` takes: the XOR of its
    /// two big-endian halves. Stable by definition, so a painting's names never change.
    public static func seed(for id: UUID) -> UInt64 {
        let bytes = id.uuid
        let all = [bytes.0, bytes.1, bytes.2, bytes.3, bytes.4, bytes.5, bytes.6, bytes.7,
                   bytes.8, bytes.9, bytes.10, bytes.11, bytes.12, bytes.13, bytes.14, bytes.15]
        func half(_ range: Range<Int>) -> UInt64 { all[range].reduce(0) { $0 << 8 | UInt64($1) } }
        return half(0..<8) ^ half(8..<16)
    }
}

extension ColorName {
    /// `english` with a capital first letter, for names shown on their own ("Dark grayish green").
    public var englishTitle: String {
        let text = english
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }
}
