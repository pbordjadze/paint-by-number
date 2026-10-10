import Foundation
import Testing
@testable import PaintCore

/// Coding of detail areas (`Template.detailRegions`): the optional `DETL` chunk, against a
/// fixture written by its first encoder and against today's encoder output, and hostile input.
@Suite("Detail coding")
struct DetailCodingTests {

    /// `Fixtures/template-v2-detail.pbnt` was written by the DETL encoder of the commit adding
    /// it, with `pbn generate Fixtures/layered-photo.ppm <dir> --colors 8 --line-style coloringBook
    /// --edges Fixtures/layered-edges.pgm --line-art outlineThreshold=0.8 --line-art
    /// detailThreshold=0.5 --line-art minimumStrokeLength=10 --line-art gapBridging=6
    /// --line-edits edits.json` and edits.json `[{"kind": "draw", "points": [[0.52083, 0.11806],
    /// [0.53646, 0.13889], [0.52083, 0.15972], [0.50521, 0.13889], [0.52083, 0.11806]]}, {"kind":
    /// "fill", "points": [[0.52083, 0.13889]]}]`: a diamond 6 units across drawn in the sky and
    /// filled: region 1, in the sky's paint (number 4), its line joined to it. The v1 payload,
    /// then GENR, LINE and DETL (one region). It pins the DETL layout: never regenerate it.
    @Test func decodesDetailFixture() throws {
        let data = try TestFixtures.data("template-v2-detail.pbnt")
        #expect(data.count == 11234)
        #expect(data[4..<8] == Data([2, 0, 0, 0]))
        let t = try Template(encoded: data)
        #expect(t.width == 192 && t.height == 144)
        #expect(t.regions.count == 5 && t.edges.count == 10 && t.points.count == 164 && t.palette.count == 4)
        #expect(t.pipelineVersion == 8)
        #expect(t.lineArt?.style == .coloringBook)
        #expect(t.detailRegions == [1])
        #expect(t.isDetailRegion(1) && !t.isDetailRegion(0) && !t.isDetailRegion(4) && !t.isDetailRegion(-1))
        #expect(t.regions[1].colorIndex == 3 && t.regions[0].colorIndex == 3)
        let label = try #require(t.labels(ofRegion: 1).first)
        #expect(abs(label.radius - 2.491) < 1e-3 && abs(t.regions[1].area - 19.9) < 0.05)
        // The chunk section after the payload (11111 bytes): its count (4), GENR (16), LINE (83:
        // its header and 71 bytes) and DETL (20: its header, the count and the one region).
        let tags = try LineArtCodingTests.chunks(data, payloadEnd: 11111)
        #expect(tags.map(\.0) == [Template.Chunk.generator, Template.Chunk.lines, Template.Chunk.detail])
        #expect(tags.allSatisfy { $0.1 == 0 })
        #expect(data.suffix(20) == Data([0x44, 0x45, 0x54, 0x4C, 0, 0, 0, 0, 8, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0]))
        expectValid(t)
        #expect(t.encoded() == data)
    }

    /// A template made with a fill round-trips, the chunk written after LINE and only when there
    /// are detail areas.
    @Test func roundTripsDetailRegions() throws {
        let t = try FillTests.generate([FillTests.star(), FillTests.fill(FillTests.centre)]).template
        #expect(t.detailRegions.count == 1)
        let decoded = try Template(encoded: t.encoded())
        #expect(decoded == t && decoded.detailRegions == t.detailRegions)
        let tags = try LineArtCodingTests.chunks(t.encoded(), payloadEnd: LineArtCodingTests.chunkSectionStart(of: t))
        #expect(tags.map(\.0) == [Template.Chunk.generator, Template.Chunk.lines, Template.Chunk.detail])
        var none = t
        none.detailRegions = []
        #expect(none.encoded().count == t.encoded().count - 20)
    }

    /// The chunk is optional: a reader that doesn't know it skips it. Known, it reads the same
    /// in any order, and fields a later writer appends to it are ignored.
    @Test func detailChunkIsOptional() throws {
        let t = try Template(encoded: TestFixtures.data("template-v2-detail.pbnt"))
        var generator = BinaryWriter()
        generator.write(t.pipelineVersion)
        var detail = BinaryWriter()
        detail.writeArray(t.detailRegions)
        let lines = (tag: Template.Chunk.lines, flags: UInt32(0), payload: t.lineArt!.encoded())
        let reordered = LineArtCodingTests.file(
            t, chunks: [(Template.Chunk.detail, 0, detail.data), lines, (Template.Chunk.generator, 0, generator.data)])
        #expect(try Template(encoded: reordered) == t)
        let longer = LineArtCodingTests.file(
            t, chunks: [(Template.Chunk.generator, 0, generator.data), lines, (Template.Chunk.detail, 0, detail.data + Data([7, 0, 0, 0, 9]))])
        #expect(try Template(encoded: longer) == t)
        // Under another tag (a reader that doesn't know DETL), the same painting with no detail area.
        let unknown = LineArtCodingTests.file(
            t, chunks: [(Template.Chunk.generator, 0, generator.data), lines, (0x5858_5858, 0, detail.data)])
        let older = try Template(encoded: unknown)
        #expect(older.detailRegions.isEmpty && older.regions == t.regions && older.labels == t.labels)
    }

    /// Regions out of range, out of order or twice, an empty or short list and a second chunk
    /// are corrupt, never a crash or a newer reader's file.
    @Test func craftedDetailRegionsAreCorrupt() throws {
        let base = try Template(encoded: TestFixtures.data("template-v2-detail.pbnt"))
        let regions = UInt32(base.regions.count)
        for (name, list) in [
            ("past the regions", [regions]), ("far past", [UInt32.max]), ("descending", [3, 1]), ("twice", [1, 1]),
            ("after one past", [1, regions]),
        ] as [(String, [UInt32])] {
            var t = base
            t.detailRegions = list
            let error = #expect(throws: Template.CodingError.self, "\(name)") { try Template(encoded: t.encoded()) }
            #expect(error == .corrupt("detail regions"), "\(name)")
            #expect(error?.requiresNewerReader == false, "\(name)")
        }
        var generator = BinaryWriter()
        generator.write(base.pipelineVersion)
        func file(_ detail: [Data]) -> Data {
            LineArtCodingTests.file(base, chunks: [(Template.Chunk.generator, 0, generator.data)] + detail.map { (Template.Chunk.detail, 0, $0) })
        }
        var one = BinaryWriter()
        one.writeArray([UInt32(1)])
        #expect(try Template(encoded: file([one.data])).detailRegions == [1])
        #expect(throws: Template.CodingError.corrupt("duplicate chunk")) { try Template(encoded: file([one.data, one.data])) }
        #expect(throws: Template.CodingError.corrupt("DETL")) { try Template(encoded: file([Data([0, 0, 0, 0])])) }
        #expect(throws: Template.CodingError.corrupt("DETL")) { try Template(encoded: file([Data([2, 0, 0, 0, 1, 0, 0, 0])])) }
        #expect(throws: Template.CodingError.corrupt("DETL")) { try Template(encoded: file([Data([0xFF, 0xFF, 0xFF, 0xFF])])) }
        #expect(throws: Template.CodingError.corrupt("DETL")) { try Template(encoded: file([Data([1, 0])])) }
    }

    /// Random damage to the last chunks (LINE's end and DETL; every prefix and damage anywhere
    /// are `TemplateCodingTests`') decodes to a template that is safe to use, or throws.
    @Test func damagedDetailChunk() throws {
        let data = try TestFixtures.data("template-v2-detail.pbnt")
        var rng = SplitMix64(seed: 0xDE7A)
        var decoded = 0
        for _ in 0..<2000 {
            var bytes = data
            for _ in 0..<(1 + Int(rng.next() % 3)) {
                let i = data.count - 1 - Int(rng.next() % 40)
                if rng.next() % 2 == 0 { bytes[i] ^= UInt8(1) << (rng.next() % 8) } else { bytes[i] = UInt8(truncatingIfNeeded: rng.next()) }
            }
            do {
                let t = try Template(encoded: bytes)
                decoded += 1
                TemplateCodingTests.exercise(t)
                for r in t.regions.indices { _ = t.isDetailRegion(r) }
                #expect(t.detailRegions.allSatisfy { Int($0) < t.regions.count })
            } catch is Template.CodingError {
            } catch {
                Issue.record("unexpected error \(error)")
            }
        }
        #expect(decoded > 0 && decoded < 2000)
    }
}
