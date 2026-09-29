import Foundation

/// Orders paints the way a kit would: hue families around the color wheel starting at red,
/// each from light to dark, followed by the neutrals from white to black. Vivid and muted
/// paints of similar hue (a red hat vs. skin, grass vs. olive shadow) form separate,
/// adjacent families instead of interleaving by lightness.
enum PaletteOrdering {
    /// Chroma below which a paint counts as neutral (grey, white, black).
    static let neutralChroma: Float = 0.025
    /// Chroma below which a paint counts as muted (skin, earth tones, dusty colors).
    static let mutedChroma: Float = 0.07
    /// A hue gap wider than this (radians) starts a new family.
    static let familyGap: Float = 0.26
    /// Families wider than this (radians) are split at their largest internal gap.
    static let maxFamilySpan: Float = 0.7

    typealias Item = (index: Int, hue: Float)

    /// Returns indices into `palette` in display order.
    static func order(_ palette: [SIMD3<Float>]) -> [Int] {
        let lch = palette.map { ColorScience.lch($0) }
        var neutrals: [Int] = []
        var vivid: [Item] = []
        var muted: [Item] = []
        for (i, c) in lch.enumerated() {
            var h = c.z
            if h < 0 { h += 2 * .pi }
            if c.y < neutralChroma {
                neutrals.append(i)
            } else if c.y < mutedChroma {
                muted.append((i, h))
            } else {
                vivid.append((i, h))
            }
        }
        func lighterFirst(_ a: Int, _ b: Int) -> Bool {
            lch[a].x > lch[b].x || (lch[a].x == lch[b].x && a < b)
        }
        let all = families(vivid).map { ($0, false) } + families(muted).map { ($0, true) }
        let ordered = all.sorted { a, b in
            let ha = startHue(a.0), hb = startHue(b.0)
            if abs(ha - hb) > 0.35 { return ha < hb }
            if a.1 != b.1 { return !a.1 }
            return ha < hb || (ha == hb && a.0[0].index < b.0[0].index)
        }
        var result: [Int] = []
        for (family, _) in ordered { result += family.map(\.index).sorted(by: lighterFirst) }
        return result + neutrals.sorted(by: lighterFirst)
    }

    /// Groups colors by gaps in hue around the circle.
    static func families(_ items: [Item]) -> [[Item]] {
        guard !items.isEmpty else { return [] }
        let sorted = items.sorted { $0.hue < $1.hue || ($0.hue == $1.hue && $0.index < $1.index) }
        // Start right after the widest gap so no family straddles the cut.
        let m = sorted.count
        var widest = 0, widestGap: Float = -1
        for i in 0..<m {
            let next = sorted[(i + 1) % m].hue + (i + 1 == m ? 2 * .pi : 0)
            if next - sorted[i].hue > widestGap { widestGap = next - sorted[i].hue; widest = i }
        }
        var sequence: [Item] = []
        for k in 1...m {
            var e = sorted[(widest + k) % m]
            if widest + k >= m && widest + 1 < m { e.hue += 2 * .pi }
            sequence.append(e)
        }
        var pending: [[Item]] = [[sequence[0]]]
        for e in sequence.dropFirst() {
            if e.hue - pending[pending.count - 1].last!.hue > familyGap {
                pending.append([e])
            } else {
                pending[pending.count - 1].append(e)
            }
        }
        var result: [[Item]] = []
        while let f = pending.popLast() {
            if f.count > 1 && f.last!.hue - f.first!.hue > maxFamilySpan {
                var cut = 1, cutGap: Float = -1
                for i in 1..<f.count where f[i].hue - f[i - 1].hue > cutGap {
                    cutGap = f[i].hue - f[i - 1].hue
                    cut = i
                }
                pending.append(Array(f[..<cut]))
                pending.append(Array(f[cut...]))
            } else {
                result.append(f)
            }
        }
        return result
    }

    /// Mean hue of a family on a wheel that starts at deep pink/red (OKLab hue ≈ −20°).
    static func startHue(_ family: [Item]) -> Float {
        let mean = family.reduce(0) { $0 + $1.hue } / Float(family.count)
        var h = mean.truncatingRemainder(dividingBy: 2 * .pi)
        if h < 0 { h += 2 * .pi }
        return h > 5.9 ? h - 2 * .pi : h
    }
}
