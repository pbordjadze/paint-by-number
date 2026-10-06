import Foundation
import Testing
@testable import PaintCore

/// Coding of line data: the LINE chunk and its trailing style byte, against fixtures written by
/// past encoders and against today's encoder output.
@Suite("Line art coding")
struct LineArtCodingTests {

    /// `Fixtures/template-v2-lines.pbnt` was written by the LINE encoder of commit 7ae42a1 with
    /// `pbn generate Fixtures/layered-photo.ppm <dir> --colors 8 --line-style layered --edges
    /// Fixtures/layered-edges.pgm --line-art outlineThreshold=0.8 --line-art detailThreshold=0.5
    /// --line-art textureThreshold=0.3 --line-art minimumStrokeLength=10 --line-art gapBridging=6`
    /// (a pbn of that time: the layered style is retired, and the app draws the fixture as a book):
    /// the v1 payload, then a GENR and a LINE chunk (12 edges: 7 outline, 1 detail, 4 color; one
    /// texture stroke of 6 points inside the joined sky). It pins the LINE layout: never
    /// regenerate it.
    @Test func decodesLayeredFixture() throws {
        let data = try TestFixtures.data("template-v2-lines.pbnt")
        #expect(data.count == 11152)
        #expect(data[4..<8] == Data([2, 0, 0, 0]))
        let t = try Template(encoded: data)
        #expect(t.width == 192 && t.height == 144)
        #expect(t.regions.count == 5 && t.edges.count == 12 && t.points.count == 165 && t.palette.count == 4)
        #expect(t.pipelineVersion == 3)
        let lines = try #require(t.lineArt)
        #expect(lines.edgeLayers == [0, 0, 0, 0, 0, 0, 0, 3, 3, 3, 1, 3])
        #expect(lines.edgeWeights == [218, 230, 230, 228, 228, 215, 217, 0, 0, 0, 147, 0])
        #expect(lines.strokePoints.count == 6)
        #expect(lines.strokes == [InteriorStroke(pointStart: 0, pointCount: 6, layer: 2, weight: 103, region: 0)])
        expectValid(t)
        // The chunk section: GENR then LINE (98 bytes), optional. The payload ends at 11022: the count (4),
        // GENR (16) and the LINE chunk (12-byte header, 98 bytes) fill the other 130 bytes.
        let tags = try Self.chunks(data, payloadEnd: 11022)
        #expect(tags.map(\.0) == [Template.Chunk.generator, Template.Chunk.lines])
        #expect(tags.allSatisfy { $0.1 == 0 })
        // Re-encoding writes the same bytes.
        #expect(t.encoded() == data)
    }

    @Test func roundTripsLineArt() throws {
        let t = try LineArtTests.generate().template
        let decoded = try Template(encoded: t.encoded())
        #expect(decoded == t)
        #expect(decoded.lineArt == t.lineArt)
        // Without the chunk (an older writer, or classic) the same cells decode, drawn alike.
        var classic = t
        classic.lineArt = nil
        let plain = try Template(encoded: classic.encoded())
        #expect(plain.lineArt == nil && plain.regions == t.regions)
    }

    /// `Fixtures/template-v2-book.pbnt` was written by the LINE encoder of the commit adding
    /// `TemplateLineArt.style`, with the layered fixture's command and `--line-style coloringBook`:
    /// the same five cells and twelve edges in the same layers (the sky's faint line, below
    /// detail, is not drawn at all, so there is no stroke), and the style byte after the
    /// (empty) strokes. It pins that byte: never regenerate it.
    @Test func decodesColoringBookFixture() throws {
        let data = try TestFixtures.data("template-v2-book.pbnt")
        #expect(data.count == 10147)
        #expect(data[4..<8] == Data([2, 0, 0, 0]))
        let t = try Template(encoded: data)
        #expect(t.width == 192 && t.height == 144)
        #expect(t.regions.count == 5 && t.edges.count == 12 && t.palette.count == 4)
        #expect(t.pipelineVersion == 3)
        let lines = try #require(t.lineArt)
        #expect(lines.style == .coloringBook)
        #expect(lines.edgeLayers == [0, 0, 0, 0, 0, 0, 0, 3, 3, 3, 1, 3])
        #expect(lines.edgeWeights == [218, 230, 230, 228, 228, 215, 217, 0, 0, 0, 148, 0])
        #expect(lines.strokes.isEmpty && lines.strokePoints.isEmpty)
        // The chunk section: its count, GENR, then LINE (37 bytes: 4 + 12 + 12 + 4 + 4 + the style byte).
        // The payload ends before the count (4), GENR (16) and the LINE chunk (49 with its header).
        let tags = try Self.chunks(data, payloadEnd: data.count - 4 - 16 - 49)
        #expect(tags.map(\.0) == [Template.Chunk.generator, Template.Chunk.lines])
        #expect(tags.allSatisfy { $0.1 == 0 })
        #expect(data.last == TemplateLineArt.Style.coloringBook.rawValue)
        expectValid(t)
        #expect(t.encoded() == data)
    }

    @Test func lineArtStyleIsAnOptionalTrailingByte() throws {
        let book = try LineArtTests.generate().template
        let art = try #require(book.lineArt)
        #expect(art.style == .coloringBook)
        #expect(try Template(encoded: book.encoded()) == book)
        // Layered templates encode as they always did, without the byte.
        var layered = art
        layered.style = .layered
        #expect(layered.encoded() == art.encoded().dropLast())
        #expect(art.encoded().last == TemplateLineArt.Style.coloringBook.rawValue)
        // The byte is read when present: a layered payload plus it is a coloring book, and a
        // book payload without it (an older writer) or with a style this reader does not know
        // (a later one) is layered.
        var generator = BinaryWriter()
        generator.write(book.pipelineVersion)
        func decode(_ payload: Data) throws -> TemplateLineArt? {
            try Template(encoded: Self.file(book, chunks: [(Template.Chunk.generator, 0, generator.data), (Template.Chunk.lines, 0, payload)])).lineArt
        }
        #expect(try decode(layered.encoded() + Data([1]))?.style == .coloringBook)
        #expect(try decode(art.encoded().dropLast())?.style == .layered)
        #expect(try decode(layered.encoded() + Data([9]))?.style == .layered)
        #expect(try decode(art.encoded() + Data([5, 6]))?.style == .coloringBook)
    }

    /// Where the chunk section starts in `t`'s encoding. The classic file ends with the chunk
    /// count (4 bytes) and its one chunk (GENR: 12-byte header, 4-byte payload).
    static func chunkSectionStart(of t: Template) -> Int {
        var classic = t
        classic.lineArt = nil
        return classic.encoded().count - 4 - 16
    }

    /// A file of `t`'s payload followed by `chunks`.
    static func file(_ t: Template, chunks: [(tag: UInt32, flags: UInt32, payload: Data)]) -> Data {
        var classic = t
        classic.lineArt = nil
        var w = BinaryWriter()
        w.write(bytes: classic.encoded().prefix(chunkSectionStart(of: t)))
        w.write(UInt32(chunks.count))
        for c in chunks {
            w.write(c.tag); w.write(c.flags); w.write(UInt32(c.payload.count)); w.write(bytes: c.payload)
        }
        return w.data
    }

    /// The (tag, flags) of every chunk of a layered file.
    static func chunks(_ data: Data, payloadEnd: Int) throws -> [(UInt32, UInt32)] {
        var r = BinaryReader(data[payloadEnd...])
        var tags: [(UInt32, UInt32)] = []
        for _ in 0..<(try r.read(UInt32.self)) {
            let tag = try r.read(UInt32.self), flags = try r.read(UInt32.self)
            _ = try r.readBytes(Int(try r.read(UInt32.self)))
            tags.append((tag, flags))
        }
        #expect(r.isAtEnd)
        return tags
    }

    @Test func lineChunkIsOptional() throws {
        // The chunk is flagged optional, so readers that don't know it skip it.
        let t = try LineArtTests.generate().template
        let tags = try Self.chunks(t.encoded(), payloadEnd: Self.chunkSectionStart(of: t))
        #expect(tags.map(\.0) == [Template.Chunk.generator, Template.Chunk.lines])
        #expect(tags.allSatisfy { $0.1 & Template.Chunk.requiredFlag == 0 })
        // Written with the other chunks in any order, it reads the same.
        var generator = BinaryWriter()
        generator.write(t.pipelineVersion)
        let reordered = Self.file(t, chunks: [(Template.Chunk.lines, 0, t.lineArt!.encoded()), (Template.Chunk.generator, 0, generator.data)])
        #expect(try Template(encoded: reordered) == t)
        // A later writer may append fields to the chunk (after the style byte, 0 for layered).
        let longer = Self.file(t, chunks: [(Template.Chunk.generator, 0, generator.data),
                                           (Template.Chunk.lines, 0, t.lineArt!.encoded() + Data([0, 2, 3]))])
        #expect(try Template(encoded: longer) == t)
    }

    @Test func truncatedLayeredFilesAreRejected() throws {
        let data = try LineArtTests.generate().template.encoded()
        // The chunk section is at the end; every prefix from the payload's end on is short.
        for length in stride(from: 0, to: data.count, by: max(1, data.count / 4000)) {
            #expect(throws: Template.CodingError.self, "length \(length)") { try Template(encoded: data.prefix(length)) }
        }
        let tail = data.count - 400
        for length in tail..<data.count {
            #expect(throws: Template.CodingError.self, "length \(length)") { try Template(encoded: data.prefix(length)) }
        }
    }

    @Test func randomCorruptionOfLineData() throws {
        let data = try LineArtTests.generate().template.encoded()
        var rng = SplitMix64(seed: 0x11E5)
        var decoded = 0
        let tail = 600
        for _ in 0..<2000 {
            var bytes = data
            for _ in 0..<(1 + Int(rng.next() % 3)) {
                // Mostly in the chunk section, where the line data is.
                let i = data.count - 1 - Int(rng.next() % UInt64(tail))
                if rng.next() % 2 == 0 { bytes[i] ^= UInt8(1) << (rng.next() % 8) } else { bytes[i] = UInt8(truncatingIfNeeded: rng.next()) }
            }
            do {
                let t = try Template(encoded: bytes)
                decoded += 1
                TemplateCodingTests.exercise(t)
            } catch is Template.CodingError {
            } catch {
                Issue.record("unexpected error \(error)")
            }
        }
        #expect(decoded > 0 && decoded < 2000)
    }

    @Test func craftedLineReferencesAreCorrupt() throws {
        let base = try LineArtTests.generate().template
        let lines = try #require(base.lineArt)
        try #require(!lines.strokes.isEmpty)
        let mutations: [(String, (inout TemplateLineArt) -> Void)] = [
            ("layer count", { $0.edgeLayers.removeLast() }),
            ("weight count", { $0.edgeWeights.append(0) }),
            ("unknown layer", { $0.edgeLayers[0] = 4 }),
            ("stroke layer", { $0.strokes[0].layer = 200 }),
            ("stroke region", { $0.strokes[0].region = UInt32(base.regions.count) }),
            ("stroke start", { $0.strokes[0].pointStart = .max }),
            ("stroke span wraps", { $0.strokes[0].pointStart = .max; $0.strokes[0].pointCount = 3 }),
            ("stroke one point", { $0.strokes[0].pointCount = 1 }),
            ("stroke past points", { $0.strokes[0].pointCount = UInt32($0.strokePoints.count) + 1 }),
            ("point NaN", { $0.strokePoints[0] = SIMD2(.nan, 1) }),
            ("point outside", { $0.strokePoints[0].x = Float(base.width) + 1 }),
            ("point negative", { $0.strokePoints[0].y = -0.5 }),
        ]
        for (name, mutate) in mutations {
            var t = base
            mutate(&t.lineArt!)
            let error = #expect(throws: Template.CodingError.self, "\(name)") { try Template(encoded: t.encoded()) }
            if case .corrupt = error {} else { Issue.record("\(name): \(String(describing: error))") }
            #expect(error?.requiresNewerReader == false, "\(name)")
        }
        // A duplicate chunk, or one for another number of edges, is corrupt too.
        let duplicate = Self.file(base, chunks: [(Template.Chunk.lines, 0, lines.encoded()), (Template.Chunk.lines, 0, lines.encoded())])
        #expect(throws: Template.CodingError.corrupt("duplicate chunk")) { try Template(encoded: duplicate) }
        var fewer = lines
        fewer.edgeLayers.removeLast()
        fewer.edgeWeights.removeLast()
        let mismatch = Self.file(base, chunks: [(Template.Chunk.lines, 0, fewer.encoded())])
        #expect(throws: Template.CodingError.corrupt("LINE edge count")) { try Template(encoded: mismatch) }
        let short = Self.file(base, chunks: [(Template.Chunk.lines, 0, lines.encoded().dropLast(3))])
        #expect(throws: Template.CodingError.corrupt("LINE")) { try Template(encoded: short) }
    }
}
