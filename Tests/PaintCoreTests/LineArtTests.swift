import Foundation
import Testing
@testable import PaintCore

@Suite("Layered line art")
struct LineArtTests {

    // MARK: - A synthetic scene

    static func fixture(_ name: String) -> Data {
        let url = Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures")!
        return try! Data(contentsOf: url)
    }

    /// `Fixtures/layered-photo.ppm`, 128×96: flat sky (150, 190, 230) over flat ground
    /// (90, 150, 70), the horizon at y = 48, a dark red disc (140, 30, 40) of radius 18 around
    /// (40, 48) and a yellow square (240, 200, 40) over x 80..<112, y 30..<62.
    static func photo() -> RGBAImage { try! Netpbm.read(fixture("layered-photo.ppm")) }

    /// `Fixtures/layered-edges.pgm`, the photo's lines as a learned detector draws them (soft:
    /// a Gaussian profile, σ = 2 px): 0.95 around the disc and the square, 0.9 along the
    /// horizon where it is visible, 0.62 across the ground at y = 80 (same paint on both
    /// sides) and 0.42 down the sky at x = 60 (likewise). Values are rounded to 8 bits.
    static func edges() -> EdgeMap {
        let image = try! Netpbm.read(fixture("layered-edges.pgm"))
        return EdgeMap(width: image.width, height: image.height, values: (0..<(image.width * image.height)).map { image.pixels[$0 * 4] })
    }

    static func settings(_ change: (inout LineArtSettings) -> Void = { _ in }) -> GenerationSettings {
        var lineArt = LineArtSettings(
            style: .layered, outlineThreshold: 0.8, detailThreshold: 0.5, textureThreshold: 0.3,
            minimumStrokeLength: 10, gapBridging: 6, lineSmoothing: 0.5)
        change(&lineArt)
        return GenerationSettings(colorCount: 8, detail: 0.5, lineArt: lineArt)
    }

    static func generate(
        _ settings: GenerationSettings = settings(), eyes: [[SIMD2<Float>]] = [], input: Bool = true
    ) throws -> TemplateGenerator.Output {
        try TemplateGenerator(settings: settings).generate(
            from: photo(), lineArt: input ? LineArtInput(edges: edges(), eyes: eyes) : nil, cancel: .none)
    }

    /// Length of edges per layer (outline, detail, texture, color).
    static func lengths(_ t: Template) -> [Float] {
        var out: [Float] = [0, 0, 0, 0]
        for (k, e) in t.edges.enumerated() {
            let p = t.points(of: e)
            for i in p.indices.dropFirst() { out[Int(t.lineArt!.edgeLayers[k])] += simdLength(p[i] - p[i - 1]) }
        }
        return out
    }

    // MARK: - Generation

    @Test func layeredTemplateIsValid() throws {
        let out = try Self.generate()
        let t = out.template
        let lines = try #require(t.lineArt)
        #expect(lines.edgeLayers.count == t.edges.count && lines.edgeWeights.count == t.edges.count)
        let report = t.validate(minLabelRadius: LabelSizing.minimumRadius)
        #expect(report.isValid, "\(report)")
        #expect(report.badLines == [])
        #expect(out.vectorStats.labelRoomUnmet == 0)
        let length = Self.lengths(t)
        // The disc, square and horizon are outlines; the ground's line is detail.
        #expect(length[0] > 300, "\(length)")
        #expect(length[1] > 150, "\(length)")
        let stats = try #require(out.lineArtStats)
        #expect(stats.cells == t.regions.count)
        // The detail line splits the ground's paint into two cells.
        #expect(t.regions.count > stats.segmentationRegions)
        #expect(out.segmentation.regionCount == t.regions.count)
    }

    @Test func classicIgnoresTheEdgeMap() throws {
        var classic = Self.settings()
        classic.lineArt.style = .classic
        let plain = try TemplateGenerator(settings: classic).generate(from: Self.photo(), cancel: .none)
        let given = try Self.generate(classic)
        #expect(given.template == plain.template)
        #expect(given.template.lineArt == nil && given.lineArtStats == nil)
        // Layered settings without an edge map give the classic template too.
        let missing = try Self.generate(Self.settings(), input: false)
        #expect(missing.template == plain.template)
    }

    @Test func deterministic() throws {
        let a = try Self.generate().template.encoded(), b = try Self.generate().template.encoded()
        #expect(a == b)
    }

    @Test func samePaintJoinsFollowTheSetting() throws {
        let joined = try Self.generate(Self.settings { $0.samePaint = .joinTexture }).template
        let split = try Self.generate(Self.settings { $0.samePaint = .split }).template
        let all = try Self.generate(Self.settings { $0.samePaint = .joinAllButOutlines }).template
        // The sky's texture line: one cell with the line inside it, or two cells.
        #expect(split.regions.count > joined.regions.count)
        #expect(joined.lineArt!.strokes.contains { $0.layer == LineLayer.texture.rawValue })
        #expect(split.lineArt!.strokes.isEmpty)
        // Joining across detail lines too also unites the ground's two cells.
        #expect(all.regions.count < joined.regions.count)
        #expect(all.lineArt!.strokes.contains { $0.layer == LineLayer.detail.rawValue })
        for t in [joined, split, all] {
            let report = t.validate(minLabelRadius: LabelSizing.minimumRadius)
            #expect(report.isValid, "\(report)")
        }
        // Interior strokes lie inside their cell, whose paint is on both sides.
        for s in joined.lineArt!.strokes {
            let p = joined.lineArt!.strokePoints[Int(s.pointStart) + Int(s.pointCount) / 2]
            #expect(joined.region(at: p) == Int(s.region))
        }
    }

    @Test func eyesAreOutlined() throws {
        // A diamond inside the yellow square (normalized to the photo).
        let c = SIMD2<Float>(96 / 128, 46 / 96)
        let rx: Float = 9 / 128, ry: Float = 7 / 96
        let eye: [SIMD2<Float>] = [SIMD2(c.x - rx, c.y), SIMD2(c.x, c.y - ry), SIMD2(c.x + rx, c.y), SIMD2(c.x, c.y + ry)]
        let with = try Self.generate(eyes: [eye])
        let without = try Self.generate()
        #expect(with.lineArtStats?.eyes == 1)
        #expect(with.template.regions.count > without.template.regions.count)
        let report = with.template.validate(minLabelRadius: LabelSizing.minimumRadius)
        #expect(report.isValid, "\(report)")
        // The diamond is drawn as an outline: outline edges run around its centre.
        let t = with.template
        let centre = SIMD2<Float>(c.x * Float(t.width), c.y * Float(t.height))
        var nearOutline: Float = 0
        for (k, e) in t.edges.enumerated() where t.lineArt!.edgeLayers[k] == LineLayer.outline.rawValue {
            let p = t.points(of: e)
            for i in p.indices.dropFirst() where simdLength(p[i] - centre) < 16 { nearOutline += simdLength(p[i] - p[i - 1]) }
        }
        #expect(nearOutline > 40, "\(nearOutline)")
        // Switched off, eyes are ignored.
        let off = try Self.generate(Self.settings { $0.outlineEyes = false }, eyes: [eye])
        #expect(off.template == without.template)
    }

    @Test func anEyeTooSmallForANumberIsStillDrawn() throws {
        // A diamond 3 units across inside the square: no room for a number, so its cell joins
        // the square and the contour is drawn inside it, closed.
        let c = SIMD2<Float>(96 / 128, 46 / 96)
        let rx: Float = 1 / 128, ry: Float = 1 / 96
        let eye: [SIMD2<Float>] = [SIMD2(c.x - rx, c.y), SIMD2(c.x, c.y - ry), SIMD2(c.x + rx, c.y), SIMD2(c.x, c.y + ry)]
        let t = try Self.generate(eyes: [eye]).template
        let lines = try #require(t.lineArt)
        let stroke = try #require(lines.strokes.first { $0.layer == LineLayer.outline.rawValue })
        let first = lines.strokePoints[Int(stroke.pointStart)]
        let last = lines.strokePoints[Int(stroke.pointStart + stroke.pointCount) - 1]
        #expect(first == last)
        #expect(t.region(at: first) == Int(stroke.region))
        #expect(t.validate(minLabelRadius: LabelSizing.minimumRadius).isValid)
    }

    @Test func mergingCloseColorsGivesFewerCells() throws {
        // A soft gradient band across the ground makes paint-only boundaries.
        var image = Self.photo()
        for y in 48..<96 {
            for x in 0..<128 where x < 80 || x >= 112 || y >= 62 {
                let dx = Float(x) - 40, dy = Float(y) - 48
                guard dx * dx + dy * dy > 18 * 18 else { continue }
                image[x, y] = SIMD4(UInt8(60 + x / 2), UInt8(130 + x / 4), 70, 255)
            }
        }
        func run(_ keep: Bool) throws -> Template {
            var s = Self.settings { $0.keepColorEdges = keep }
            s.colorCount = 16
            return try TemplateGenerator(settings: s).generate(
                from: image, lineArt: LineArtInput(edges: Self.edges()), cancel: .none).template
        }
        let kept = try run(true), merged = try run(false)
        #expect(merged.regions.count < kept.regions.count)
        #expect(merged.validate(minLabelRadius: LabelSizing.minimumRadius).isValid)
    }

    @Test func edgeMapAtAnotherResolution() throws {
        // A map at half the photo's size still lines up (it is resampled to the working size).
        let full = Self.edges()
        var half = [UInt8](repeating: 0, count: 64 * 48)
        for y in 0..<48 {
            for x in 0..<64 {
                let a = Int(full.values[2 * y * 128 + 2 * x]) + Int(full.values[2 * y * 128 + 2 * x + 1])
                let b = Int(full.values[(2 * y + 1) * 128 + 2 * x]) + Int(full.values[(2 * y + 1) * 128 + 2 * x + 1])
                half[y * 64 + x] = UInt8((a + b + 2) / 4)
            }
        }
        let t = try TemplateGenerator(settings: Self.settings()).generate(
            from: Self.photo(), lineArt: LineArtInput(edges: EdgeMap(width: 64, height: 48, values: half)), cancel: .none).template
        #expect(t.validate(minLabelRadius: LabelSizing.minimumRadius).isValid)
        #expect(Self.lengths(t)[0] > 300)
    }

    @Test func emptyEdgeMapKeepsTheCells() throws {
        let blank = EdgeMap(width: 128, height: 96, values: [UInt8](repeating: 0, count: 128 * 96))
        var classic = Self.settings()
        classic.lineArt.style = .classic
        let plain = try TemplateGenerator(settings: classic).generate(from: Self.photo(), cancel: .none).template
        let t = try TemplateGenerator(settings: Self.settings()).generate(
            from: Self.photo(), lineArt: LineArtInput(edges: blank), cancel: .none).template
        #expect(t.regions.count == plain.regions.count)
        #expect(t.lineArt!.edgeLayers.allSatisfy { $0 == LineLayer.color.rawValue })
        #expect(t.lineArt!.strokes.isEmpty)
        #expect(t.validate(minLabelRadius: LabelSizing.minimumRadius).isValid)
    }

    // MARK: - Stages

    @Test func layersByHysteresisAlongTheLine() {
        // Points 2.5 apart: a seed needs three points (5 units) at or above its threshold.
        let strength: [Float] = [0.2, 0.55, 0.9, 0.9, 0.9, 0.55, 0.45, 0.35, 0.2, 0.32, 0.35, 0.33, 0.1, 0.9, 0.1]
        let arc = strength.indices.map { Float($0) * 2.5 }
        let layer = LineLayering.classify(strength, arc: arc, closed: false, thresholds: [0.8, 0.5, 0.3])
        // The sustained 0.9 makes its run above 0.48 an outline; 0.45 and 0.35 are detail
        // (above 0.25, connected to the 0.55s, which reach 0.5 for 10 units with the 0.9s);
        // 0.2 to 0.33 are texture (above 0.15, seeded by 0.32–0.33); the lone 0.9 between
        // 0.1s is too short for any seed, and 0.1 is below every layer.
        #expect(layer == [2, 0, 0, 0, 0, 0, 1, 1, 2, 2, 2, 2, LineLayering.none, LineLayering.none, LineLayering.none])
    }

    @Test func crowdedLinesAreDetailUnlessLong() {
        // On a 1500-unit canvas: a short, strong stroke is an outline where nothing crowds it
        // and detail where lines crowd; a long one stays an outline either way.
        let w = 1500, h = 100
        func stroke(length: Int) -> StrokeGraph.Stroke {
            StrokeGraph.Stroke(
                points: (0..<length).map { SIMD2(Float(10 + $0), 50) }, strength: [Float](repeating: 0.95, count: length),
                closed: false, free: (true, true), links: [])
        }
        let calm = [Float](repeating: 0, count: w * h), crowded = [Float](repeating: 1, count: w * h)
        let thresholds: [Float] = [0.85, 0.5, 0.3]
        func layers(_ s: StrokeGraph.Stroke, _ clutter: [Float]) -> Set<UInt8> {
            Set(LineLayering.layered([s], thresholds: thresholds, clutter: clutter, width: w).flatMap(\.layer))
        }
        #expect(layers(stroke(length: 60), calm) == [LineLayer.outline.rawValue])
        #expect(layers(stroke(length: 60), crowded) == [LineLayer.detail.rawValue])
        #expect(layers(stroke(length: 200), crowded) == [LineLayer.outline.rawValue])
        // Half crowded: the threshold is halfway to 1, so 0.95 still makes an outline.
        let half = [Float](repeating: 0.5, count: w * h)
        #expect(layers(stroke(length: 60), half) == [LineLayer.outline.rawValue])
    }

    @Test func clutterCountsCrowdedLinesOnly() throws {
        // A 1500-unit canvas (crowding is measured relative to the canvas size): a lone line on
        // the left, lines 6 units apart on the right, 30 apart in the middle.
        let w = 1500, h = 200
        var mask = [Bool](repeating: false, count: w * h)
        for y in 0..<h { mask[y * w + 100] = true }
        for x in stride(from: 400, to: 800, by: 30) { for y in 0..<h { mask[y * w + x] = true } }
        for x in stride(from: 1000, to: 1400, by: 6) { for y in 0..<h { mask[y * w + x] = true } }
        let clutter = try LineDetection.clutter(mask, width: w, height: h, cancel: .none)
        #expect(clutter[100 * w + 100] == 0)
        #expect(clutter[100 * w + 610] < 0.05)
        #expect(clutter[100 * w + 1200] > 0.9)
    }

    @Test func linesAroundEyesAreStronger() {
        let w = 200, h = 100
        // A texture line passing just above an eye, and another far from it.
        func line(_ y: Float) -> DrawnLine {
            DrawnLine(points: (0..<180).map { SIMD2(Float(10 + $0), y) }, strength: [Float](repeating: 0.35, count: 180),
                      layer: [UInt8](repeating: LineLayer.texture.rawValue, count: 180), closed: false,
                      free: (true, true), links: [], eye: false)
        }
        let eye: [SIMD2<Float>] = [SIMD2(90, 50), SIMD2(100, 44), SIMD2(110, 50), SIMD2(100, 56)]
        let out = LineLayering.addEyes([line(40), line(90)], eyes: [eye], width: w, height: h)
        #expect(out.count == 3)
        let near = out[0], far = out[1]
        #expect(near.layer[90] == LineLayer.detail.rawValue)
        #expect(near.layer[0] == LineLayer.texture.rawValue)
        #expect(far.layer.allSatisfy { $0 == LineLayer.texture.rawValue })
        #expect(out[2].eye && out[2].closed && out[2].layer.allSatisfy { $0 == LineLayer.outline.rawValue })
    }

    @Test func layeredGenerationCancels() throws {
        // Cancelled after every number of checks up to the last: always a CancellationError.
        final class Counter: @unchecked Sendable {
            let lock = NSLock()
            var value = 0
            func next() -> Int { lock.withLock { value += 1; return value } }
        }
        let total = Counter()
        _ = try TemplateGenerator(settings: Self.settings()).generate(
            from: Self.photo(), lineArt: LineArtInput(edges: Self.edges()),
            cancel: CancellationCheck { _ = total.next(); return false })
        let checks = total.value
        #expect(checks > 20)
        for after in stride(from: 0, to: checks, by: max(1, checks / 25)) {
            let counter = Counter()
            #expect(throws: CancellationError.self, "after \(after)") {
                try TemplateGenerator(settings: Self.settings()).generate(
                    from: Self.photo(), lineArt: LineArtInput(edges: Self.edges()),
                    cancel: CancellationCheck { counter.next() > after })
            }
        }
    }

    @Test func thinningLeavesOnePixelLines() {
        let w = 40, h = 20
        var mask = [Bool](repeating: false, count: w * h)
        for y in 7..<12 { for x in 4..<36 { mask[y * w + x] = true } }
        Thinning.thin(&mask, width: w, height: h)
        // One pixel thick: no 2×2 block of set pixels.
        for y in 0..<(h - 1) {
            for x in 0..<(w - 1) {
                #expect(!(mask[y * w + x] && mask[y * w + x + 1] && mask[(y + 1) * w + x] && mask[(y + 1) * w + x + 1]))
            }
        }
        let count = mask.filter { $0 }.count
        #expect(count > 24 && count < 36)
    }

    @Test func gapsAreBridged() {
        // Two collinear strokes with a 5-pixel gap become one.
        let w = 60, h = 20
        var mask = [Bool](repeating: false, count: w * h)
        for x in 5..<25 { mask[10 * w + x] = true }
        for x in 30..<55 { mask[10 * w + x] = true }
        var g = StrokeGraph.trace(mask, strength: [Float](repeating: 1, count: w * h), width: w, height: h)
        g.mergeDegree2()
        #expect(g.components().count == 2)
        g.bridgeGaps(4)
        #expect(g.components().count == 2)
        g.bridgeGaps(7)
        #expect(g.components().count == 1)
        let strokes = g.strokes(sigma: 1)
        #expect(strokes.count == 1)
        #expect(strokes[0].free == (true, true))
    }

    // MARK: - Coding

    /// `Fixtures/template-v2-lines.pbnt` was written by the LINE encoder of commit 7ae42a1 with
    /// `pbn generate Fixtures/layered-photo.ppm <dir> --colors 8 --line-style layered --edges
    /// Fixtures/layered-edges.pgm --line-art outlineThreshold=0.8 --line-art detailThreshold=0.5
    /// --line-art textureThreshold=0.3 --line-art minimumStrokeLength=10 --line-art gapBridging=6`:
    /// the v1 payload, then a GENR and a LINE chunk (12 edges: 7 outline, 1 detail, 4 color; one
    /// texture stroke of 6 points inside the joined sky). It pins the LINE layout: never
    /// regenerate it.
    @Test func decodesLayeredFixture() throws {
        let data = Self.fixture("template-v2-lines.pbnt")
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
        let report = t.validate(minLabelRadius: LabelSizing.minimumRadius)
        #expect(report.isValid, "\(report)")
        // The chunk section: GENR then LINE (98 bytes), optional.
        let tags = try Self.chunks(data, payloadEnd: 11022)
        #expect(tags.map(\.0) == [Template.Chunk.generator, Template.Chunk.lines])
        #expect(tags.allSatisfy { $0.1 == 0 })
        // Re-encoding writes the same bytes.
        #expect(t.encoded() == data)
    }

    @Test func roundTripsLineArt() throws {
        let t = try Self.generate().template
        let decoded = try Template(encoded: t.encoded())
        #expect(decoded == t)
        #expect(decoded.lineArt == t.lineArt)
        // Without the chunk (an older writer, or classic) the same cells decode, drawn alike.
        var classic = t
        classic.lineArt = nil
        let plain = try Template(encoded: classic.encoded())
        #expect(plain.lineArt == nil && plain.regions == t.regions)
    }

    /// A file of `t`'s payload followed by `chunks`.
    static func file(_ t: Template, chunks: [(tag: UInt32, flags: UInt32, payload: Data)]) -> Data {
        var classic = t
        classic.lineArt = nil
        // The classic encoding ends with its one chunk (GENR: 12-byte header, 4-byte payload).
        let encoded = classic.encoded()
        var w = BinaryWriter()
        w.write(bytes: encoded.prefix(encoded.count - 4 - 16))
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
        let t = try Self.generate().template
        var classic = t
        classic.lineArt = nil
        let tags = try Self.chunks(t.encoded(), payloadEnd: classic.encoded().count - 4 - 16)
        #expect(tags.map(\.0) == [Template.Chunk.generator, Template.Chunk.lines])
        #expect(tags.allSatisfy { $0.1 & Template.Chunk.requiredFlag == 0 })
        // Written with the other chunks in any order, it reads the same.
        var generator = BinaryWriter()
        generator.write(t.pipelineVersion)
        let reordered = Self.file(t, chunks: [(Template.Chunk.lines, 0, t.lineArt!.encoded()), (Template.Chunk.generator, 0, generator.data)])
        #expect(try Template(encoded: reordered) == t)
        // A later writer may append fields to the chunk.
        let longer = Self.file(t, chunks: [(Template.Chunk.generator, 0, generator.data),
                                           (Template.Chunk.lines, 0, t.lineArt!.encoded() + Data([1, 2, 3]))])
        #expect(try Template(encoded: longer) == t)
    }

    @Test func truncatedLayeredFilesAreRejected() throws {
        let data = try Self.generate().template.encoded()
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
        let data = try Self.generate().template.encoded()
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
        let base = try Self.generate().template
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

    @Test func validationReportsBadLineData() throws {
        var t = try Self.generate().template
        #expect(t.validate().badLines == [])
        var classic = t
        classic.lineArt = nil
        #expect(classic.validate().badLines == nil)
        #expect(!classic.validate().description.contains("lines"))
        // A stroke moved to a region it does not touch.
        let stroke = t.lineArt!.strokes[0]
        let points = t.lineArt!.strokePoints[Int(stroke.pointStart)..<Int(stroke.pointStart + stroke.pointCount)]
        let far = t.regions.indices.first { r in
            points.allSatisfy { p in
                let x = Int(p.x), y = Int(p.y)
                return (max(0, y - 1)...min(t.height - 1, y + 1)).allSatisfy { yy in
                    (max(0, x - 1)...min(t.width - 1, x + 1)).allSatisfy { xx in t.regionMap[xx, yy] != UInt32(r) }
                }
            }
        }!
        t.lineArt!.strokes[0].region = UInt32(far)
        let report = t.validate()
        #expect(!report.isValid)
        #expect(report.badLines?.count == 1)
        #expect(report.description.contains("lines 1"))
    }
}
