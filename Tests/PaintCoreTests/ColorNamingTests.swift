import Foundation
import Testing
@testable import PaintCore

@Suite("ColorNaming")
struct ColorNamingTests {

    private func name(_ hex: String) -> String { ColorName(oklab: ColorFixtures.lab(hex)).english }

    /// Parses "<hex> <name…>" lines.
    private func table(_ text: String) -> [(hex: String, name: String)] {
        text.split(separator: "\n").map { line in
            var words = line.split(separator: " ").map(String.init)
            let hex = words.removeFirst()
            return (hex, words.joined(separator: " "))
        }
    }

    @Test func knownColorsHaveExpectedNames() {
        for entry in table(Self.known) {
            #expect(name(entry.hex) == entry.name, "#\(entry.hex)")
        }
    }

    @Test func samplePalettesGetSensibleNames() {
        let vocabulary: Set<String> = Set(["very", "dark", "light", "pale", "grayish", "vivid"])
            .union(ColorName.Family.allCases.map(\.rawValue))
        let entries = ColorFixtures.swatches
        #expect(entries.count == 142)
        #expect(ColorFixtures.samples.count == 6)
        for entry in entries {
            let oklab = ColorFixtures.lab(entry.hex)
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

    @Test func englishTitleCapitalizesOnlyTheFirstLetter() {
        #expect(ColorName(family: .green, lightness: .dark, chroma: .grayish).englishTitle == "Dark grayish green")
        #expect(ColorName(family: .navy, lightness: .dark, chroma: .vivid).englishTitle == "Navy")
    }

    @Test func paletteColorExposesItsName() {
        let oklab = ColorFixtures.lab("228b22")
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
}
