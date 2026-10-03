import Foundation
import PaintCore

/// How many lines the palette wraps into (Settings › Painting and the painting screen's More ›
/// Palette): rows at the bottom, columns along the trailing edge of a landscape iPad.
nonisolated enum PaletteRows: Int, CaseIterable, Identifiable, Sendable {
    /// A few lines on roomy screens (three at the bottom, two beside), one on compact ones.
    case auto = 0
    case one = 1, two, three, four, five, six
    /// As many as every color needs to show at once.
    case all = 99

    static let `default` = PaletteRows.auto

    var id: Int { rawValue }

    /// The most lines this choice wraps into, where `automatic` is what Auto allows here.
    /// A fixed count is used as given (capped by the colors left and the room on screen).
    func maxLines(automatic: Int) -> Int {
        switch self {
        case .auto: automatic
        case .all: .max
        default: rawValue
        }
    }

    /// Whether the palette uses all of `maxLines` (a fixed count) rather than the fewest that fit.
    var isFixed: Bool { self != .auto && self != .all }
}

/// The order of the palette's swatches (Settings › Painting and the painting screen's More ›
/// Palette). Custom is arranged per painting (`PaletteArrangeSheet`); a painting not arranged
/// yet goes by number.
nonisolated enum PaletteOrder: String, CaseIterable, Identifiable, Sendable {
    case number, rainbow, lightToDark, darkToLight, nearlyDone, mostLeft, custom

    static let `default` = PaletteOrder.number

    var id: String { rawValue }

    /// Below this OKLab chroma a paint reads as a gray: the rainbow puts grays after the hues.
    static let grayChroma: Float = 0.03

    /// `colors` (palette indices) in this order. `remaining` is each color's areas left to
    /// paint; `custom`, a painting's arrangement (colors it lacks follow by number). Ties keep
    /// number order, so the result depends only on its inputs.
    func arrange(_ colors: [Int], palette: [PaletteColor], remaining: [Int], custom: [Int]?) -> [Int] {
        func by<T: Comparable>(_ key: (Int) -> T) -> [Int] {
            colors.sorted { key($0) != key($1) ? key($0) < key($1) : $0 < $1 }
        }
        switch self {
        case .number:
            return colors.sorted()
        case .rainbow:
            return colors.sorted { a, b in
                let ka = Self.rainbowKey(palette[a].oklab), kb = Self.rainbowKey(palette[b].oklab)
                return ka != kb ? ka < kb : a < b
            }
        case .lightToDark:
            return by { -palette[$0].oklab.x }
        case .darkToLight:
            return by { palette[$0].oklab.x }
        case .nearlyDone:
            return by { remaining[$0] }
        case .mostLeft:
            return by { -remaining[$0] }
        case .custom:
            guard let custom else { return colors.sorted() }
            let rank = Dictionary(custom.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
            return by { rank[$0] ?? custom.count + $0 }
        }
    }

    /// Hues around the wheel from red (OKLab hue angle 0 sits at pink-red), then grays from
    /// light to dark.
    private static func rainbowKey(_ lab: SIMD3<Float>) -> RainbowKey {
        let lch = ColorScience.lch(lab)
        guard lch.y >= grayChroma else { return RainbowKey(isGray: true, value: -lch.x) }
        let turn = 2 * Float.pi
        return RainbowKey(isGray: false, value: (lch.z.truncatingRemainder(dividingBy: turn) + turn).truncatingRemainder(dividingBy: turn))
    }

    private struct RainbowKey: Comparable {
        var isGray: Bool
        var value: Float

        static func < (a: Self, b: Self) -> Bool {
            a.isGray != b.isGray ? !a.isGray : a.value < b.value
        }
    }

    // MARK: Custom arrangements

    /// Where a painting's custom arrangement is kept, by its nickname seed (unique per artwork).
    static func customKey(seed: UInt64) -> String { "paletteOrder.custom.\(seed)" }

    /// A painting's custom arrangement: a permutation of its `count` colors, or nil (none
    /// stored, or one that no longer fits, e.g. after the painting was regenerated).
    static func storedCustom(seed: UInt64, count: Int, in defaults: UserDefaults = .standard) -> [Int]? {
        guard let stored = defaults.array(forKey: customKey(seed: seed)) as? [Int],
              stored.count == count, Set(stored) == Set(0..<count)
        else { return nil }
        return stored
    }

    static func storeCustom(_ order: [Int], seed: UInt64, in defaults: UserDefaults = .standard) {
        defaults.set(order, forKey: customKey(seed: seed))
    }
}
