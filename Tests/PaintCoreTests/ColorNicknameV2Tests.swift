import Foundation
import Testing
@testable import PaintCore

@Suite("ColorNickname v2")
struct ColorNicknameV2Tests {
    private struct Pin: Decodable {
        let name: String
        let seed: UInt64
        let hexes: [UInt32]?
        let labBits: [[UInt32]]
        let names: [String]
    }

    @Test func sharedPlatformPins() throws {
        let pins = try JSONDecoder().decode([Pin].self, from: TestFixtures.data("nickname-v2.json"))
        #expect(pins.count == 2)
        for pin in pins {
            let palette = pin.labBits.map { bits in
                PaletteColor(oklab: SIMD3(Float(bitPattern: bits[0]), Float(bitPattern: bits[1]), Float(bitPattern: bits[2])), rgb: .zero)
            }
            #expect(ColorNickname.assign(palette, seed: pin.seed, version: 2) == pin.names, "\(pin.name)")
            #expect(ColorNickname.assign(palette, seed: pin.seed, version: Int.max) == pin.names)
            if let hexes = pin.hexes {
                let reconstructed = hexes.map { PaletteColor(oklab: ColorScience.okLab(hex: $0), space: .sRGB) }
                #expect(ColorNickname.assign(reconstructed, seed: pin.seed, version: 2) == pin.names)
            }
        }
    }

    @Test func canonicalAnchorsAreFrozenAndMatchTheOriginalTable() {
        let original = ColorNickname.Vocabulary(version: 1)
        let v2 = ColorNickname.Vocabulary(version: 2)
        #expect(original.table == v2.table)
        #expect(v2.entries.count == ColorNicknameV2.anchors.count)
        var hash: UInt64 = 14695981039346656037
        for (index, pair) in zip(original.entries, v2.entries).enumerated() {
            let (old, new) = pair
            #expect(old.hex == new.hex && old.name == new.name)
            let anchor = ColorNicknameV2.anchors[index]
            #expect(ColorNicknameV2.point(new.oklab) == anchor)
            // Check provenance on either libm without allowing it to regenerate the constants.
            // Half a Q16 step plus 1e-6 allows the measured native cbrtf/Float differences.
            #expect(abs(old.oklab.x - new.oklab.x) <= 0.000009)
            #expect(abs(old.oklab.y - new.oklab.y) <= 0.000009)
            #expect(abs(old.oklab.z - new.oklab.z) <= 0.000009)
            for value in [anchor.x, anchor.y, anchor.z] {
                let bits = UInt64(bitPattern: value)
                for shift in stride(from: 0, to: 64, by: 8) {
                    hash = (hash ^ ((bits >> shift) & 255)) &* 1099511628211
                }
            }
        }
        #expect(hash == 0xf639628048fa6e25)
        #expect(v2.problems().isEmpty)
    }

    @Test func binary32QuantizationHasSpecifiedEdges() {
        let unit: Float = 1 / 65536
        #expect(ColorNicknameV2.coordinate(0) == 0)
        #expect(ColorNicknameV2.coordinate(-0.0) == 0)
        #expect(ColorNicknameV2.coordinate(Float.leastNonzeroMagnitude) == 0)
        #expect(ColorNicknameV2.coordinate((unit / 2).nextDown) == 0)
        #expect(ColorNicknameV2.coordinate(unit / 2) == 1)
        #expect(ColorNicknameV2.coordinate(-unit / 2) == -1)
        #expect(ColorNicknameV2.coordinate(1 + unit / 2) == 65537)
        #expect(ColorNicknameV2.coordinate(-1 - unit / 2) == -65537)
        #expect(ColorNicknameV2.coordinate(Float.greatestFiniteMagnitude) == 524288)
        #expect(ColorNicknameV2.coordinate(-Float.greatestFiniteMagnitude) == -524288)
        #expect(ColorNicknameV2.coordinate(.infinity) == nil)
        #expect(ColorNicknameV2.coordinate(-.infinity) == nil)
        #expect(ColorNicknameV2.coordinate(.nan) == nil)
    }

    @Test func integerDistanceWeightAndMappingBoundaries() {
        // These two anchors are exactly equidistant; table order breaks the tie.
        let tied = ColorNicknameV2.nearest(to: SIMD3(11702, 1175, -2676))
        #expect(tied[21].index == 0 && tied[22].index == 446)
        let first = ColorNicknameV2.anchors[0]
        #expect(ColorNicknameV2.nearest(to: SIMD3(first.x - 7864, first.y, first.z)).contains { $0.index == 0 })
        #expect(!ColorNicknameV2.nearest(to: SIMD3(first.x - 7865, first.y, first.z)).contains { $0.index == 0 })
        for n: Int64 in [0, 1, 2, 3, 4, 25, 26, 7864 * 7864, 3 * 1048576 * 1048576] {
            let r = ColorNicknameV2.squareRoot(n)
            #expect(r * r <= n && (r + 1) * (r + 1) > n)
        }
        #expect(ColorNicknameV2.weight(distance: 0) == 1 << 24)
        var previous = ColorNicknameV2.weight(distance: 0)
        for d in 1...ColorNicknameV2.radius {
            let weight = ColorNicknameV2.weight(distance: d)
            #expect(weight > 0 && weight <= previous)
            previous = weight
        }
        for total: UInt64 in [1, 2, 3, 2116773, 6 << 24] {
            #expect(ColorNicknameV2.ticket(word: 0, total: total) == 0)
            #expect(ColorNicknameV2.ticket(word: .max, total: total) == total - 1)
            #expect(ColorNicknameV2.ticket(word: 1 << 63, total: total) == total / 2)
        }
        // A one-unit total change can move a multiply-high ticket by at most one.
        #expect(ColorNicknameV2.ticket(word: 13708834885075422956, total: 2116774)
                - ColorNicknameV2.ticket(word: 13708834885075422956, total: 2116773) <= 1)
    }

    @Test func drawStaysNearAndUniqueWithVariedSeeds() {
        let entries = ColorNickname.Vocabulary(version: 2).entries
        for sample in ColorFixtures.samples {
            let palette = ColorFixtures.palette(of: sample)
            let names = ColorNickname.assign(palette, seed: 0x5eed, version: 2)
            #expect(Set(names).count == names.count)
            #expect(names.allSatisfy(ColorNickname.isNickname))
            for color in palette {
                let candidates = ColorNicknameV2.nearest(to: ColorNicknameV2.point(color.oklab)!)
                let allowed = candidates.prefix(6).filter { $0.distance <= candidates[0].distance + ColorNicknameV2.window }
                for seed: UInt64 in 0..<40 {
                    let pick = ColorNickname.assign([color], seed: seed, version: 2)[0]
                    #expect(allowed.contains { entries[$0.index].name == pick })
                }
            }
            let other = ColorNickname.assign(palette, seed: 2, version: 2)
            #expect(zip(names, other).filter { $0 != $1 }.count >= palette.count / 3)
        }
    }

    @Test func fallbackIsIntegerAndHandlesExhaustionAndExtremeInputs() {
        // Check all reviewed structured names using v2's independent fixed-point classifier.
        for swatch in ColorFixtures.swatches {
            let point = ColorNicknameV2.point(ColorFixtures.lab(swatch.hex))!
            #expect(ColorNicknameV2.fallback(point).english == swatch.name, "\(swatch.sample) \(swatch.hex)")
        }
        func paint(_ lab: SIMD3<Float>) -> PaletteColor { PaletteColor(oklab: lab, rgb: .zero) }
        let extreme: [SIMD3<Float>] = [SIMD3(.nan, 0, 0), SIMD3(0, .infinity, 0),
            SIMD3(-.greatestFiniteMagnitude, 0, 0), SIMD3(.greatestFiniteMagnitude, 0, 0), SIMD3(0.5, 0.6, 0.6)]
        #expect(ColorNickname.assign(extreme.map(paint), seed: 1, version: 2) == ["Gray", "Gray", "Black", "White", "Dark orange"])
        let repeated = Array(repeating: paint(SIMD3(0.5, 0, 0)), count: 30)
        let names = ColorNickname.assign(repeated, seed: 1, version: 2)
        #expect(names.suffix(6).allSatisfy { $0 == "Gray" })
        let nicknames = names.filter(ColorNickname.isNickname)
        #expect(nicknames.count == 24 && Set(nicknames).count == 24)
        #expect(ColorNickname.assign([], seed: 1, version: 2).isEmpty)
    }
}
