import Foundation
import Testing
@testable import PaintCore

@Suite("ColorNickname")
struct ColorNicknameTests {

    private func lab(_ hex: String) -> SIMD3<Float> {
        let v = UInt32(hex, radix: 16)!
        let rgb = SIMD3(Float((v >> 16) & 0xFF), Float((v >> 8) & 0xFF), Float(v & 0xFF)) / 255
        return ColorScience.encodedToOKLab(rgb, space: .sRGB)
    }

    private func paint(_ lab: SIMD3<Float>) -> PaletteColor { PaletteColor(oklab: lab, space: .sRGB) }

    /// The bundled samples in `ColorNamingTests.samplePalettes`.
    private static let samples = ["barn", "espresso", "hibiscus", "lighthouse", "parrots", "regatta"]

    /// The bundled samples' palettes (`ColorNamingTests`), by sample name.
    private func samplePalette(_ sample: String) -> [PaletteColor] {
        ColorNamingTests.samplePalettes.split(separator: "\n").compactMap { line in
            let words = line.split(separator: " ")
            return words[0] == sample ? paint(lab(String(words[1]))) : nil
        }
    }

    /// A deterministic palette of `count` in-gamut colors at least 0.04 apart.
    private func spreadPalette(count: Int, seed: UInt64) -> [PaletteColor] {
        var rng = SplitMix64(seed: seed)
        var colors: [SIMD3<Float>] = []
        while colors.count < count {
            let candidate = SIMD3(rng.nextFloat(), rng.nextFloat() * 0.5 - 0.24, rng.nextFloat() * 0.5 - 0.3)
            guard Self.inGamut(candidate), colors.allSatisfy({ ColorScience.distance($0, candidate) >= 0.04 }) else { continue }
            colors.append(candidate)
        }
        return colors.map(paint)
    }

    private static func inGamut(_ lab: SIMD3<Float>) -> Bool {
        let rgb = ColorScience.okLabToLinearSRGB(lab)
        return rgb.min() >= -1e-7 && rgb.max() <= 1 + 1e-6
    }

    // MARK: Vocabulary

    @Test func vocabularySizeAndFormat() {
        let vocabulary = ColorNickname.vocabulary
        #expect((480...640).contains(vocabulary.count), "\(vocabulary.count) entries")
        #expect(ColorNickname.table.split(separator: "\n").count == vocabulary.count)
        for line in ColorNickname.table.split(separator: "\n") {
            #expect(line.count > 7 && line.dropFirst(6).first == " ", "\(line)")
            #expect(line.prefix(6).allSatisfy(\.isHexDigit) && line.prefix(6).uppercased() == line.prefix(6), "\(line)")
        }
        #expect(Set(vocabulary.map(\.name)).count == vocabulary.count, "names are unique")
        #expect(Set(vocabulary.map(\.hex)).count == vocabulary.count, "anchors are unique")
    }

    @Test func namesFollowTheStyleGuide() {
        let color: Set<String> = ["red", "orange", "yellow", "green", "blue", "purple", "pink", "brown", "gray", "grey",
                                  "black", "white", "beige", "olive", "teal", "navy", "magenta", "violet", "indigo",
                                  "lime", "aqua", "turquoise", "tan", "cyan", "maroon", "mauve", "crimson", "scarlet",
                                  "lavender", "lilac", "coral", "peach", "cream", "ivory", "gold", "silver", "bronze",
                                  "khaki", "fuchsia", "amber", "rose", "plum", "mint", "sage", "rust", "sand"]
        var leading: [String: Int] = [:]
        var trailing: [String: Int] = [:]
        for entry in ColorNickname.vocabulary {
            let name = entry.name
            let words = name.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
            #expect((1...2).contains(words.count), "\(name): one or two words")
            #expect(name.count <= 16, "\(name): at most 16 characters")
            #expect(name.unicodeScalars.allSatisfy { $0.isASCII && ($0.properties.isAlphabetic || $0 == " " || $0 == "-") },
                    "\(name): ASCII letters, spaces and a hyphen only")
            #expect(name.filter { $0 == "-" }.count <= 1, "\(name): at most one hyphen")
            for word in words {
                #expect(word.first?.isUppercase == true && word.dropFirst().allSatisfy { $0.isLowercase || $0 == "-" },
                        "\(name): Title Case")
            }
            if words.count == 1 {
                #expect(!color.contains(name.lowercased()), "\(name): a plain color word alone")
            } else {
                leading[words[0], default: 0] += 1
                trailing[words[1], default: 0] += 1
            }
        }
        for (word, count) in leading { #expect(count <= 4, "\(count) names start with \(word)") }
        for (word, count) in trailing { #expect(count <= 6, "\(count) names end with \(word)") }
    }

    @Test func namesAvoidWhatTheStyleGuideForbids() {
        let forbidden: Set<String> = [
            // skin tones and body parts
            "skin", "flesh", "nude", "tan", "blush", "ivory", "ebony", "porcelain", "fair", "bone", "cheek", "lip", "lips",
            "hair", "blood", "heart", "eye", "eyes", "tooth", "teeth", "nail", "finger", "hand", "tongue", "vein", "bruise",
            "breast", "comb", "foot", "face", "head", "belly", "bile", "scab", "rash", "vomit", "mucus",
            // brands and people
            "cola", "coke", "pepsi", "tiffany", "crayola", "sharpie", "lego", "kleenex", "popsicle", "creamsicle", "tabasco",
            "nutella", "oreo", "starbucks", "pantone", "persian", "indian", "prussian", "sienna", "titian",
            // religion, politics, medicine
            "angel", "heaven", "saint", "monk", "pope", "cathedral", "church", "temple", "altar", "holy", "sacred", "easter",
            "christmas", "cardinal", "royal", "liberty", "republic", "rebel", "revolution", "pill", "aspirin", "bandage",
            "surgical", "hospital", "iodine", "calamine", "antiseptic", "tobacco", "nicotine",
            // superlatives
            "best", "perfect", "ultimate", "supreme", "greatest", "brightest", "darkest", "finest", "purest", "ultra",
            "super", "mega", "most", "utmost",
        ]
        for entry in ColorNickname.vocabulary {
            for word in entry.name.lowercased().split(whereSeparator: { $0 == " " || $0 == "-" }) {
                #expect(!forbidden.contains(String(word)), "\(entry.name) uses “\(word)”")
            }
        }
    }

    /// A name that contains a basic color word must be the color: "Teal Lagoon" is teal.
    @Test func colorWordsInNamesMatchTheAnchor() {
        let families: [String: Set<ColorName.Family>] = [
            "red": [.red], "orange": [.orange], "yellow": [.yellow], "green": [.green, .olive], "blue": [.blue, .navy],
            "purple": [.purple], "pink": [.pink], "brown": [.brown], "gray": [.gray], "grey": [.gray],
            "black": [.black], "white": [.white], "beige": [.beige], "olive": [.olive, .green], "teal": [.teal],
            "navy": [.navy], "magenta": [.magenta, .purple, .pink],
        ]
        for entry in ColorNickname.vocabulary {
            let family = ColorName(oklab: entry.oklab).family
            for word in entry.name.lowercased().split(whereSeparator: { $0 == " " || $0 == "-" }) {
                if let allowed = families[String(word)] {
                    #expect(allowed.contains(family), "\(entry.name) is a \(family) anchor (#\(String(entry.hex, radix: 16)))")
                }
            }
        }
    }

    /// Every in-gamut color the pipeline can produce has at least five anchors within ΔE 0.10.
    @Test func vocabularyCoversTheGamut() {
        let anchors = ColorNickname.vocabulary.map(\.oklab)
        let steps = 24
        func value(_ i: Int, _ low: Float, _ high: Float) -> Float { low + (high - low) * Float(i) / Float(steps - 1) }
        var samples = 0
        var worst = Int.max
        var failures: [String] = []
        for l in 0..<steps {
            for a in 0..<steps {
                for b in 0..<steps {
                    let point = SIMD3(value(l, 0, 1), value(a, -0.24, 0.285), value(b, -0.32, 0.21))
                    guard Self.inGamut(point) else { continue }
                    samples += 1
                    let near = anchors.reduce(0) { $0 + (ColorScience.distance($1, point) <= 0.10 ? 1 : 0) }
                    worst = min(worst, near)
                    if near < 5 && failures.count < 8 { failures.append("\(point) has \(near)") }
                }
            }
        }
        #expect(samples > 2000)
        #expect(worst >= 5, "\(failures)")
    }

    /// A typical photo palette finds names close by, not just within the discard radius.
    @Test func samplePalettesHaveNearbyAnchors() {
        for sample in Self.samples {
            let palette = samplePalette(sample)
            #expect(palette.count >= 23, "\(sample)")
            for color in palette {
                let nearest = ColorNickname.nearest(to: color.oklab)
                #expect(nearest.count >= ColorNickname.poolSize, "\(sample) \(color.oklab)")
                #expect((nearest.first?.distance ?? 1) < 0.07, "\(sample) \(color.oklab)")
            }
        }
    }

    // MARK: Assignment

    @Test func parrotsPaletteGetsDistinctApposites() {
        let palette = samplePalette("parrots")
        #expect(palette.count == 24)
        let names = ColorNickname.assign(palette, seed: 0x5eed)
        #expect(Set(names).count == names.count)
        #expect(names.allSatisfy(ColorNickname.isNickname))
        // Every pick is one of the paint's own near anchors.
        for (color, name) in zip(palette, names) {
            let entry = ColorNickname.vocabulary.first { $0.name == name }!
            #expect(ColorScience.distance(entry.oklab, color.oklab) <= ColorNickname.maximumDistance)
        }
    }

    @Test func namesAreUniqueWithin150Colors() {
        for seed in [1, 2, 3] as [UInt64] {
            let names = ColorNickname.assign(spreadPalette(count: 150, seed: seed), seed: seed)
            #expect(Set(names).count == 150, "seed \(seed)")
            #expect(names.allSatisfy(ColorNickname.isNickname), "seed \(seed)")
        }
    }

    @Test func crowdedPalettesStayUniqueWhereAnchorsAllow() {
        // 150 colors in one narrow, well populated region: fallbacks may repeat, nicknames never do.
        var rng = SplitMix64(seed: 9)
        var colors: [SIMD3<Float>] = []
        while colors.count < 60 {
            let candidate = SIMD3(0.45 + rng.nextFloat() * 0.35, -0.12 + rng.nextFloat() * 0.1, 0.05 + rng.nextFloat() * 0.1)
            guard Self.inGamut(candidate), colors.allSatisfy({ ColorScience.distance($0, candidate) >= 0.02 }) else { continue }
            colors.append(candidate)
        }
        let names = ColorNickname.assign(colors.map(paint), seed: 4)
        let nicknames = names.filter(ColorNickname.isNickname)
        #expect(Set(nicknames).count == nicknames.count)
        #expect(names.allSatisfy { !$0.isEmpty })
    }

    @Test func assignmentIsDeterministic() {
        let palette = spreadPalette(count: 40, seed: 5)
        #expect(ColorNickname.assign(palette, seed: 77) == ColorNickname.assign(palette, seed: 77))
        #expect(ColorNickname.assign([], seed: 1).isEmpty)
    }

    @Test func differentSeedsGiveDifferentNames() {
        let palette = samplePalette("parrots")
        let a = ColorNickname.assign(palette, seed: 1)
        let b = ColorNickname.assign(palette, seed: 2)
        let differing = zip(a, b).filter { $0 != $1 }.count
        #expect(Double(differing) >= 0.3 * Double(palette.count), "\(differing) of \(palette.count) differ")
    }

    @Test func farOrNonFinitePaintsFallBackToTheStructuredName() {
        let far = SIMD3<Float>(0.5, 0.6, 0.6)
        let names = ColorNickname.assign([paint(far), paint(SIMD3(.nan, 0, 0)), paint(SIMD3(0.5, 0, 0))], seed: 3)
        #expect(names[0] == ColorName(oklab: far).englishTitle)
        #expect(names[1] == "Gray")
        #expect(!ColorNickname.isNickname(names[0]))
        #expect(names.allSatisfy { !$0.isEmpty })
    }

    @Test func englishTitleCapitalizesOnlyTheFirstLetter() {
        #expect(ColorName(family: .green, lightness: .dark, chroma: .grayish).englishTitle == "Dark grayish green")
        #expect(ColorName(family: .navy, lightness: .dark, chroma: .vivid).englishTitle == "Navy")
    }

    /// A paint right on an anchor with few close neighbours takes that anchor's name about half the
    /// time or more, and the other draws still vary.
    @Test func theNearestAnchorWinsMostOften() throws {
        /// Chance of the paint's own anchor being drawn: the less its neighbours weigh, the higher.
        func chance(_ entry: ColorNickname.Entry) -> Float {
            let others = ColorNickname.nearest(to: entry.oklab).prefix(ColorNickname.poolSize).dropFirst()
                .filter { $0.distance <= ColorNickname.window }
            return 1 / (1 + others.reduce(0) { $0 + exp(-$1.distance / ColorNickname.falloff) })
        }
        let anchor = try #require(ColorNickname.vocabulary.filter { chance($0) < 1 }.max { chance($0) < chance($1) })
        let palette = [PaletteColor(oklab: anchor.oklab, space: .sRGB)]
        var wins = 0
        for seed in 0..<1000 where ColorNickname.assign(palette, seed: UInt64(seed)) == [anchor.name] { wins += 1 }
        #expect(wins >= 500, "\(anchor.name) won \(wins) of 1000")
        #expect(wins < 1000)
    }

    /// The draw stays within `window` of the nearest anchor (one paint per palette, so no name is
    /// taken): a warm gray is never called "Morning Lake", a blue-gray 0.03 away, yet still varies.
    @Test func drawsStayCloseToTheNearestAnchor() {
        for sample in Self.samples {
            for color in samplePalette(sample) {
                let nearest = ColorNickname.nearest(to: color.oklab)
                for seed in 0..<40 as Range<UInt64> {
                    let name = ColorNickname.assign([color], seed: seed)[0]
                    let pick = nearest.first { ColorNickname.vocabulary[$0.index].name == name }
                    #expect(pick.map { $0.distance <= nearest[0].distance + ColorNickname.window } == true,
                            "\(sample) \(color.oklab): \(name)")
                }
            }
        }
        let warmGray = paint(lab("B5AFAF"))
        let names = Set((0..<300 as Range<UInt64>).map { ColorNickname.assign([warmGray], seed: $0)[0] })
        #expect(!names.contains("Morning Lake"))
        #expect(names.count >= 2, "\(names)")
    }

    @Test func seedFoldsAUUIDStably() throws {
        let id = try #require(UUID(uuidString: "00112233-4455-6677-8899-AABBCCDDEEFF"))
        let expected: UInt64 = 0x0011_2233_4455_6677 ^ 0x8899_AABB_CCDD_EEFF
        #expect(ColorNickname.seed(for: id) == expected)
        #expect(ColorNickname.seed(for: id) == ColorNickname.seed(for: id))
        #expect(ColorNickname.seed(for: UUID()) != ColorNickname.seed(for: UUID()))
    }
}
