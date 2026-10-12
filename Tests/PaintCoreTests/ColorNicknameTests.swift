import Foundation
import Testing
@testable import PaintCore

@Suite("ColorNickname")
struct ColorNicknameTests {

    private func paint(_ lab: SIMD3<Float>) -> PaletteColor { PaletteColor(oklab: lab, space: .sRGB) }

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

    @Test func versionOneTableSHA256IsFrozen() throws {
        let table = ColorNickname.Vocabulary(version: 1).table
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: path) }
        try Data(table.utf8).write(to: path)
        // Use the host's SHA-256 utility so PaintCore keeps no crypto dependency.
        let process = Process()
        #if os(Linux)
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sha256sum")
        process.arguments = [path.path]
        #else
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shasum")
        process.arguments = ["-a", "256", path.path]
        #endif
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        let hash = String(decoding: output, as: UTF8.self).split(separator: " ").first
        #expect(hash == "1291d9a047a81feda50e76f7fe255c29b7ee32a1e78ebe45dfa259eb03620064")
    }

    @Test func vocabularyPassesTheLibraryOracle() {
        #expect(ColorNickname.currentVersion == 2)
        #expect(ColorNickname.Vocabulary(version: 1).problems().isEmpty)
    }

    @Test func tsvPreservesTableOrderAndAssignments() {
        let original = ColorNickname.Vocabulary(version: 1)
        let tsv = original.table.split(separator: "\n").map { line in
            String(line.prefix(6)) + "\t" + line.dropFirst(7)
        }.joined(separator: "\r\n") + "\r\n"
        let proposed = ColorNickname.Vocabulary(table: tsv)
        #expect(proposed.entries == original.entries)
        #expect(proposed.problems().isEmpty)
        for sample in ColorFixtures.samples {
            let palette = ColorFixtures.palette(of: sample)
            for seed in [1, 2, 0x5eed] as [UInt64] {
                #expect(ColorNickname.assign(palette, seed: seed, vocabulary: proposed)
                        == ColorNickname.assign(palette, seed: seed, version: 1))
            }
        }
    }

    @Test func unknownVersionsUseTheNewestKnownVocabulary() {
        let palette = ColorFixtures.palette(of: "parrots")
        #expect(ColorNickname.Vocabulary(version: Int.max).entries
                == ColorNickname.Vocabulary(version: ColorNickname.currentVersion).entries)
        #expect(ColorNickname.assign(palette, seed: 77, version: Int.max)
                == ColorNickname.assign(palette, seed: 77, version: ColorNickname.currentVersion))
    }

    @Test(arguments: [
        ("050507", "05050Z"), ("050507", "05050a"), ("050507 Void", "050507\t"),
        ("050507 Void", "050507Void"), ("050507 Void", "050507\tVoid\tExtra"),
    ])
    func malformedTablesAreReported(edit: (String, String)) {
        let table = ColorNickname.table.replacingOccurrences(of: edit.0, with: edit.1)
        let vocabulary = ColorNickname.Vocabulary(table: table)
        #expect(!vocabulary.problems().isEmpty)
        #expect(!vocabulary.formatProblems.isEmpty)
    }

    @Test(arguments: [
        ("Void", "Soot", "duplicate name"), ("050507", "0F0E0D", "duplicate anchor"),
        ("Void", "void", "Title Case"), ("Void", "A Long Name", "one or two words"),
        ("Void", "Extraordinarily Long", "at most 16 characters"),
        ("Void", "Vöid", "ASCII letters"), ("Void", "Void2", "ASCII letters"),
        ("Void", "Deep-Black-Sea", "at most one hyphen"), ("Void", "Blue", "a plain color word alone"),
        ("Void", "Skin", "uses “skin”"), ("Void", "Blue Fog", "is a black anchor"),
    ])
    func oracleRejectsStyleViolations(edit: (String, String, String)) {
        let table = ColorNickname.table.replacingOccurrences(of: edit.0, with: edit.1)
        let vocabulary = ColorNickname.Vocabulary(table: table)
        #expect(vocabulary.problems().contains { $0.contains(edit.2) })
    }

    @Test func oracleChecksWordCapsSizeAndGamut() {
        let small = ColorNickname.Vocabulary(table: (1...8).map {
            String(format: "%06X", $0) + "\tCommon Word"
        }.joined(separator: "\n"))
        let problems = small.problems()
        #expect(problems.contains { $0.contains("expected 480...640") })
        #expect(problems.contains { $0.contains("8 names start with Common") })
        #expect(problems.contains { $0.contains("8 names end with Word") })
        #expect(problems.contains { $0.hasPrefix("gamut:") })
        #expect(problems == small.problems())
    }

    @Test func proposedNamesAreActuallyUsed() {
        let proposed = ColorNickname.Vocabulary(table: "050507\tTest Anchor")
        let palette = [paint(ColorScience.okLab(hex: 0x050507))]
        #expect(ColorNickname.assign(palette, seed: 1, vocabulary: proposed) == ["Test Anchor"])
        #expect(ColorNickname.assign([], seed: 1, vocabulary: proposed).isEmpty)
        let empty = ColorNickname.Vocabulary(table: "")
        #expect(ColorNickname.assign(palette, seed: 1, vocabulary: empty) == [palette[0].colorName.englishTitle])
    }

    /// A typical photo palette finds names close by, not just within the discard radius.
    @Test func samplePalettesHaveNearbyAnchors() {
        for sample in ColorFixtures.samples {
            let palette = ColorFixtures.palette(of: sample)
            #expect(palette.count >= 23, "\(sample)")
            for color in palette {
                let nearest = ColorNickname.nearest(to: color.oklab)
                #expect(nearest.count >= ColorNickname.poolSize, "\(sample) \(color.oklab)")
                #expect((nearest.first?.distance ?? 1) < 0.07, "\(sample) \(color.oklab)")
            }
        }
    }

    // MARK: Assignment

    @Test func parrotsPaletteGetsDistinctNicknames() {
        let palette = ColorFixtures.palette(of: "parrots")
        #expect(palette.count == 24)
        let names = ColorNickname.assign(palette, seed: 0x5eed)
        // v1 is frozen per platform: native libm differences affect its modulo-based draw.
        // Keep Linux's pin here; the observed iOS pin lives in ArtworkNicknameTests.
        #if os(Linux)
        #expect(names == [
            "Dusty Coral", "Ember Glow", "Roof Tile", "Barn Roof", "Fire Brick", "Rosewood", "Rose Quartz", "Daffodil",
            "Ochre Wall", "Latte Foam", "Eucalyptus", "Bay Leaf", "Shale", "Wet Moss", "Moss Garden", "Swamp Reed",
            "Bog Myrtle", "Agave", "Dragonfly", "Marshmallow", "Galvanized Pail", "Driftwood", "Bog Oak", "Burnt Cork",
        ], "\(names)")
        #endif
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
        // 60 colors in one narrow, well populated region: fallbacks may repeat, nicknames never do.
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
        let palette = ColorFixtures.palette(of: "parrots")
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
        for sample in ColorFixtures.samples {
            for color in ColorFixtures.palette(of: sample) {
                let nearest = ColorNickname.nearest(to: color.oklab)
                for seed in 0..<40 as Range<UInt64> {
                    let name = ColorNickname.assign([color], seed: seed)[0]
                    let pick = nearest.first { ColorNickname.vocabulary[$0.index].name == name }
                    #expect(pick.map { $0.distance <= nearest[0].distance + ColorNickname.window } == true,
                            "\(sample) \(color.oklab): \(name)")
                }
            }
        }
        let warmGray = paint(ColorFixtures.lab("B5AFAF"))
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
