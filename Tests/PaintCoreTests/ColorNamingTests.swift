import Foundation
import Testing
@testable import PaintCore

@Suite("ColorNaming")
struct ColorNamingTests {

    private func lab(_ hex: String) -> SIMD3<Float> {
        let v = UInt32(hex, radix: 16)!
        let rgb = SIMD3(Float((v >> 16) & 0xFF), Float((v >> 8) & 0xFF), Float(v & 0xFF)) / 255
        return ColorScience.encodedToOKLab(rgb, space: .sRGB)
    }

    private func name(_ hex: String) -> String { ColorName(oklab: lab(hex)).english }

    /// Parses "<hex> <name…>" lines (optionally prefixed by a sample name).
    private func table(_ text: String, prefixed: Bool) -> [(sample: String, hex: String, name: String)] {
        text.split(separator: "\n").map { line in
            var words = line.split(separator: " ").map(String.init)
            let sample = prefixed ? words.removeFirst() : ""
            let hex = words.removeFirst()
            return (sample, hex, words.joined(separator: " "))
        }
    }

    @Test func knownColorsHaveExpectedNames() {
        for entry in table(Self.known, prefixed: false) {
            #expect(name(entry.hex) == entry.name, "#\(entry.hex)")
        }
    }

    @Test func bundledSamplePalettesGetSensibleNames() {
        let vocabulary: Set<String> = Set(["very", "dark", "light", "pale", "grayish", "vivid"])
            .union(ColorName.Family.allCases.map(\.rawValue))
        let entries = table(Self.samplePalettes, prefixed: true)
        #expect(entries.count == 142)
        #expect(Set(entries.map(\.sample)).count == 6)
        for entry in entries {
            let oklab = lab(entry.hex)
            let color = ColorName(oklab: oklab)
            let english = color.english
            #expect(english == entry.name, "\(entry.sample) #\(entry.hex)")

            let words = english.split(separator: " ", omittingEmptySubsequences: false)
            #expect((1...4).contains(words.count), "\(english)")
            #expect(words.allSatisfy { !$0.isEmpty && vocabulary.contains(String($0)) }, "\(english)")

            let lch = ColorScience.lch(oklab)
            var hue = lch.z * 180 / .pi
            if hue < 0 { hue += 360 }
            let inSector: Bool
            switch color.family {
            case .black, .white, .gray: inSector = color.family == .black || lch.y < 0.06
            case .red, .pink: inSector = hue >= 318 || hue < 45
            case .orange, .brown, .beige: inSector = hue >= 35 && hue < 115
            case .yellow, .olive: inSector = hue >= 75 && hue < 140
            case .green: inSector = hue >= 110 && hue < 180
            case .teal: inSector = hue >= 170 && hue < 225
            case .blue, .navy: inSector = hue >= 215 && hue < 285
            case .purple, .magenta: inSector = hue >= 275 && hue < 350
            }
            #expect(inSector, "\(entry.sample) #\(entry.hex) \(english) at \(hue)°, C \(lch.y)")
        }
    }

    @Test func syntheticPaletteNames() {
        // The app's `SyntheticTemplate.palette` (OKLCh) and the names it should get.
        let palette: [(Float, Float, Float, String)] = [
            (0.34, 0.09, 262, "navy"), (0.52, 0.13, 248, "vivid blue"), (0.79, 0.08, 232, "pale blue"),
            (0.88, 0.05, 20, "grayish pink"), (0.88, 0.07, 88, "beige"), (0.82, 0.15, 84, "vivid yellow"),
            (0.77, 0.13, 58, "vivid orange"), (0.68, 0.17, 32, "vivid red"), (0.50, 0.15, 30, "vivid red"),
            (0.63, 0.10, 190, "teal"), (0.74, 0.09, 142, "green"), (0.45, 0.10, 150, "dark green"),
            (0.44, 0.13, 330, "dark magenta"), (0.96, 0.02, 95, "white"),
        ]
        for (l, c, h, expected) in palette {
            let rad = h * .pi / 180
            #expect(ColorName(oklab: SIMD3(l, c * cos(rad), c * sin(rad))).english == expected, "L \(l) C \(c) h \(h)")
        }
    }

    @Test func grayRampIsMonotonic() {
        var previous = -1
        var families: [ColorName.Family] = []
        for v in 0...255 {
            let g = Float(v) / 255
            let color = ColorName(oklab: ColorScience.encodedToOKLab(SIMD3(repeating: g), space: .sRGB))
            families.append(color.family)
            let rank: Int
            switch color.family {
            case .black: rank = 0
            case .gray: rank = 1 + color.lightness.rawValue
            case .white: rank = 7
            default:
                Issue.record("gray \(v) named \(color.english)")
                continue
            }
            #expect(rank >= previous, "gray \(v) named \(color.english)")
            previous = rank
        }
        #expect(families.first == .black)
        #expect(families.last == .white)
    }

    @Test func namingIsDeterministicAndPure() {
        var rng = SplitMix64(seed: 3)
        let points = (0..<2000).map { _ in
            SIMD3(rng.nextFloat(), rng.nextFloat() * 0.6 - 0.3, rng.nextFloat() * 0.6 - 0.3)
        }
        let first = points.map { ColorName(oklab: $0) }
        let second = points.map { ColorName(oklab: $0) }
        #expect(first == second)

        let order = Array(points.indices).shuffled(using: &rng)
        let shuffled = order.map { ColorName(oklab: points[$0]) }
        #expect(shuffled == order.map { first[$0] })
    }

    @Test func nonFiniteInputIsGray() {
        #expect(ColorName(oklab: SIMD3(.nan, 0, 0)) == ColorName(family: .gray, lightness: .medium, chroma: .grayish))
        #expect(ColorName(oklab: SIMD3(0.5, .infinity, 0)).english == "gray")
    }

    @Test func spokenModifierRules() {
        let cases: [(ColorName.Family, ColorName.Lightness, ColorName.Chroma, String)] = [
            (.green, .medium, .muted, "green"),
            (.brown, .medium, .vivid, "brown"),
            (.red, .dark, .vivid, "dark red"),
            (.navy, .dark, .vivid, "navy"),
            (.gray, .light, .grayish, "light gray"),
            (.blue, .veryDark, .grayish, "very dark grayish blue"),
            (.teal, .light, .vivid, "light vivid teal"),
            (.black, .veryDark, .grayish, "black"),
        ]
        for (family, lightness, chroma, expected) in cases {
            let color = ColorName(family: family, lightness: lightness, chroma: chroma)
            #expect(color.english == expected)
            #expect(color.description == expected)
        }
    }

    @Test func paletteColorExposesItsName() {
        let oklab = lab("228b22")
        let color = PaletteColor(oklab: oklab, space: .displayP3)
        #expect(color.colorName == ColorName(oklab: oklab))
        #expect(color.colorName.english == "vivid green")
    }

    /// Named web colors ("<hex> <expected name>").
    private static let known = """
        ff0000 vivid red
        00ff00 light vivid green
        0000ff vivid blue
        ffff00 vivid yellow
        00ffff light vivid teal
        ff00ff vivid magenta
        ffa500 vivid orange
        800080 dark magenta
        008080 vivid teal
        808000 olive
        000080 navy
        800000 dark red
        8b4513 brown
        ffc0cb pink
        ff69b4 vivid pink
        808080 gray
        c0c0c0 light gray
        404040 dark gray
        ffffff white
        000000 black
        006400 dark green
        228b22 vivid green
        87ceeb pale blue
        4b0082 dark purple
        d2b48c beige
        e6e6fa pale grayish purple
        191970 navy
        2f4f4f dark teal
        556b2f olive
        f5deb3 light beige
        """

    /// The six bundled samples' 24-color palettes ("<sample> <hex> <expected name>"), from
    /// `pbn` at `--colors 24`; the names were reviewed by eye against the swatches.
    private static let samplePalettes = """
        barn f77b5c light vivid red
        barn c66148 vivid red
        barn 8e4f3f red
        barn f9b38b light orange
        barn 6d3e33 dark red
        barn 563128 dark red
        barn bca48b beige
        barn a88c76 orange
        barn 927763 light brown
        barn 736751 grayish brown
        barn 5f513d brown
        barn 453e2b dark olive
        barn 312419 dark brown
        barn fee3ad light beige
        barn cfb96d yellow
        barn b29f5f light olive
        barn 958856 olive
        barn 747846 olive
        barn 61693c olive
        barn 4e552f olive
        barn f9efe6 white
        barn c2b4b4 light gray
        barn 9d9aa1 gray
        barn 79797b gray
        espresso e4bb94 beige
        espresso d8a274 orange
        espresso e89339 vivid orange
        espresso c98857 orange
        espresso c97239 vivid orange
        espresso b26b3f dark orange
        espresso ba5a25 dark orange
        espresso 8c6040 brown
        espresso b73414 vivid red
        espresso a14e25 dark orange
        espresso a1260d vivid red
        espresso 8d3919 brown
        espresso 70442c brown
        espresso 731607 dark red
        espresso 572a18 brown
        espresso 4b0d05 very dark red
        espresso 2c0e06 very dark red
        espresso 1b0502 black
        espresso f1d8bc light beige
        espresso c8ae8e beige
        espresso bc9672 orange
        espresso a07a57 light brown
        espresso f7eee3 white
        hibiscus d9a78b beige
        hibiscus b7836d orange
        hibiscus b3605a red
        hibiscus c83c27 vivid red
        hibiscus 9e3a28 vivid red
        hibiscus 7f351d brown
        hibiscus 986b55 brown
        hibiscus e9cea6 beige
        hibiscus 68563f brown
        hibiscus 523e27 brown
        hibiscus a1a650 light olive
        hibiscus 888e47 olive
        hibiscus 747832 olive
        hibiscus 606424 olive
        hibiscus 51511c olive
        hibiscus afaa89 beige
        hibiscus 9b967b light grayish olive
        hibiscus 8a846e grayish olive
        hibiscus 717361 grayish olive
        hibiscus 413f14 dark olive
        hibiscus 352e12 dark olive
        hibiscus 566258 grayish green
        hibiscus 434b44 dark gray
        hibiscus 262218 very dark gray
        lighthouse 834638 red
        lighthouse 865d42 brown
        lighthouse fcfacd light beige
        lighthouse e1d7ae beige
        lighthouse c5bc9b beige
        lighthouse b9a57d beige
        lighthouse a49473 light brown
        lighthouse 908164 light brown
        lighthouse 7e6f4f brown
        lighthouse 6b5e42 brown
        lighthouse 604f3c brown
        lighthouse 525028 olive
        lighthouse 4d4031 brown
        lighthouse 3e3b1f dark olive
        lighthouse 6b8799 grayish blue
        lighthouse a4a695 light grayish olive
        lighthouse 869695 gray
        lighthouse 73766c gray
        lighthouse 596162 gray
        lighthouse 494f4e dark gray
        lighthouse 394042 dark gray
        lighthouse 3c3229 grayish brown
        lighthouse 2e261f very dark gray
        lighthouse 221915 black
        parrots d19195 pink
        parrots e34c40 vivid red
        parrots a75d55 red
        parrots bc3b33 vivid red
        parrots 91362e vivid red
        parrots 6b3129 dark red
        parrots e2c6c9 grayish pink
        parrots eebd0e vivid yellow
        parrots b59b22 light olive
        parrots ceccb1 beige
        parrots a0ab7e green
        parrots 706953 grayish olive
        parrots 575848 grayish olive
        parrots 779354 olive
        parrots 5c8430 olive
        parrots 5d713c olive
        parrots 45582a olive
        parrots 689c9e teal
        parrots 4c7b82 teal
        parrots f3eae7 white
        parrots b6afaf light gray
        parrots 928f86 gray
        parrots 403e33 dark gray
        parrots 2e2a26 very dark gray
        regatta b8768c dark pink
        regatta 80536d purple
        regatta ab4d3e red
        regatta 853d35 red
        regatta 62262e dark red
        regatta d9a1a9 pink
        regatta 5b4639 brown
        regatta 775a20 brown
        regatta d9cf7f yellow
        regatta c0af46 dark yellow
        regatta a99b44 light olive
        regatta 897d3a olive
        regatta e6e9ce grayish yellow
        regatta cccfb8 grayish yellow
        regatta 243255 navy
        regatta b5b8a7 grayish green
        regatta 949c92 gray
        regatta 7f8782 gray
        regatta 6c7573 gray
        regatta 5a6262 gray
        regatta 424d56 dark grayish blue
        regatta 39393a dark gray
        regatta 251d21 black
        """
}
