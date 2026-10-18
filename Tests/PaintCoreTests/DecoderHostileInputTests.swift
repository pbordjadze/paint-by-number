import Foundation
import Testing
@testable import PaintCore

/// Targeted fuzzing complements the unrestricted flips in TemplateCodingTests: every input
/// here is known to be invalid, so silently accepting damage also fails the test.
@Suite("Decoder hostile input")
struct DecoderHostileInputTests {
    static func replacing(_ data: Data, at offset: Int, with value: UInt32) -> Data {
        var bytes = data
        withUnsafeBytes(of: value.littleEndian) { bytes.replaceSubrange(offset..<(offset + 4), with: $0) }
        return bytes
    }

    /// Discover each base array's count from the frozen v1 layout, including the RLE array.
    static func counts(_ data: Data) throws -> [(String, Int)] {
        var r = BinaryReader(data)
        _ = try r.readBytes(17) // magic, version, canvas, color space
        var offsets: [(String, Int)] = []
        for (name, size) in [("palette", 24), ("regions", 52), ("points", 8),
                             ("edges", 16), ("ring edges", 4), ("rings", 9),
                             ("labels", 16), ("vertices", 8), ("vertex regions", 4),
                             ("indices", 4), ("runs", 4)] {
            offsets.append((name, r.offset))
            let count = try r.readCount(elementSize: size)
            _ = try r.readBytes(count * size)
        }
        #expect(r.isAtEnd)
        return offsets
    }

    static func refuse(_ data: Data, _ context: String) {
        #expect(throws: Template.CodingError.self, "template: \(context)") { try Template(encoded: data) }
        let shared = SharedPaintingTests.file([SharedPaintingTests.meta(), SharedPaintingTests.body(data)])
        #expect(throws: Template.CodingError.self, "moonlight: \(context)") { try SharedPainting(encoded: shared) }
    }

    /// TMPL's envelope and declared length are valid even when its template is a proper prefix.
    /// This reaches the nested decoder rather than stopping at the outer chunk length check.
    @Test func embeddedTemplateTruncatedAtEveryOffset() throws {
        let data = try TestFixtures.data("template-v2-writing.pbnt")
        for length in 0..<data.count {
            Self.refuse(Data(data.prefix(length)), "prefix \(length)")
        }
    }

    @Test func everyBaseCountIsBounded() throws {
        let data = try TestFixtures.data("template-v1.pbnt")
        for (name, offset) in try Self.counts(data) {
            for count: UInt32 in [0x7FFF_FFFF, .max] {
                Self.refuse(Self.replacing(data, at: offset, with: count), "\(name): \(count)")
            }
        }
    }

    /// Randomize all four count bytes, forcing the high bit so every mutation exceeds this
    /// small file. Unlike unrestricted flips, no accepted mutation is allowed here.
    @Test func seededCountByteCorruptionIsRefused() throws {
        let data = try TestFixtures.data("template-v1.pbnt")
        let offsets = try Self.counts(data)
        var rng = SplitMix64(seed: 0xBAD_C0_017)
        for iteration in 0..<512 {
            let (name, offset) = offsets[Int(rng.next() % UInt64(offsets.count))]
            let count = UInt32(truncatingIfNeeded: rng.next()) | 0x8000_0000
            Self.refuse(Self.replacing(data, at: offset, with: count), "seeded \(iteration), \(name)")
        }
    }

    @Test func overlappingOwnershipSpansAreRefused() throws {
        let base = try TemplateCodingTests.v1Template()
        let mutations: [(String, (inout Template) -> Void)] = [
            ("region rings", { $0.regions[1].ringStart = $0.regions[0].ringStart }),
            ("region labels", { $0.regions[1].labelStart = $0.regions[0].labelStart }),
            ("region triangles", { $0.regions[1].indexStart = $0.regions[0].indexStart }),
            ("ring references", { $0.rings[1].edgeStart = $0.rings[0].edgeStart }),
            ("partially overlapping triangles", {
                $0.regions[0].indexStart = 0; $0.regions[0].indexCount = 6
                $0.regions[1].indexStart = 3; $0.regions[1].indexCount = 6
            }),
            ("nested ring spans", {
                $0.regions[0].ringStart = 0; $0.regions[0].ringCount = 3
                $0.regions[1].ringStart = 1; $0.regions[1].ringCount = 1
            }),
        ]
        for (name, mutate) in mutations {
            var t = base
            mutate(&t)
            Self.refuse(t.encoded(), name)
        }
    }

    /// Overlap checks must allow adjacent spans, empty spans and storage in another order.
    @Test func disjointOwnershipSpansStillDecode() throws {
        var t = try TemplateCodingTests.v1Template()
        t.regions.reverse()
        t.rings.reverse()
        #expect(try Template(encoded: t.encoded()) == t)
        t.regions[0].ringStart = UInt32(t.rings.count)
        t.regions[0].ringCount = 0
        t.regions[0].labelStart = UInt32(t.labels.count)
        t.regions[0].labelCount = 0
        t.regions[0].indexStart = UInt32(t.mesh.indices.count)
        t.regions[0].indexCount = 0
        #expect(try Template(encoded: t.encoded()) == t)
    }

    @Test func nestedOutOfRangeReferencesAreRefused() throws {
        let base = try TemplateCodingTests.v1Template()
        let mutations: [(String, (inout Template) -> Void)] = [
            ("ring reference", { $0.ringEdges[0].edge = 0x7FFF_FFFF }),
            ("triangle vertex", { $0.mesh.indices[0] = .max }),
            ("vertex owner", { $0.mesh.vertexRegion[0] = .max }),
            ("map owner", { $0.regionMap.storage[0] = .max }),
            ("ring span wraps", { $0.rings[0].edgeStart = .max; $0.rings[0].edgeCount = .max }),
            ("label span wraps", { $0.regions[0].labelStart = .max; $0.regions[0].labelCount = .max }),
        ]
        for (name, mutate) in mutations {
            var t = base
            mutate(&t)
            Self.refuse(t.encoded(), name)
        }
    }

    @Test func extensionCountsAndLengthsAreBounded() throws {
        let t = try Template(encoded: TestFixtures.data("template-v2-writing.pbnt"))
        let lines = try #require(t.lineArt)
        let payload = lines.encoded()
        let pointCountOffset = 4 + 2 * lines.edgeLayers.count
        let strokeCountOffset = pointCountOffset + 4 + 8 * lines.strokePoints.count
        for offset in [0, pointCountOffset, strokeCountOffset] {
            let bad = Self.replacing(payload, at: offset, with: .max)
            Self.refuse(LineArtCodingTests.file(t, chunks: [(Template.Chunk.lines, 0, bad)]), "LINE count at \(offset)")
        }
        for tag in [Template.Chunk.detail, Template.Chunk.writing] {
            Self.refuse(LineArtCodingTests.file(t, chunks: [(tag, 0, TemplateCodingTests.uint32(.max))]), "extension count \(tag)")
        }
        var classic = t
        classic.lineArt = nil
        classic.detailRegions = []
        let bytes = classic.encoded()
        let chunkStart = LineArtCodingTests.chunkSectionStart(of: classic)
        for offset in [chunkStart, chunkStart + 12] {
            Self.refuse(Self.replacing(bytes, at: offset, with: .max), "chunk count/length at \(offset)")
        }
    }

    @Test func sharedChunkCountsAndLengthsAreBounded() throws {
        let data = SharedPaintingTests.file([SharedPaintingTests.meta(), SharedPaintingTests.body(try SharedPaintingTests.templateBytes())])
        // Header count, META length, TMPL length, and TMPL's decompressed length.
        let templateHeader = 24 + SharedPaintingTests.meta().payload.count
        var rng = SplitMix64(seed: 0x5A1E_BAD)
        for offset in [8, 20, templateHeader + 8, templateHeader + 16] {
            for iteration in 0..<128 {
                let value = UInt32(truncatingIfNeeded: rng.next()) | 0x8000_0000
                let bytes = Self.replacing(data, at: offset, with: value)
                var calls = 0
                #expect(throws: Template.CodingError.self, "offset \(offset), case \(iteration)") {
                    try SharedPainting(encoded: bytes) { _, _, _ in calls += 1; return Data() }
                }
                #expect(calls == 0)
            }
        }
    }
}
