/// Frozen v2 arithmetic. All naming decisions use integers; Float inputs are decoded by bits.
/// Q16 coordinates round to nearest, ties away from zero. Distances sort by squared Euclidean
/// distance (ties by table index), then use floor(sqrt(d²)) in Q16 for the window and weights.
/// The radius/window are 7864/1311 units (0.12/0.02 rounded to Q16); keep 24 candidates, draw
/// among the first six inside the window, then try untaken candidates in distance order.
///
/// Weights approximate exp(-d/0.03) by (1 + d/(256*1966))^-256: start with
/// floor(2^24 * 503296/(503296+d)), then square/divide by 2^24 eight times, flooring each time.
/// Map one SplitMix64(seed ^ paletteIndex) word with high64(word * sum(weights)); never modulo.
/// Integer sums are in pool order. All constants, rounding, ordering and fallback are frozen.
/// The maximum coordinate magnitude is 8 (far outside the gamut): distances fit in 42 bits,
/// Q24 weight products in 49, and the six-weight total in 27. No unchecked overflow is used.
/// The structured fallback has its own integer classifier, leaving v1's ColorName untouched.
/// Exact Float conversions in anchorLab are only for the public vocabulary/validation API;
/// each Q16 integer fits in 24 bits, and division by 2^16 is exact on IEEE binary32.
enum ColorNicknameV2 {
    static let scale: Int64 = 65536
    static let radius: Int64 = 7864
    static let window: Int64 = 1311

    static func coordinate(_ value: Float) -> Int64? {
        let bits = value.bitPattern
        let exponent = Int((bits >> 23) & 255)
        guard exponent != 255 else { return nil }
        let sign: Int64 = bits >> 31 == 0 ? 1 : -1
        if exponent >= 130 { return sign * 8 * scale }
        let shift = 134 - exponent
        if shift > 24 { return 0 } // Includes subnormals and signed zero.
        let significand = Int64((bits & 0x7fffff) | 0x800000)
        return sign * ((significand + (1 << (shift - 1))) >> shift)
    }

    static func point(_ lab: SIMD3<Float>) -> SIMD3<Int64>? {
        guard let l = coordinate(lab.x), let a = coordinate(lab.y), let b = coordinate(lab.z) else { return nil }
        return SIMD3(l, a, b)
    }

    static func anchorLab(at index: Int) -> SIMD3<Float> {
        let q = anchors[index]
        return SIMD3(Float(q.x), Float(q.y), Float(q.z)) / 65536
    }

    /// Floor square root by integer Newton iteration; n is at most 3 * (16 * 65536)^2.
    static func squareRoot(_ n: Int64) -> Int64 {
        guard n > 0 else { return 0 }
        var x = n
        var next = (x + 1) / 2
        while next < x {
            x = next
            next = (x + n / x) / 2
        }
        return x
    }

    static func nearest(to point: SIMD3<Int64>) -> [(index: Int, distance: Int64)] {
        var found: [(index: Int, squared: Int64)] = []
        for (index, anchor) in anchors.enumerated() {
            let l = point.x - anchor.x, a = point.y - anchor.y, b = point.z - anchor.z
            let squared = (l * l + a * a) + b * b
            if squared <= radius * radius { found.append((index, squared)) }
        }
        found.sort { $0.squared != $1.squared ? $0.squared < $1.squared : $0.index < $1.index }
        return found.prefix(24).map { ($0.index, squareRoot($0.squared)) }
    }

    static func weight(distance: Int64) -> UInt64 {
        let unit: UInt64 = 1 << 24
        var weight = unit * 503296 / (503296 + UInt64(distance))
        for _ in 0..<8 { weight = weight * weight / unit }
        return max(1, weight)
    }

    static func ticket(word: UInt64, total: UInt64) -> UInt64 {
        word.multipliedFullWidth(by: total).high
    }

    static func assign(_ palette: [PaletteColor], seed: UInt64, entries: [ColorNickname.Entry]) -> [String] {
        var taken = Set<Int>()
        return palette.enumerated().map { index, color in
            guard let point = point(color.oklab) else { return "Gray" }
            let candidates = nearest(to: point)
            var order = candidates.map(\.index)
            if let first = candidates.first {
                let pool = candidates.prefix(6).filter { $0.distance <= first.distance + window }
                let weights = pool.map { weight(distance: $0.distance) }
                let total = weights.reduce(0, +)
                var rng = SplitMix64(seed: seed ^ UInt64(index))
                var ticket = ticket(word: rng.next(), total: total)
                for (candidate, weight) in zip(pool, weights) {
                    if ticket < weight {
                        order.removeAll { $0 == candidate.index }
                        order.insert(candidate.index, at: 0)
                        break
                    }
                    ticket -= weight
                }
            }
            if let pick = order.first(where: { !taken.contains($0) }) {
                taken.insert(pick)
                return entries[pick].name
            }
            return fallback(point).englishTitle
        }
    }

    /// v2's structured fallback follows the familiar hue/lightness bands, with fixed arithmetic.
    /// Chroma is floor(sqrt(a²+b²)); hue tests use cross products against frozen Q30 rays, so no
    /// atan2/sin/cos is needed. Threshold percentages compare integer products without division.
    static func fallback(_ point: SIMD3<Int64>) -> ColorName {
        let l = point.x, a = point.y, b = point.z
        let c = squareRoot(a * a + b * b)
        let mc = maxChroma(l: l, a: a, b: b, c: c)
        let denominator = max(l, 3277) // 0.05, rounded to Q16.
        let grayish = mc == 0 || c * 100 < mc * 28 || c * 100 < denominator * 7
        let chroma: ColorName.Chroma = grayish ? .grayish
            : (c * 100 >= mc * 62 && c * 100 >= denominator * 16 ? .vivid : .muted)
        func name(_ family: ColorName.Family, _ lightness: ColorName.Lightness) -> ColorName {
            ColorName(family: family, lightness: lightness, chroma: chroma)
        }
        if l * 100 < 20 * scale || (l * 100 < 25 * scale && grayish) { return name(.black, .veryDark) }
        if c * 100 < 2 * scale || (c * 1000 < 35 * scale && (mc == 0 || c * 100 < mc * 12)) {
            return l * 100 > 93 * scale ? name(.white, .pale) : name(.gray, band(.gray, l))
        }
        if l * 100 > 95 * scale && c * 100 < 3 * scale { return name(.white, .pale) }

        // Rays are nearest integers to (cos θ, sin θ) * 2^30; offline constants, never libm.
        func below(_ ray: (Int64, Int64)) -> Bool {
            if ray.1 >= 0 && b < 0 { return false }
            if ray.1 < 0 && b >= 0 { return true }
            return ray.0 * b - ray.1 * a < 0
        }
        let h12 = below((1050277989, 223243478)), h25 = below((973140576, 453782903))
        let h38 = below((846120104, 661061475)), h45 = below((759250125, 759250125))
        let h80 = below((186453311, 1057429273)), h90 = below((0, 1073741824))
        let h110 = below((-367241333, 1008987269)), h115 = below((-453782903, 973140576))
        let h135 = below((-759250125, 759250125)), h175 = below((-1069655912, 93582766))
        let h220 = below((-822533958, -690187940)), h280 = below((186453311, -1057429273))
        let h318 = below((797945680, -718473518)), h345 = below((1037154959, -277904834))
        var family: ColorName.Family
        if !h345 || h38 {
            let core = !h345 || h12
            let pink = (core && (l * 100 >= 72 * scale || (l * 100 >= 60 * scale && chroma != .vivid)))
                || (!core && chroma != .vivid && l * 100 >= 65 * scale && (h25 || l * 100 >= 72 * scale))
            family = pink ? .pink : .red
        } else if h80 { family = .orange
        } else if h115 { family = .yellow
        } else if h175 { family = .green
        } else if h220 { family = .teal
        } else if h280 { family = .blue
        } else if h318 { family = .purple
        } else if l * 100 >= 72 * scale && chroma != .vivid { family = .pink
        } else { family = chroma == .vivid || l * 100 >= 65 * scale ? .magenta : .purple }

        if (family == .orange || family == .yellow) && l * 100 >= 72 * scale && chroma != .vivid
            && c * 10 < denominator && !h45 && h110 {
            family = .beige
        } else if family == .orange && (l * 100 < 50 * scale || (l * 100 < 65 * scale && chroma != .vivid)) {
            family = .brown
        } else if family == .yellow && l * 100 < 72 * scale {
            family = h90 ? .brown : .olive
        } else if family == .green && h135 && l * 100 < 72 * scale {
            family = .olive
        }
        if family == .blue && l * 100 < 40 * scale && chroma != .grayish { return name(.navy, .dark) }
        var lightness = band(family, l)
        if family == .beige { lightness = max(lightness, .medium) }
        if family == .brown { lightness = min(lightness, .light) }
        if lightness == .pale && chroma == .vivid { lightness = .light }
        return name(family, lightness)
    }

    private static func band(_ family: ColorName.Family, _ l: Int64) -> ColorName.Lightness {
        let lo: Int64, hi: Int64
        switch family {
        case .gray, .black, .white: (lo, hi) = (45, 72)
        case .red: (lo, hi) = (45, 70)
        case .orange: (lo, hi) = (60, 82)
        case .brown: (lo, hi) = (30, 58)
        case .beige: (lo, hi) = (72, 88)
        case .yellow: (lo, hi) = (76, 99)
        case .olive: (lo, hi) = (38, 65)
        case .green: (lo, hi) = (48, 80)
        case .teal, .magenta: (lo, hi) = (45, 75)
        case .blue, .navy: (lo, hi) = (42, 68)
        case .purple: (lo, hi) = (35, 62)
        case .pink: (lo, hi) = (65, 88)
        }
        if l * 100 < (lo - 15) * scale { return .veryDark }
        if l * 100 < lo * scale { return .dark }
        if l * 100 <= hi * scale { return .medium }
        return l * 100 <= (hi + 10) * scale ? .light : .pale
    }

    /// Search chroma in [0, 0.5], 16 bisections with floor midpoints (Q16). Unit hue comes from
    /// integer division toward zero. The inverse OKLab matrix coefficients are rounded to Q24;
    /// each multiply/divide truncates toward zero, in written order. Intermediate magnitudes
    /// stay below 2^55: l in [0,1], chroma <= 0.5, normalized a/b magnitude <= 1.00002.
    private static func maxChroma(l: Int64, a: Int64, b: Int64, c: Int64) -> Int64 {
        guard c > 0 else { return 0 }
        let unit: Int64 = 1 << 24
        let light = min(max(l, 0), scale) * 256
        let ca = a * scale / c, sa = b * scale / c
        func multiply(_ x: Int64, _ y: Int64) -> Int64 { x * y / unit }
        func cube(_ x: Int64) -> Int64 { multiply(multiply(x, x), x) }
        var lo: Int64 = 0, hi: Int64 = 32768
        for _ in 0..<16 {
            let mid = (lo + hi) / 2
            let aa = mid * ca * 256 / scale, bb = mid * sa * 256 / scale
            let ll = cube(light + multiply(6649445, aa) + multiply(3620586, bb))
            let mm = cube(light - multiply(1771025, aa) - multiply(1071295, bb))
            let ss = cube(light - multiply(1501295, aa) - multiply(21667532, bb))
            let r = multiply(68396375, ll) - multiply(55494192, mm) + multiply(3875032, ss)
            let g = -multiply(21280858, ll) + multiply(43784464, mm) - multiply(5726389, ss)
            let blue = -multiply(70399, ll) - multiply(11801406, mm) + multiply(28649021, ss)
            if min(r, g, blue) < -1678 || max(r, g, blue) > unit + 1678 { hi = mid } else { lo = mid }
        }
        return lo
    }
}
