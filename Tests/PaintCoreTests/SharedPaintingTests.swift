import Foundation
import Testing
@testable import PaintCore

/// The file a painter sends someone else (`SharedPainting`, the app's `.moonlight`): against a
/// fixture written by its first encoder, and hostile input.
@Suite("Shared painting")
struct SharedPaintingTests {

    /// `Fixtures/shared-v1.moonlight` was written by the encoder of the commit adding it, from
    /// `template-v2-book.pbnt`'s template, titled "Irises at Dusk" with `GenerationSettings()`,
    /// uncompressed: the header, META (its JSON) and TMPL (method 0, the template's 10147 bytes).
    /// It pins the version-1 layout: never regenerate it.
    @Test func decodesFixture() throws {
        let data = try TestFixtures.data("shared-v1.moonlight")
        #expect(data.prefix(8) == Data([0x50, 0x42, 0x4D, 0x53, 1, 0, 0, 0]))
        let shared = try SharedPainting(encoded: data)
        #expect(shared.title == "Irises at Dusk")
        #expect(shared.settings == GenerationSettings())
        let book = try Template(encoded: TestFixtures.data("template-v2-book.pbnt"))
        #expect(shared.template == book)
        // The TMPL chunk closes the file: its header, method, length and the template.
        #expect(try data.suffix(10147) == TestFixtures.data("template-v2-book.pbnt"))
        #expect(data.dropLast(10147).suffix(20) == Data([
            0x54, 0x4D, 0x50, 0x4C, 1, 0, 0, 0, 0xAB, 0x27, 0, 0, 0, 0, 0, 0, 0xA3, 0x27, 0, 0,
        ]))
        #expect(shared.encoded() == data)
    }

    /// `Fixtures/shared-v1-photo.moonlight` was written by the encoder of the commit adding the
    /// photo: `shared-v1.moonlight`'s painting with `"sampleName":"irises"` in its META and, after
    /// TMPL, an optional PHOT chunk holding a 4×3 JPEG of 663 bytes (Pillow, quality 80). It pins
    /// the PHOT layout: never regenerate it.
    @Test func decodesPhotoFixture() throws {
        let data = try TestFixtures.data("shared-v1-photo.moonlight")
        #expect(data.count == 11396)
        let shared = try SharedPainting(encoded: data)
        #expect(shared.title == "Irises at Dusk" && shared.sampleName == "irises")
        #expect(try shared.template == Self.fixture().template)
        let photo = try #require(shared.photo)
        #expect(photo.count == 663 && photo.prefix(3) == Data([0xFF, 0xD8, 0xFF]))
        #expect(photo.startIndex == 0)
        // PHOT closes the file: its tag, flags 0 (optional) and length, then the photo.
        #expect(data.dropLast(663).suffix(12) == Data([0x50, 0x48, 0x4F, 0x54, 0, 0, 0, 0, 0x97, 0x02, 0, 0]))
        #expect(shared.encoded() == data)
        // A reader that doesn't know PHOT would skip it: the painting without its photo.
        #expect(try Self.fixture().photo == nil)
    }

    static func fixture() throws -> SharedPainting { try SharedPainting(encoded: TestFixtures.data("shared-v1.moonlight")) }

    /// A stand-in compressor: any reversible transform proves the method and length reach it.
    static func reversed(_ data: Data) -> Data { Data(data.reversed()) }

    @Test func roundTripsCompressed() throws {
        let shared = try Self.fixture()
        let data = shared.encoded(compression: .lzfse, compress: Self.reversed)
        var asked: (SharedPainting.Compression, Int)?
        let decoded = try SharedPainting(encoded: data) { method, stream, length in
            asked = (method, length)
            return Self.reversed(stream)
        }
        #expect(decoded == shared)
        #expect(asked?.0 == .lzfse && asked?.1 == shared.template.encoded().count)
        // Without a decompressor the template can't be read.
        #expect(throws: Template.CodingError.self) { try SharedPainting(encoded: data) }
    }

    @Test func decodesDataSlices() throws {
        let data = try TestFixtures.data("shared-v1.moonlight")
        let slice = (Data([9, 9]) + data + Data([7]))[2..<(2 + data.count)]
        #expect(try SharedPainting(encoded: slice) == Self.fixture())
    }

    @Test func titlesAreCleaned() throws {
        let template = try Self.fixture().template
        func decoded(_ title: String) throws -> String {
            try SharedPainting(encoded: SharedPainting(title: title, settings: nil, template: template).encoded()).title
        }
        #expect(try decoded("  Irises\n") == "Irises")
        #expect(try decoded("Iri\u{0}ses\u{7}") == "Irises")
        #expect(try decoded(String(repeating: "é", count: 500)).count == SharedPainting.maximumTitleLength)
        #expect(try decoded(" \t ") == "")
    }

    @Test func sampleNamesAreLibraryNamesOrNone() throws {
        let template = try Self.fixture().template
        func decoded(_ name: String) throws -> String? {
            try SharedPainting(encoded: SharedPainting(title: "A", settings: nil, template: template, sampleName: name).encoded()).sampleName
        }
        #expect(try decoded("great-wave") == "great-wave")
        #expect(try decoded("red-fuji-2") == "red-fuji-2")
        for bad in ["", "Great-Wave", "../wave", "wave.jpg", "wave name", String(repeating: "a", count: 65), "vågen"] {
            #expect(try decoded(bad) == nil, "\(bad)")
        }
    }

    // MARK: - Hostile input

    /// A file of `chunks` after a valid header.
    static func file(version: UInt32 = 1, chunkCount: UInt32? = nil, _ chunks: [(tag: UInt32, flags: UInt32, payload: Data)], trailing: Data = Data()) -> Data {
        var w = BinaryWriter()
        w.write(SharedPainting.magic)
        w.write(version)
        w.write(chunkCount ?? UInt32(chunks.count))
        for chunk in chunks {
            w.write(chunk.tag); w.write(chunk.flags); w.write(UInt32(chunk.payload.count)); w.write(bytes: chunk.payload)
        }
        return w.data + trailing
    }

    static func meta(_ json: String = #"{"title":"A"}"#) -> (tag: UInt32, flags: UInt32, payload: Data) {
        (SharedPainting.Chunk.meta, 1, Data(json.utf8))
    }

    static func body(method: UInt32 = 0, length: UInt32? = nil, _ stream: Data) -> (tag: UInt32, flags: UInt32, payload: Data) {
        var w = BinaryWriter()
        w.write(method); w.write(length ?? UInt32(stream.count)); w.write(bytes: stream)
        return (SharedPainting.Chunk.template, 1, w.data)
    }

    static func templateBytes() throws -> Data { try TestFixtures.data("template-v2-book.pbnt") }

    @Test func chunkRules() throws {
        let t = try Self.templateBytes()
        func error(_ data: Data) -> Template.CodingError? {
            do { _ = try SharedPainting(encoded: data); return nil } catch { return error as? Template.CodingError }
        }
        // Order doesn't matter; unknown optional chunks are skipped; unknown meta keys ignored.
        let minimal = try SharedPainting(encoded: Self.file([Self.body(t), (0x5859_5A57, 0, Data([1, 2])), Self.meta(#"{"title":"A","x":[1]}"#)]))
        #expect(minimal.title == "A" && minimal.settings == nil)
        // Settings that don't decode are none.
        #expect(try SharedPainting(encoded: Self.file([Self.meta(#"{"title":"A","settings":{"detail":"x"}}"#), Self.body(t)])).settings == nil)

        #expect(error(Self.file([Self.meta(), Self.body(t), (0x5859_5A57, 1, Data())])) == .requiredExtension(0x5859_5A57))
        #expect(error(Self.file(version: 2, [Self.meta(), Self.body(t)])) == .newerFormat(2))
        #expect(error(Self.file(version: 2, [Self.meta(), Self.body(t)]))?.requiresNewerReader == true)
        #expect(error(Self.file(version: 0, [Self.meta(), Self.body(t)])) == .corrupt("version"))
        #expect(error(Data("PBNT".utf8) + Self.file([Self.meta(), Self.body(t)]).dropFirst(4)) == .badMagic)
        #expect(error(Self.file([Self.meta(), Self.body(method: 9, t)])) == .requiredExtension(SharedPainting.Chunk.template))
        #expect(error(Self.file([Self.meta(), Self.meta(), Self.body(t)])) == .corrupt("duplicate chunk"))
        #expect(error(Self.file([Self.meta(), Self.body(t), Self.body(t)])) == .corrupt("duplicate chunk"))
        #expect(error(Self.file([Self.meta()])) == .corrupt("missing chunk"))
        #expect(error(Self.file([Self.body(t)])) == .corrupt("missing chunk"))
        #expect(error(Self.file([Self.meta(), Self.body(t)], trailing: Data([0]))) == .corrupt("trailing bytes"))
        let photo = (tag: SharedPainting.Chunk.photo, flags: UInt32(0), payload: Data([0xFF, 0xD8]))
        #expect(try SharedPainting(encoded: Self.file([Self.meta(), photo, Self.body(t)])).photo == Data([0xFF, 0xD8]))
        #expect(error(Self.file([Self.meta(), Self.body(t), photo, photo])) == .corrupt("duplicate chunk"))
        #expect(error(Self.file([Self.meta(), Self.body(t), (photo.tag, 0, Data())])) == .corrupt("PHOT"))
        #expect(error(Self.file([Self.meta(), Self.body(t), (photo.tag, 0, Data(count: SharedPainting.maximumPhotoBytes + 1))])) == .corrupt("PHOT"))
        #expect(error(Self.file(chunkCount: 3, [Self.meta(), Self.body(t)])) == .truncated)
        #expect(error(Self.file(chunkCount: 0xFFFF_FFFF, [Self.meta(), Self.body(t)])) == .truncated)
        #expect(error(Self.file([Self.meta(#"{"name":"A"}"#), Self.body(t)])) == .corrupt("META"))
        #expect(error(Self.file([Self.meta("not json"), Self.body(t)])) == .corrupt("META"))
        let long = #"{"title":""# + String(repeating: "a", count: SharedPainting.maximumMetaBytes) + #""}"#
        #expect(error(Self.file([Self.meta(long), Self.body(t)])) == .corrupt("META"))
        #expect(error(Self.file([Self.meta(), Self.body(length: UInt32(t.count + 1), t)])) == .corrupt("TMPL"))
        #expect(error(Self.file([Self.meta(), Self.body(Data())])) == .corrupt("TMPL"))
        // A damaged template is the template decoder's error.
        #expect(error(Self.file([Self.meta(), Self.body(t.prefix(100))])) == .truncated)
    }

    /// The decompressed length is bounded before anything decompresses, and must come out exact.
    @Test func decompressionIsBounded() throws {
        let t = try Self.templateBytes()
        var calls = 0
        let huge = Self.file([Self.meta(), Self.body(method: 1, length: 0xFFFF_FFFF, Data([1, 2, 3]))])
        #expect(throws: Template.CodingError.corrupt("TMPL")) {
            try SharedPainting(encoded: huge, maximumTemplateBytes: 1 << 20) { _, _, _ in calls += 1; return Data() }
        }
        #expect(calls == 0)
        let short = Self.file([Self.meta(), Self.body(method: 1, length: UInt32(t.count), Self.reversed(t))])
        #expect(throws: Template.CodingError.corrupt("TMPL")) {
            try SharedPainting(encoded: short) { _, stream, _ in Self.reversed(stream).dropLast() }
        }
        #expect(try SharedPainting(encoded: short) { _, stream, _ in Self.reversed(stream) }.template == Template(encoded: t))
    }

    /// Every proper prefix of the file is rejected with a `CodingError` (never a trap).
    @Test(arguments: ["shared-v1.moonlight", "shared-v1-photo.moonlight"])
    func truncationAtEveryOffset(_ name: String) throws {
        let data = try TestFixtures.data(name)
        for length in 0..<data.count {
            #expect(throws: Template.CodingError.self, "length \(length)") { try SharedPainting(encoded: data.prefix(length)) }
        }
    }

    /// Seeded random byte flips: every case throws a `CodingError` or decodes to a painting whose
    /// template's accessors and `validate()` run without trapping.
    @Test(arguments: ["shared-v1.moonlight", "shared-v1-photo.moonlight"])
    func randomCorruption(_ name: String) throws {
        let data = try TestFixtures.data(name)
        var rng = SplitMix64(seed: 0x5EED_5A1E)
        var decoded = 0
        let cases = 3000
        for _ in 0..<cases {
            var bytes = data
            for _ in 0..<(1 + Int(rng.next() % 4)) {
                let i = Int(rng.next() % UInt64(bytes.count))
                if rng.next() % 2 == 0 { bytes[i] ^= UInt8(1) << (rng.next() % 8) } else { bytes[i] = UInt8(truncatingIfNeeded: rng.next()) }
            }
            do {
                let shared = try SharedPainting(encoded: bytes)
                decoded += 1
                #expect(shared.title.count <= SharedPainting.maximumTitleLength)
                TemplateCodingTests.exercise(shared.template)
            } catch is Template.CodingError {
            } catch {
                Issue.record("unexpected error \(error)")
            }
        }
        #expect(decoded > 0 && decoded < cases)
    }
}
