import Foundation
import Testing
@testable import PaintCore

@Suite("Template coding")
struct TemplateCodingTests {

    // MARK: - Fixtures

    static func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    /// `Fixtures/template-v1.pbnt` was written by the format-1 encoder at commit ccbbabe with
    /// `pbn trace Fixtures/shapes.ppm <dir>`: a 40×28 flat-color image (white background, a
    /// red square with a blue hole, two green squares touching diagonally, a yellow stripe
    /// along the bottom border). It pins the v1 layout: never regenerate it.
    @Test func decodesV1Fixture() throws {
        let data = try Self.fixture("template-v1.pbnt")
        #expect(data.count == 5558)
        let t = try Template(encoded: data)
        #expect(t.width == 40 && t.height == 28)
        #expect(t.palette.count == 5)
        #expect(t.regions.count == 6)
        #expect(t.edges.count == 7)
        #expect(t.points.count == 86)
        #expect(t.labels.count == 6)
        #expect(t.mesh.indices.count == 146 * 3)
        let report = t.validate()
        #expect(report.isValid, "\(report)")

        // The region map is exactly the 4-connected components of the source's colors.
        let image = try Netpbm.read(Self.fixture("shapes.ppm"))
        var classOf: [UInt32: UInt32] = [:]
        var classes = [UInt32](repeating: 0, count: image.width * image.height)
        for i in classes.indices {
            let key = UInt32(image.pixels[i * 4]) << 16 | UInt32(image.pixels[i * 4 + 1]) << 8 | UInt32(image.pixels[i * 4 + 2])
            classes[i] = classOf[key] ?? { let c = UInt32(classOf.count); classOf[key] = c; return c }()
        }
        let components = ConnectedComponents.label(Grid(width: image.width, height: image.height, storage: classes))
        #expect(t.regionMap == components.labels)
        #expect(t.regions.map(\.colorIndex) == components.classOf)

        #expect(t.pipelineVersion == 0)
        // Re-encoding writes the current format: the same payload, then the extension chunks.
        let v2 = t.encoded()
        #expect(v2[4..<8] == Data([2, 0, 0, 0]))
        #expect(v2[8..<data.count] == data[8...])
        #expect(try Template(encoded: v2) == t)
    }

    /// `Fixtures/template-v2.pbnt` was written by the format-2 encoder at commit 84762fb from
    /// the v1 fixture's template with `pipelineVersion = 1` (`v1Template()` stamped, then
    /// `encoded()`): the v1 payload followed by one `GENR` chunk. It pins the v2 layout, the
    /// first one with extension chunks: never regenerate it.
    @Test func decodesV2Fixture() throws {
        let data = try Self.fixture("template-v2.pbnt"), v1 = try Self.fixture("template-v1.pbnt")
        #expect(data.count == 5578)
        #expect(data[4..<8] == Data([2, 0, 0, 0]))
        // The payload is the v1 payload byte for byte, then 1 chunk: "GENR", flags 0, 4 bytes.
        #expect(data[8..<v1.count] == v1[8...])
        #expect(data[v1.count...] == Self.uint32(1, Self.genr, 0, 4, 1))
        let t = try Template(encoded: data)
        #expect(t.pipelineVersion == 1)
        var expected = try Self.v1Template()
        expected.pipelineVersion = 1
        #expect(t == expected)
        #expect(t.validate().isValid)
    }

    static func v1Template() throws -> Template { try Template(encoded: fixture("template-v1.pbnt")) }

    /// The fixture's payload (everything after the 8-byte header).
    static func payload() throws -> Data { try fixture("template-v1.pbnt").dropFirst(8) }

    /// A format-2 file from the fixture's payload, with the given chunk section.
    static func v2(chunkCount: UInt32? = nil, _ chunks: [(tag: UInt32, flags: UInt32, payload: Data)], trailing: Data = Data()) throws -> Data {
        var w = BinaryWriter()
        w.write(Template.magic)
        w.write(UInt32(2))
        w.write(bytes: try payload())
        w.write(chunkCount ?? UInt32(chunks.count))
        for c in chunks {
            w.write(c.tag); w.write(c.flags); w.write(UInt32(c.payload.count)); w.write(bytes: c.payload)
        }
        w.write(bytes: trailing)
        return w.data
    }

    static func uint32(_ values: UInt32...) -> Data {
        var w = BinaryWriter()
        for v in values { w.write(v) }
        return w.data
    }

    static let genr: UInt32 = 0x524E_4547
    static let unknownTag: UInt32 = 0x5A5A_5858  // "XXZZ"

    // MARK: - Format 2

    @Test func roundTripsPipelineVersion() throws {
        var t = try Self.v1Template()
        t.pipelineVersion = 7
        let decoded = try Template(encoded: t.encoded())
        #expect(decoded == t)
        #expect(decoded.pipelineVersion == 7)
    }

    @Test func generatorStampsPipelineVersion() throws {
        var pixels = [UInt8](repeating: 255, count: 64 * 48 * 4)
        for y in 0..<48 {
            for x in 0..<64 where (x / 16 + y / 12) % 2 == 0 {
                let i = (y * 64 + x) * 4
                pixels[i] = 200; pixels[i + 1] = 40; pixels[i + 2] = UInt8(x * 3)
            }
        }
        let out = try TemplateGenerator().generate(from: RGBAImage(width: 64, height: 48, pixels: pixels), cancel: .none)
        #expect(out.template.pipelineVersion == TemplateGenerator.pipelineVersion)
        #expect(try Template(encoded: out.template.encoded()) == out.template)
    }

    @Test func skipsUnknownChunks() throws {
        let data = try Self.v2([
            (Self.unknownTag, 0, Data([1, 2, 3])),
            (Self.genr, 0, Self.uint32(9, 0xDEAD_BEEF, 0xFEED_FACE)),  // fields a later reader may know
            (Self.unknownTag + 1, 0xFFFF_FFFE, Data()),  // unknown flag bits are ignored
        ])
        let t = try Template(encoded: data)
        #expect(t.pipelineVersion == 9)
        var expected = try Self.v1Template()
        expected.pipelineVersion = 9
        #expect(t == expected)
    }

    @Test func requiredUnknownChunkNeedsNewerReader() throws {
        let error = #expect(throws: Template.CodingError.self) {
            try Template(encoded: Self.v2([(Self.genr, 0, Self.uint32(1)), (Self.unknownTag, 1, Data([0]))]))
        }
        #expect(error == .requiredExtension(Self.unknownTag))
        #expect(error?.requiresNewerReader == true)
    }

    @Test func malformedChunkSections() throws {
        let cases: [(String, Data, Template.CodingError)] = [
            ("duplicate", try Self.v2([(Self.genr, 0, Self.uint32(1)), (Self.genr, 0, Self.uint32(2))]), .corrupt("duplicate chunk")),
            ("short GENR", try Self.v2([(Self.genr, 0, Data([1, 0]))]), .corrupt("GENR")),
            ("trailing", try Self.v2([(Self.genr, 0, Self.uint32(1))], trailing: Data([0])), .corrupt("trailing bytes")),
            ("length past end", try Self.v2([(Self.genr, 0, Self.uint32(1))]).dropLast(1), .truncated),
            ("count past end", try Self.v2(chunkCount: 0xFFFF_FFFF, [(Self.genr, 0, Self.uint32(1))]), .truncated),
            ("count one too many", try Self.v2(chunkCount: 2, [(Self.genr, 0, Self.uint32(1))]), .truncated),
        ]
        for (name, data, expected) in cases {
            let error = #expect(throws: Template.CodingError.self, "\(name)") { try Template(encoded: data) }
            #expect(error == expected, "\(name)")
            #expect(error?.requiresNewerReader == false, "\(name)")
        }
        // An empty chunk section is fine: pipeline version unknown.
        #expect(try Template(encoded: Self.v2([])) == Self.v1Template())
    }

    @Test func versions() throws {
        var data = try Self.fixture("template-v1.pbnt")
        data[4] = 3
        let newer = #expect(throws: Template.CodingError.self) { try Template(encoded: data) }
        #expect(newer == .newerFormat(3))
        #expect(newer?.requiresNewerReader == true)

        data[4] = 0
        let zero = #expect(throws: Template.CodingError.self) { try Template(encoded: data) }
        #expect(zero == .corrupt("version"))

        data[4] = 1
        data[0] = 0
        let magic = #expect(throws: Template.CodingError.self) { try Template(encoded: data) }
        #expect(magic == .badMagic)
    }

    // MARK: - Damaged input

    /// Every proper prefix of a file is rejected with a `CodingError` (never a trap).
    @Test func truncationAtEveryOffset() throws {
        for name in ["template-v1.pbnt", "template-v2.pbnt", "template-v2-lines.pbnt"] {
            let data = try Self.fixture(name)
            for length in 0..<data.count {
                #expect(throws: Template.CodingError.self, "length \(length)") { try Template(encoded: data.prefix(length)) }
            }
        }
    }

    @Test func decodesDataSlices() throws {
        let data = try Self.v1Template().encoded()
        let slice = (Data([9, 9, 9]) + data + Data([7]))[3..<(3 + data.count)]
        #expect(slice.startIndex == 3)
        #expect(try Template(encoded: slice) == Self.v1Template())
    }

    /// Seeded random byte flips: every case throws a `CodingError` or decodes to a template
    /// whose accessors and `validate()` run without trapping.
    @Test(arguments: ["v1", "v2", "v2-lines", "blobs"])
    func randomCorruption(_ source: String) throws {
        let data: Data
        switch source {
        case "v1": data = try Self.fixture("template-v1.pbnt")
        case "v2": data = try Self.fixture("template-v2.pbnt")
        case "v2-lines": data = try Self.fixture("template-v2-lines.pbnt")
        default:
            let s = VectorizerTests.blobMap(width: 64, height: 48, colors: 6, cell: 8, noise: 0.01, seed: 5)
            data = try VectorizerTests.vectorize(s).encoded()
        }
        let cases = source == "blobs" ? 2000 : 3000
        var rng = SplitMix64(seed: 0xC0DE + UInt64(source.utf8.count))
        var decoded = 0
        for _ in 0..<cases {
            var bytes = data
            for _ in 0..<(1 + Int(rng.next() % 4)) {
                let i = Int(rng.next() % UInt64(bytes.count))
                // Mostly single-bit flips; sometimes a whole random byte (large counts, NaNs).
                if rng.next() % 2 == 0 { bytes[i] ^= UInt8(1) << (rng.next() % 8) } else { bytes[i] = UInt8(truncatingIfNeeded: rng.next()) }
            }
            do {
                let t = try Template(encoded: bytes)
                decoded += 1
                Self.exercise(t)
            } catch is Template.CodingError {
            } catch {
                Issue.record("unexpected error \(error)")
            }
        }
        // Flips in float payloads decode, so both paths are covered.
        #expect(decoded > 0 && decoded < cases)
    }

    static func exercise(_ t: Template) {
        for r in t.regions.indices {
            _ = t.polygons(ofRegion: r)
            _ = t.labels(ofRegion: r).count
        }
        for e in t.edges { _ = t.points(of: e).count }
        _ = t.regionCountsByColor
        for y in stride(from: -1, through: t.height, by: 3) {
            for x in stride(from: -1, through: t.width, by: 3) { _ = t.region(at: SIMD2(Float(x), Float(y))) }
        }
        _ = t.validate()
    }

    /// References that would index out of bounds, or wrap in `UInt32` arithmetic.
    @Test func craftedReferencesAreCorrupt() throws {
        let base = try Self.v1Template()
        let w = Float(base.width), h = Float(base.height)
        let mutations: [(String, (inout Template) -> Void)] = [
            ("pointStart near max", { $0.edges[0].pointStart = .max - 1 }),
            ("pointStart wraps", { $0.edges[0].pointStart = .max; $0.edges[0].pointCount = 3 }),
            ("single-point edge", { $0.edges[0].pointCount = 1 }),
            ("edge left", { $0.edges[0].left = UInt32($0.regions.count) }),
            ("edge right", { $0.edges[0].right = UInt32($0.regions.count) }),
            ("ring edge", { $0.ringEdges[0].edge = UInt32($0.edges.count) }),
            ("edgeStart max", { $0.rings[0].edgeStart = .max }),
            ("edgeStart wraps", { $0.rings[0].edgeStart = .max; $0.rings[0].edgeCount = 2 }),
            ("ringStart max", { $0.regions[0].ringStart = .max }),
            ("ring span wraps", { $0.regions[0].ringStart = .max; $0.regions[0].ringCount = 2 }),
            ("labelStart max", { $0.regions[0].labelStart = .max }),
            ("label span wraps", { $0.regions[0].labelStart = .max; $0.regions[0].labelCount = 2 }),
            ("indexStart max", { $0.regions[0].indexStart = .max }),
            ("index span wraps", { $0.regions[0].indexStart = .max - 2; $0.regions[0].indexCount = 6 }),
            ("index count not triangles", { $0.regions[0].indexCount -= 1 }),
            ("color index", { $0.regions[0].colorIndex = UInt32($0.palette.count) }),
            ("region area NaN", { $0.regions[0].area = .nan }),
            ("bounds past canvas", { $0.regions[0].bounds.maxX = Int32($0.width) + 1 }),
            ("bounds negative", { $0.regions[0].bounds.minY = -1 }),
            ("bounds reversed", { $0.regions[0].bounds = PixelBounds(minX: 5, minY: 0, maxX: 2, maxY: 4) }),
            ("label region", { $0.labels[0].region = UInt32($0.regions.count) }),
            ("label radius", { $0.labels[0].radius = .infinity }),
            ("label outside", { $0.labels[0].position = SIMD2(w + 1, 0) }),
            ("vertex region", { $0.mesh.vertexRegion[0] = UInt32($0.regions.count) }),
            ("vertex region count", { $0.mesh.vertexRegion.removeLast() }),
            ("mesh index", { $0.mesh.indices[0] = UInt32($0.mesh.vertices.count) }),
            ("mesh index count", { $0.mesh.indices.append(0) }),
            ("mesh vertex outside", { $0.mesh.vertices[0] = SIMD2(-1, 0) }),
            ("point NaN", { $0.points[0] = SIMD2(.nan, 0) }),
            ("point past width", { $0.points[0].x = w + 1 }),
            ("point above canvas", { $0.points[0].y = -1 }),
            ("point huge", { $0.points[0] = SIMD2(4e16, h) }),
            ("palette infinite", { $0.palette[0].rgb.x = .infinity }),
            ("palette NaN", { $0.palette[1].oklab.z = .nan }),
        ]
        for (name, mutate) in mutations {
            var t = base
            mutate(&t)
            let error = #expect(throws: Template.CodingError.self, "\(name)") { try Template(encoded: t.encoded()) }
            if case .corrupt = error {} else { Issue.record("\(name): \(String(describing: error))") }
        }

        // What the vectorizer emits for a region without an outer ring is fine.
        var empty = base
        empty.regions[0].bounds = .empty
        #expect(try Template(encoded: empty.encoded()) == empty)
    }

    /// Counts larger than the file throw before anything is allocated.
    @Test func hugeCountsAreTruncated() throws {
        let fixture = try Self.fixture("template-v1.pbnt"), t = try Self.v1Template()
        func patched(at offset: Int, _ values: UInt32...) -> Data {
            var data = fixture
            for (k, v) in values.enumerated() {
                withUnsafeBytes(of: v.littleEndian) { data.replaceSubrange((offset + 4 * k)..<(offset + 4 * k + 4), with: $0) }
            }
            return data
        }
        let paletteCount = 17
        let pointsCount = paletteCount + 4 + 24 * t.palette.count + 4 + 52 * t.regions.count
        #expect(patched(at: pointsCount, UInt32(t.points.count)) == fixture)

        for (name, data) in [("palette", patched(at: paletteCount, 0xFFFF_FFFF)), ("points", patched(at: pointsCount, 0xFFFF_FFFF)),
                             ("points one too many", patched(at: pointsCount, UInt32(t.points.count + 1)))] {
            let error = #expect(throws: Template.CodingError.self, "\(name)") { try Template(encoded: data) }
            #expect(error == .truncated, "\(name)")
        }

        // 8000 × 8000 is within the canvas cap, but the runs do not cover it: rejected
        // before the map is allocated.
        let error = #expect(throws: Template.CodingError.self) { try Template(encoded: patched(at: 8, 8000, 8000)) }
        if case .corrupt = error {} else { Issue.record("\(String(describing: error))") }
        let tooLarge = #expect(throws: Template.CodingError.self) { try Template(encoded: patched(at: 8, 0x7FFF_FFFF, 0x7FFF_FFFF)) }
        #expect(tooLarge == .corrupt("size"))
    }

    @Test func emptyBoundsHaveNoSize() {
        #expect(PixelBounds.empty.width < 0)
        #expect(PixelBounds.empty.height < 0)
        #expect(PixelBounds.empty.isEmpty)
    }
}
