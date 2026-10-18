import CoreGraphics
import Foundation
import PaintCore
import PDFKit
import Testing
@testable import PaintByNumber

@MainActor
struct ArtworkNicknameTests {
    let root = Fixtures.temporaryDirectory()

    private func makeLibrary() -> Library { Library(store: ArtworkStore(root: root)) }

    private func draft() -> ArtworkDraft {
        ArtworkDraft(title: "Stripes", template: Fixtures.stripes(), settings: Artwork.settingsBeforeLineArt)
    }

    private func fields(at url: URL) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    @Test func newArtworkRecordsTheCurrentVocabulary() async throws {
        let library = makeLibrary()
        let artwork = try await library.create(draft())
        #expect(ColorNickname.currentVersion == 2)
        #expect(artwork.nicknameVersion == ColorNickname.currentVersion)
        let meta = library.store.url(.meta, of: artwork.id)
        #expect(try fields(at: meta)["nicknameVersion"] as? Int == ColorNickname.currentVersion)
        #expect(makeLibrary().artwork(with: artwork.id)?.nicknameVersion == ColorNickname.currentVersion)
        #expect(artwork.format == Artwork.currentFormat)
    }

    @Test func oldMetaStaysUntouchedUntilSaved() async throws {
        let library = makeLibrary()
        let artwork = try await library.create(draft())
        let meta = library.store.url(.meta, of: artwork.id)
        var oldFields = try fields(at: meta)
        #expect(oldFields.removeValue(forKey: "nicknameVersion") != nil)
        let oldData = try JSONSerialization.data(withJSONObject: oldFields)
        try oldData.write(to: meta)

        let reloaded = makeLibrary()
        #expect(reloaded.artwork(with: artwork.id)?.nicknameVersion == 1)
        #expect(try reloaded.store.readMeta(artwork.id).nicknameVersion == 1)
        _ = try await reloaded.loadForPainting(artwork.id)
        await reloaded.flush()
        #expect(try Data(contentsOf: meta) == oldData, "Listing and opening must not migrate meta.json")
        #expect(try fields(at: meta)["nicknameVersion"] == nil)

        reloaded.rename(artwork.id, to: "Saved by this build")
        await reloaded.flush()
        #expect(try fields(at: meta)["nicknameVersion"] as? Int == 1)
        #expect(try reloaded.store.readMeta(artwork.id).nicknameVersion == 1)
    }

    /// Both normal and newer-format metadata use v1 for a missing or unreadable value.
    @Test(arguments: ["", "null", "\"future\"", "true", "[]", "{}", "1.5", "1e100"])
    func unreadableVersionsUseOne(value: String) throws {
        let nicknameField = value.isEmpty ? "" : #", "nicknameVersion":\#(value)"#
        for format in [Artwork.currentFormat, Artwork.currentFormat + 1] {
            let json = #"{"id":"\#(UUID().uuidString)","width":10,"height":20,"regionCount":5,"format":\#(format)\#(nicknameField)}"#
            let artwork = try JSONDecoder().decode(Artwork.self, from: Data(json.utf8))
            #expect(artwork.nicknameVersion == 1)
            #expect(artwork.needsNewerApp == (format > Artwork.currentFormat))
        }
    }

    @Test func futureVocabularyRoundTripsWithoutResolvingTheStoredValue() async throws {
        let library = makeLibrary()
        var artwork = try await library.create(draft())
        artwork.nicknameVersion = Int.max
        try library.store.writeMeta(artwork)
        let reloaded = makeLibrary()
        #expect(reloaded.artwork(with: artwork.id)?.nicknameVersion == Int.max)
        reloaded.rename(artwork.id, to: "Still a future vocabulary")
        await reloaded.flush()
        #expect(try reloaded.store.readMeta(artwork.id).nicknameVersion == Int.max)
        #expect(try fields(at: library.store.url(.meta, of: artwork.id))["nicknameVersion"] as? Int == Int.max)

        let palette = Fixtures.stripes().palette
        #expect(ColorNameText.nicknames(for: palette, seed: 7, version: Int.max, languageCode: "en")
                == ColorNameText.nicknames(for: palette, seed: 7, version: ColorNickname.currentVersion, languageCode: "en"))

        // Even the tolerant, read-only decoder keeps a newer app's vocabulary verbatim.
        artwork.format = Artwork.currentFormat + 1
        let future = try JSONDecoder().decode(Artwork.self, from: JSONEncoder().encode(artwork))
        #expect(future.nicknameVersion == Int.max && future.needsNewerApp)
    }

    @Test(arguments: [1, 2, Int.max])
    func regenerationKeepsTheRecordedVocabulary(version: Int) async throws {
        let library = makeLibrary()
        var item = draft()
        let photo = try #require(TemplateRasterizer.image(item.template, style: .painting, maxPixelSize: 300))
        item.photo = photo
        var artwork = try await library.create(item)
        artwork.nicknameVersion = version
        try library.store.writeMeta(artwork)
        let reloaded = makeLibrary()
        _ = try await reloaded.regenerate(
            artwork: artwork.id, settings: GenerationSettings(colorCount: 6, detail: 0, lineArt: LineArtSettings(style: .classic)))
        #expect(reloaded.artwork(with: artwork.id)?.nicknameVersion == version)
        #expect(try reloaded.store.readMeta(artwork.id).nicknameVersion == version)
    }

    @Test(arguments: [1, 2, Int.max])
    func sessionsAndPrintableKeyUseTheArtworkVocabulary(version: Int) async throws {
        let library = makeLibrary()
        var artwork = try await library.create(draft())
        artwork.nicknameVersion = version
        try library.store.writeMeta(artwork)
        let template = try library.store.readTemplate(artwork.id)
        let seed = ColorNickname.seed(for: artwork.id)
        let fresh = PaintingSession(template: template, nicknameSeed: seed, nicknameVersion: artwork.nicknameVersion)
        let resumed = try PaintingSession(
            template: template, progress: PaintProgress(regionCount: template.regions.count),
            nicknameSeed: seed, nicknameVersion: artwork.nicknameVersion)
        let expected = ColorNickname.assign(template.palette, seed: seed, version: version)
        #expect(fresh.nicknameVersion == version && resumed.nicknameVersion == version)
        #expect(fresh.colorNicknames == expected.map { Optional($0) })
        #expect(resumed.colorNicknames == fresh.colorNicknames)
        #expect(template.palette.indices.map { resumed.nickname(of: $0) } == fresh.colorNicknames)
        let data = try ArtworkExporter.templatePDF(store: library.store, artwork: artwork, paper: .a4)
        let key = try #require(PDFDocument(data: data)?.page(at: 1)?.string)
        for name in expected { #expect(key.contains(name), "Missing nickname: \(name)") }
    }

    @Test func versionOneAppleNamesAreFrozen() {
        // Apple's observed v1 names (iPad CI, iOS 26.5, test-results.json accompanying app-test.log).
        // Guards saved paintings against a libm change in a future iOS. pbn on Linux differs
        // for v1; its separate pins remain in ColorNicknameTests. Only v2 promises agreement.
        let hexes: [UInt32] = [
            0xD19195, 0xE34C40, 0xA75D55, 0xBC3B33, 0x91362E, 0x6B3129, 0xE2C6C9, 0xEEBD0E,
            0xB59B22, 0xCECCB1, 0xA0AB7E, 0x706953, 0x575848, 0x779354, 0x5C8430, 0x5D713C,
            0x45582A, 0x689C9E, 0x4C7B82, 0xF3EAE7, 0xB6AFAF, 0x928F86, 0x403E33, 0x2E2A26,
        ]
        let palette = hexes.map { hex in
            let rgb = SIMD3(Float((hex >> 16) & 0xFF), Float((hex >> 8) & 0xFF), Float(hex & 0xFF)) / 255
            return PaletteColor(oklab: ColorScience.encodedToOKLab(rgb, space: .sRGB), space: .sRGB)
        }
        let expected = [
            "Dusty Coral", "Boiled Lobster", "Roof Tile", "Orchard Apple", "Fire Brick", "Merlot", "Pink Salt", "Mango Lassi",
            "Ochre Wall", "Sand Dune", "Eucalyptus", "Bay Leaf", "Shale", "Wet Moss", "Fresh Lawn", "Swamp Reed",
            "Bog Myrtle", "Eucalyptus Sprig", "Dragonfly", "Fresh Linen", "Pumice", "Driftwood", "Bog Oak", "Wet Asphalt",
        ]
        #expect(ColorNickname.assign(palette, seed: 0x5eed, version: 1) == expected)
        #expect(ColorNameText.nicknames(for: palette, seed: 0x5eed, version: 1, languageCode: "en")
                == expected.map { Optional($0) })
    }

    private struct NicknamePin: Decodable {
        let name: String
        let seed: UInt64
        let hexes: [UInt32]?
        let labBits: [[UInt32]]
        let names: [String]
    }

    @Test func versionTwoUsesTheSharedCorePins() throws {
        // The exact same expected names run in PaintCore on Linux/macOS and here on iOS.
        let url = Fixtures.repositoryRoot.appendingPathComponent("Tests/PaintCoreTests/Fixtures/nickname-v2.json")
        let pins = try JSONDecoder().decode([NicknamePin].self, from: Data(contentsOf: url))
        #expect(pins.count == 2)
        for pin in pins {
            let palette = pin.labBits.map { bits in
                PaletteColor(oklab: SIMD3(Float(bitPattern: bits[0]), Float(bitPattern: bits[1]), Float(bitPattern: bits[2])), rgb: .zero)
            }
            #expect(ColorNickname.assign(palette, seed: pin.seed, version: 2) == pin.names, "\(pin.name)")
            #expect(ColorNameText.nicknames(for: palette, seed: pin.seed, version: 2, languageCode: "en")
                    == pin.names.map { Optional($0) })
            if let hexes = pin.hexes {
                let reconstructed = hexes.map { hex in
                    let rgb = SIMD3(Float((hex >> 16) & 0xFF), Float((hex >> 8) & 0xFF), Float(hex & 0xFF)) / 255
                    return PaletteColor(oklab: ColorScience.encodedToOKLab(rgb, space: .sRGB), space: .sRGB)
                }
                #expect(ColorNickname.assign(reconstructed, seed: pin.seed, version: 2) == pin.names)
            }
        }
    }
}
