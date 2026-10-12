import Foundation
import Testing
@testable import PaintCore

/// Coding of which interior strokes are writing (`TemplateLineArt.writingStrokes`): the optional
/// `WRIT` chunk, against a fixture written by its first encoder and against today's encoder
/// output, and hostile input.
@Suite("Writing coding")
struct WritingCodingTests {

    /// `Fixtures/template-v2-writing.pbnt` was written by the WRIT encoder of the commit adding it
    /// from `template-v2-book.pbnt`'s template, stamped pipeline 11 and given four strokes in its
    /// line art: a drawing stroke in the sky (region 0), two writing strokes (an "L" and an "I")
    /// in region 2, whose paint (number 1, OKLab lightness 0.423) is dark, and one in region 3,
    /// whose paint (number 3, 0.614) is not; the last three are the writing. The v1 payload, then
    /// GENR, LINE and WRIT (three strokes). It pins the WRIT layout: never regenerate it.
    @Test func decodesWritingFixture() throws {
        let data = try TestFixtures.data("template-v2-writing.pbnt")
        #expect(data.count == 10311)
        #expect(data[4..<8] == Data([2, 0, 0, 0]))
        let t = try Template(encoded: data)
        #expect(t.width == 192 && t.height == 144)
        #expect(t.regions.count == 5 && t.edges.count == 12 && t.palette.count == 4)
        #expect(t.pipelineVersion == 11)
        let art = try #require(t.lineArt)
        #expect(art.style == .coloringBook && art.strokes.count == 4)
        #expect(art.writingStrokes == [1, 2, 3])
        #expect(!art.isWritingStroke(0) && art.isWritingStroke(1) && art.isWritingStroke(3) && !art.isWritingStroke(4))
        #expect(!art.isWritingStroke(-1) && !art.isWritingStroke(Int.max))
        // Writing is dark-paint writing where its region's paint is under `Template.darkPaintLightness`.
        #expect(!t.writesOnDarkPaint(stroke: 0) && t.writesOnDarkPaint(stroke: 1) && t.writesOnDarkPaint(stroke: 2))
        #expect(!t.writesOnDarkPaint(stroke: 3) && !t.writesOnDarkPaint(stroke: 4) && !t.writesOnDarkPaint(stroke: -1))
        // The chunk section after the payload (10078 bytes): its count (3), GENR (16), LINE (185:
        // its header and 173 bytes) and WRIT (28: its header, the count and the three strokes).
        let tags = try LineArtCodingTests.chunks(data, payloadEnd: 10078)
        #expect(tags.map(\.0) == [Template.Chunk.generator, Template.Chunk.lines, Template.Chunk.writing])
        #expect(tags.allSatisfy { $0.1 == 0 })
        #expect(data.suffix(28) == Data([
            0x57, 0x52, 0x49, 0x54, 0, 0, 0, 0, 16, 0, 0, 0, 3, 0, 0, 0, 1, 0, 0, 0, 2, 0, 0, 0, 3, 0, 0, 0,
        ]))
        expectValid(t)
        #expect(t.encoded() == data)
    }

    /// A template made from a photo with writing round-trips, the chunk written after LINE and
    /// only when there is writing: the strokes it marks are the letters, none of the drawing.
    @Test func roundTripsWritingStrokes() throws {
        let t = try WritingTests.book().template
        let art = try #require(t.lineArt)
        #expect(!art.writingStrokes.isEmpty)
        let scale = Float(t.width) / Float(WritingTests.size.w)
        let box = SIMD4<Float>(66, 88, 158, 124) * scale
        func inside(_ index: Int) -> Bool {
            let s = art.strokes[index]
            return art.strokePoints[Int(s.pointStart)..<Int(s.pointStart + s.pointCount)].allSatisfy {
                $0.x > box.x - 8 * scale && $0.x < box.z + 8 * scale && $0.y > box.y - 8 * scale && $0.y < box.w + 8 * scale
            }
        }
        for index in art.strokes.indices { #expect(inside(index) == art.isWritingStroke(index), "stroke \(index)") }
        let decoded = try Template(encoded: t.encoded())
        #expect(decoded == t && decoded.lineArt?.writingStrokes == art.writingStrokes)
        let tags = try LineArtCodingTests.chunks(t.encoded(), payloadEnd: LineArtCodingTests.chunkSectionStart(of: t))
        #expect(tags.map(\.0) == [Template.Chunk.generator, Template.Chunk.lines, Template.Chunk.writing])
        var none = t
        none.lineArt?.writingStrokes = []
        #expect(none.encoded().count == t.encoded().count - (12 + 4 + 4 * art.writingStrokes.count))
        #expect(try Template(encoded: none.encoded()).lineArt?.writingStrokes == [])
        // Without the writing in the photo the template has no WRIT chunk.
        let off = try WritingTests.book(keepWriting: false).template
        #expect(off.lineArt?.writingStrokes == [])
    }

    /// The chunk is optional: a reader that doesn't know it skips it. Known, it reads the same
    /// in any order, and fields a later writer appends to it are ignored.
    @Test func writingChunkIsOptional() throws {
        let t = try Template(encoded: TestFixtures.data("template-v2-writing.pbnt"))
        var generator = BinaryWriter()
        generator.write(t.pipelineVersion)
        var writing = BinaryWriter()
        writing.writeArray(t.lineArt!.writingStrokes)
        let lines = (tag: Template.Chunk.lines, flags: UInt32(0), payload: t.lineArt!.encoded())
        let reordered = LineArtCodingTests.file(
            t, chunks: [(Template.Chunk.writing, 0, writing.data), lines, (Template.Chunk.generator, 0, generator.data)])
        #expect(try Template(encoded: reordered) == t)
        let longer = LineArtCodingTests.file(
            t, chunks: [(Template.Chunk.generator, 0, generator.data), lines, (Template.Chunk.writing, 0, writing.data + Data([7, 0, 0, 0, 9]))])
        #expect(try Template(encoded: longer) == t)
        // Under another tag (a reader that doesn't know WRIT), the same painting drawn without
        // marking its writing.
        let unknown = LineArtCodingTests.file(
            t, chunks: [(Template.Chunk.generator, 0, generator.data), lines, (0x5858_5858, 0, writing.data)])
        let older = try Template(encoded: unknown)
        #expect(older.lineArt?.writingStrokes == [] && older.lineArt?.strokes == t.lineArt?.strokes && older.regions == t.regions)
    }

    /// Strokes out of range, out of order or twice, an empty or short list, a second chunk and a
    /// list with no line art to refer to are corrupt, never a crash or a newer reader's file.
    @Test func craftedWritingStrokesAreCorrupt() throws {
        let base = try Template(encoded: TestFixtures.data("template-v2-writing.pbnt"))
        let strokes = UInt32(base.lineArt!.strokes.count)
        for (name, list) in [
            ("past the strokes", [strokes]), ("far past", [UInt32.max]), ("descending", [3, 1]), ("twice", [1, 1]),
            ("after one past", [1, strokes]),
        ] as [(String, [UInt32])] {
            var t = base
            t.lineArt?.writingStrokes = list
            let error = #expect(throws: Template.CodingError.self, "\(name)") { try Template(encoded: t.encoded()) }
            #expect(error == .corrupt("writing strokes"), "\(name)")
            #expect(error?.requiresNewerReader == false, "\(name)")
        }
        var generator = BinaryWriter()
        generator.write(base.pipelineVersion)
        let lines = (tag: Template.Chunk.lines, flags: UInt32(0), payload: base.lineArt!.encoded())
        func file(_ writing: [Data], lines withLines: Bool = true) -> Data {
            LineArtCodingTests.file(
                base, chunks: [(Template.Chunk.generator, 0, generator.data)] + (withLines ? [lines] : [])
                    + writing.map { (Template.Chunk.writing, 0, $0) })
        }
        var one = BinaryWriter()
        one.writeArray([UInt32(1)])
        #expect(try Template(encoded: file([one.data])).lineArt?.writingStrokes == [1])
        #expect(throws: Template.CodingError.corrupt("duplicate chunk")) { try Template(encoded: file([one.data, one.data])) }
        #expect(throws: Template.CodingError.corrupt("WRIT")) { try Template(encoded: file([Data([0, 0, 0, 0])])) }
        #expect(throws: Template.CodingError.corrupt("WRIT")) { try Template(encoded: file([Data([2, 0, 0, 0, 1, 0, 0, 0])])) }
        #expect(throws: Template.CodingError.corrupt("WRIT")) { try Template(encoded: file([Data([0xFF, 0xFF, 0xFF, 0xFF])])) }
        #expect(throws: Template.CodingError.corrupt("WRIT")) { try Template(encoded: file([Data([1, 0])])) }
        #expect(throws: Template.CodingError.corrupt("WRIT")) { try Template(encoded: file([one.data], lines: false)) }
    }

    /// Random damage to the last chunks (LINE's end and WRIT; every prefix and damage anywhere
    /// are `TemplateCodingTests`') decodes to a template that is safe to use, or throws.
    @Test func damagedWritingChunk() throws {
        let data = try TestFixtures.data("template-v2-writing.pbnt")
        var rng = SplitMix64(seed: 0x771E)
        var decoded = 0
        for _ in 0..<2000 {
            var bytes = data
            for _ in 0..<(1 + Int(rng.next() % 3)) {
                let i = data.count - 1 - Int(rng.next() % 60)
                if rng.next() % 2 == 0 { bytes[i] ^= UInt8(1) << (rng.next() % 8) } else { bytes[i] = UInt8(truncatingIfNeeded: rng.next()) }
            }
            do {
                let t = try Template(encoded: bytes)
                decoded += 1
                TemplateCodingTests.exercise(t)
                for s in -1...(t.lineArt?.strokes.count ?? 0) {
                    _ = t.lineArt?.isWritingStroke(s)
                    _ = t.writesOnDarkPaint(stroke: s)
                }
                #expect(t.lineArt?.writingStrokes.allSatisfy { Int($0) < t.lineArt!.strokes.count } ?? true)
            } catch is Template.CodingError {
            } catch {
                Issue.record("unexpected error \(error)")
            }
        }
        #expect(decoded > 0 && decoded < 2000)
    }
}
