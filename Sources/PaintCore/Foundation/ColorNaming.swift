import Foundation

/// A deterministic, structured color name ("dark grayish green") derived from OKLab; `english`
/// renders it for the CLI and the app localizes the same structure.
///
/// Lightness bands are relative to each hue family (pure red sits in red's medium band, so it is
/// "vivid red", not "light red"; yellow only exists light). Chroma combines two measures: `rel`,
/// the fraction of the most saturated sRGB color at this lightness and hue, and `sat`, chroma
/// relative to lightness, so dark colors with little absolute chroma can still read as vivid.
/// Medium lightness and muted chroma are the unmarked defaults and are never spoken, which keeps
/// names short (at most four words).
public struct ColorName: Sendable, Hashable {
    public enum Family: String, Sendable, CaseIterable {
        case black, white, gray, red, orange, brown, beige, yellow, olive, green, teal, blue, navy, purple, magenta, pink
    }

    public enum Lightness: Int, Sendable, CaseIterable, Comparable {
        case veryDark, dark, medium, light, pale

        public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
    }

    public enum Chroma: Int, Sendable, CaseIterable {
        case grayish, muted, vivid
    }

    public var family: Family
    public var lightness: Lightness
    public var chroma: Chroma

    public init(family: Family, lightness: Lightness, chroma: Chroma) {
        self.family = family
        self.lightness = lightness
        self.chroma = chroma
    }

    /// Classifies an OKLab color. Neutrals are decided first (very dark colors are black whatever
    /// their hue), then a hue sector picks the family, and lightness/chroma split sectors that
    /// English names differently (dark orange is brown, pale red is pink, dark blue is navy).
    public init(oklab lab: SIMD3<Float>) {
        guard lab.x.isFinite, lab.y.isFinite, lab.z.isFinite else {
            self.init(family: .gray, lightness: .medium, chroma: .grayish)
            return
        }
        let lch = ColorScience.lch(lab)
        let L = lab.x, C = lch.y
        var h = lch.z * 180 / .pi
        if h < 0 { h += 360 }
        if h >= 360 { h -= 360 }

        let mc = Self.maxChroma(L: min(max(L, 0), 1), hue: lch.z)
        let rel = mc > 1e-6 ? min(C / mc, 1) : 0
        let sat = C / max(L, 0.05)
        let chroma: Chroma = rel < 0.28 || sat < 0.07 ? .grayish : (rel >= 0.62 && sat >= 0.16 ? .vivid : .muted)

        if L < 0.2 || (L < 0.25 && chroma == .grayish) {
            self.init(family: .black, lightness: .veryDark, chroma: .grayish)
            return
        }
        if C < 0.02 || (C < 0.035 && rel < 0.12) {
            if L > 0.93 {
                self.init(family: .white, lightness: .pale, chroma: .grayish)
            } else {
                self.init(family: .gray, lightness: Self.band(.gray, L), chroma: .grayish)
            }
            return
        }
        if L > 0.95 && C < 0.03 {
            self.init(family: .white, lightness: .pale, chroma: .grayish)
            return
        }

        var family: Family
        if h >= 345 || h < 38 {
            let core = h >= 345 || h < 12
            let pink = (core && (L >= 0.72 || (L >= 0.6 && chroma != .vivid)))
                || (!core && chroma != .vivid && L >= 0.65 && (h < 25 || L >= 0.72))
            family = pink ? .pink : .red
        } else if h < 80 {
            family = .orange
        } else if h < 115 {
            family = .yellow
        } else if h < 175 {
            family = .green
        } else if h < 220 {
            family = .teal
        } else if h < 280 {
            family = .blue
        } else if h < 318 {
            family = .purple
        } else if L >= 0.72 && chroma != .vivid {
            family = .pink
        } else {
            family = chroma == .vivid || L >= 0.65 ? .magenta : .purple
        }

        if (family == .orange || family == .yellow) && L >= 0.72 && chroma != .vivid && sat < 0.1
            && h >= 45 && h < 110 {
            family = .beige
        } else if family == .orange && (L < 0.5 || (L < 0.65 && chroma != .vivid)) {
            family = .brown
        } else if family == .yellow && L < 0.72 {
            family = h < 90 ? .brown : .olive
        } else if family == .green && h < 135 && L < 0.72 {
            family = .olive
        }

        if family == .blue && L < 0.4 && chroma != .grayish {
            self.init(family: .navy, lightness: .dark, chroma: chroma)
            return
        }

        var lightness = Self.band(family, L)
        if family == .beige { lightness = max(lightness, .medium) }
        if family == .brown { lightness = min(lightness, .light) }
        if lightness == .pale && chroma == .vivid { lightness = .light }
        self.init(family: family, lightness: lightness, chroma: chroma)
    }

    /// The lightness modifier a name speaks: none for medium, and none for families that carry
    /// their lightness in the word itself (black, white, navy).
    public var spokenLightness: Lightness? {
        switch family {
        case .black, .white, .navy: return nil
        default: return lightness == .medium ? nil : lightness
        }
    }

    /// The chroma modifier a name speaks: none for neutral families or muted colors; "vivid" only
    /// where it reads naturally (not for dark or pale colors, nor brown and olive, which are
    /// never vivid in everyday English).
    public var spokenChroma: Chroma? {
        switch family {
        case .black, .white, .gray, .beige, .navy: return nil
        default: break
        }
        switch chroma {
        case .grayish: return .grayish
        case .muted: return nil
        case .vivid:
            guard family != .brown, family != .olive, lightness == .medium || lightness == .light else { return nil }
            return .vivid
        }
    }

    /// The English name, e.g. "very dark grayish blue".
    public var english: String {
        var words: [String] = []
        switch spokenLightness {
        case .veryDark: words.append("very dark")
        case .dark: words.append("dark")
        case .light: words.append("light")
        case .pale: words.append("pale")
        case .medium, nil: break
        }
        switch spokenChroma {
        case .grayish: words.append("grayish")
        case .vivid: words.append("vivid")
        case .muted, nil: break
        }
        words.append(family.rawValue)
        return words.joined(separator: " ")
    }

    /// The most chroma an sRGB color can have at this lightness and hue (radians).
    private static func maxChroma(L: Float, hue: Float) -> Float {
        let ca = cos(hue), sa = sin(hue)
        var lo: Float = 0, hi: Float = 0.5
        for _ in 0..<24 {
            let mid = (lo + hi) / 2
            let rgb = ColorScience.okLabToLinearSRGB(SIMD3(L, mid * ca, mid * sa))
            if rgb.min() < -1e-4 || rgb.max() > 1 + 1e-4 { hi = mid } else { lo = mid }
        }
        return lo
    }

    /// Lightness relative to the family's medium range: a darker band below it, very dark more
    /// than 0.15 below, light up to 0.1 above and pale beyond.
    private static func band(_ family: Family, _ L: Float) -> Lightness {
        let (lo, hi) = mediumRange(family)
        if L < lo - 0.15 { return .veryDark }
        if L < lo { return .dark }
        if L <= hi { return .medium }
        if L <= hi + 0.1 { return .light }
        return .pale
    }

    private static func mediumRange(_ family: Family) -> (Float, Float) {
        switch family {
        case .gray, .black, .white: return (0.45, 0.72)
        case .red: return (0.45, 0.70)
        case .orange: return (0.60, 0.82)
        case .brown: return (0.30, 0.58)
        case .beige: return (0.72, 0.88)
        case .yellow: return (0.76, 0.99)
        case .olive: return (0.38, 0.65)
        case .green: return (0.48, 0.80)
        case .teal: return (0.45, 0.75)
        case .blue, .navy: return (0.42, 0.68)
        case .purple: return (0.35, 0.62)
        case .magenta: return (0.45, 0.75)
        case .pink: return (0.65, 0.88)
        }
    }
}

extension ColorName: CustomStringConvertible {
    public var description: String { english }
}

extension PaletteColor {
    /// The palette color's structured name.
    public var colorName: ColorName { ColorName(oklab: oklab) }
}
