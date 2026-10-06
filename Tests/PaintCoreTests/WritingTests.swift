import Foundation
import Testing
@testable import PaintCore

@Suite("Writing")
struct WritingTests {

    // MARK: - A synthetic note

    /// A note: paper (40…320 × 40…170) on a brown ground, notebook rules every 30 px and a red
    /// margin at x = 290 across it, and a line of handwriting ("Hi you") 30 px high sitting on
    /// the rule at y = 120, as one pen's strokes; optionally a heart below it, speckle on the
    /// ground and an `Extra`.
    struct Note {
        var image: RGBAImage
        /// The letters' centrelines (pixels).
        var letters: [[SIMD2<Float>]]
        var heart: [SIMD2<Float>]
        var rules: [[SIMD2<Float>]]
        /// The extra's centreline, if it draws one.
        var extra: [SIMD2<Float>]
        /// The recognizer's box around the line, normalized.
        var area: [SIMD2<Float>]
    }

    /// Something that isn't writing: grain all over the paper under faint letters, the letters
    /// broken into dashes, a doodle hanging from the line's corner, a straight line under it.
    enum Extra { case none, grain, dashed, doodle, underline }

    static let size = (w: 360, h: 200)

    static func note(
        pen: Float = 3, chalk: Bool = false, rules: Bool = true, heart: Bool = false, speckle: Bool = false, extra: Extra = .none
    ) -> Note {
        let (w, h) = size
        let ground: SIMD3<Float> = chalk ? SIMD3(40, 70, 50) : SIMD3(120, 85, 60)
        let paper: SIMD3<Float> = chalk ? SIMD3(40, 70, 50) : SIMD3(240, 238, 230)
        let ink: SIMD3<Float> = chalk ? SIMD3(232, 232, 222) : extra == .grain ? paper * 0.55 : SIMD3(70, 70, 80)
        var pixels = [SIMD3<Float>](repeating: ground, count: w * h)
        var rng = SplitMix64(seed: 3)
        for y in 0..<h {
            for x in 0..<w {
                let onPaper = x >= 40 && x < 320 && y >= 40 && y < 170
                if onPaper || chalk {
                    pixels[y * w + x] = extra == .grain ? paper * (0.8 + 0.2 * rng.nextFloat()) : paper
                } else if speckle {
                    pixels[y * w + x] = ground * (rng.nextFloat() < 0.3 ? 0.55 : 1)
                }
            }
        }
        // Letters in units of the line height (y up from the baseline), then pixels.
        let unit: Float = 30, origin = SIMD2<Float>(70, 120)
        func at(_ points: [(Float, Float)]) -> [SIMD2<Float>] { points.map { origin + SIMD2($0.0 * unit, -$0.1 * unit) } }
        var circle: [(Float, Float)] = []
        for k in 0...24 { let a = Float(k) / 24 * 2 * .pi; circle.append((1.95 + 0.28 * cos(a), 0.3 + 0.3 * sin(a))) }
        let letters = [
            at([(0, 0), (0, 1)]), at([(0.5, 0), (0.5, 1)]), at([(0, 0.5), (0.5, 0.5)]),  // H
            at([(0.85, 0), (0.85, 0.6)]),  // i
            at([(1.15, 0.6), (1.3, 0.15)]), at([(1.5, 0.6), (1.25, -0.35)]),  // y
            at(circle),  // o
            at([(2.45, 0.6), (2.45, 0.15), (2.6, 0), (2.8, 0.15), (2.8, 0.6), (2.85, 0)]),  // u
        ]
        var heartLine: [SIMD2<Float>] = []
        for k in 0...40 {
            let t = Float(k) / 40 * 2 * .pi
            let x = 16 * pow(sin(t), 3), y = 13 * cos(t) - 5 * cos(2 * t) - 2 * cos(3 * t) - cos(4 * t)
            heartLine.append(SIMD2(110 + x * 0.6, 150 - y * 0.6))
        }
        func draw(_ line: [SIMD2<Float>], width: Float, color: SIMD3<Float>) {
            let r = width / 2
            for y in 0..<h {
                for x in 0..<w {
                    let p = SIMD2(Float(x), Float(y))
                    var d = Float.infinity
                    for k in line.indices.dropFirst() { d = min(d, Self.distance(p, line[k - 1], line[k])) }
                    let cover = min(max(r + 0.5 - d, 0), 1)
                    if cover > 0 { pixels[y * w + x] = pixels[y * w + x] * (1 - cover) + color * cover }
                }
            }
        }
        var ruleLines: [[SIMD2<Float>]] = []
        if rules && !chalk {
            for y in stride(from: 60, through: 150, by: 30) {
                let line = [SIMD2<Float>(40, Float(y)), SIMD2(319, Float(y))]
                ruleLines.append(line)
                draw(line, width: 1, color: SIMD3(196, 206, 224))
            }
            let margin = [SIMD2<Float>(290, 40), SIMD2(290, 169)]
            ruleLines.append(margin)
            draw(margin, width: 1.5, color: SIMD3(205, 95, 95))
        }
        if extra == .dashed {
            // Six pixels of ink, ten of paper, along every letter.
            for l in letters {
                for k in l.indices.dropFirst() {
                    let a = l[k - 1], b = l[k], length = simdLength(b - a)
                    var s: Float = 0
                    while s < length {
                        draw([a + (b - a) * (s / length), a + (b - a) * (min(s + 6, length) / length)], width: pen, color: ink)
                        s += 16
                    }
                }
            }
        } else {
            for l in letters { draw(l, width: pen, color: ink) }
        }
        draw([at([(0.85, 0.85)])[0], at([(0.86, 0.85)])[0]], width: pen + 1, color: ink)  // the i's dot
        if heart { draw(heartLine, width: pen, color: ink) }
        var extraLine: [SIMD2<Float>] = []
        switch extra {
        case .doodle:
            // From inside the core's corner along the paper past the zone's end, clear of the letters.
            extraLine = [SIMD2(163, 128), SIMD2(180, 138), SIMD2(197, 128), SIMD2(214, 138), SIMD2(231, 128)]
        case .underline:
            extraLine = [SIMD2(115, 128), SIMD2(165, 128)]
        case .none, .grain, .dashed:
            break
        }
        if !extraLine.isEmpty { draw(extraLine, width: pen, color: ink) }
        var bytes = [UInt8](repeating: 255, count: w * h * 4)
        for i in 0..<(w * h) {
            bytes[i * 4] = UInt8(pixels[i].x.rounded()); bytes[i * 4 + 1] = UInt8(pixels[i].y.rounded())
            bytes[i * 4 + 2] = UInt8(pixels[i].z.rounded())
        }
        let box: [SIMD2<Float>] = [SIMD2(66, 88), SIMD2(158, 88), SIMD2(158, 124), SIMD2(66, 124)]
        return Note(
            image: RGBAImage(width: w, height: h, pixels: bytes), letters: letters, heart: heartLine, rules: ruleLines,
            extra: extraLine, area: box.map { SIMD2($0.x / Float(w), $0.y / Float(h)) })
    }

    static func distance(_ p: SIMD2<Float>, _ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float {
        let ab = b - a
        let t = min(max(simdDot(p - a, ab) / max(simdLengthSquared(ab), 1e-6), 0), 1)
        return simdLength(p - (a + ab * t))
    }

    /// Share of the points along `lines` (every pixel) within `reach` of a point of `drawn`.
    static func covered(_ lines: [[SIMD2<Float>]], by drawn: [DrawnLine], within reach: Float, scale: Float = 1) -> Float {
        var total = 0, near = 0
        for line in lines {
            for k in line.indices.dropFirst() {
                let a = line[k - 1] * scale, b = line[k] * scale
                let steps = max(1, Int(simdLength(b - a)))
                for s in 0...steps {
                    let p = a + (b - a) * (Float(s) / Float(steps))
                    total += 1
                    if drawn.contains(where: { d in d.points.indices.dropFirst().contains { Self.distance(p, d.points[$0 - 1], d.points[$0]) <= reach } }) {
                        near += 1
                    }
                }
            }
        }
        return Float(near) / Float(max(total, 1))
    }

    static func find(_ note: Note, minRadius: Float = 3) throws -> (Writing, RGBAImage) {
        var image = note.image
        let found = try Writing.find(in: &image, areas: [note.area], minRadius: minRadius, cancel: .none)
        return (found, image)
    }

    // MARK: - Finding the writing

    @Test func tracesThePenAndLeavesTheRules() throws {
        let note = Self.note()
        let (found, painted) = try Self.find(note)
        #expect(found.areas == 1)
        #expect(found.report.map(\.verdict) == ["kept"])
        // Every letter is drawn, along its pen.
        let letters = Self.covered(note.letters, by: found.lines, within: 2.5)
        #expect(letters >= 0.9, "letters covered: \(letters)")
        // The rules and the margin aren't, away from the letters they touch.
        let away = note.rules.map { rule in
            rule.indices.dropFirst().flatMap { k -> [SIMD2<Float>] in
                let a = rule[k - 1], b = rule[k], steps = Int(simdLength(b - a))
                return (0...steps).map { a + (b - a) * (Float($0) / Float(steps)) }
            }.filter { p in !note.letters.contains { l in l.indices.dropFirst().contains { Self.distance(p, l[$0 - 1], l[$0]) < 8 } } }
        }
        let rules = Self.covered(away.map { $0.isEmpty ? [] : $0 }, by: found.lines, within: 1.5)
        #expect(rules <= 0.05, "rules drawn: \(rules)")
        // The ink is painted out: the paint sees paper where the letters were.
        let lightness = { (img: RGBAImage, p: SIMD2<Float>) -> Float in
            Writing.Lightness.lightness(img, x: Int(p.x.rounded()), y: Int(p.y.rounded()))
        }
        let paper = lightness(note.image, SIMD2(200, 105))
        let left = note.letters.joined().filter { abs(lightness(painted, $0) - paper) >= 0.08 }
        #expect(left.isEmpty, "ink left at \(left)")
        // Numbers keep off the writing: one rectangle holds every letter.
        #expect(found.keepOut.count == 1)
        let r = try #require(found.keepOut.first)
        #expect(note.letters.joined().allSatisfy { $0.x > r.x && $0.x < r.z && $0.y > r.y && $0.y < r.w })
        #expect(!found.nearInk.isEmpty)
    }

    @Test func aMarkBesideTheWritingComesAlongAndTheGroundDoesNot() throws {
        let note = Self.note(heart: true, speckle: true)
        let (found, _) = try Self.find(note)
        #expect(found.areas == 1 && found.marks == 1)
        #expect(Self.covered([note.heart], by: found.lines, within: 2.5) >= 0.85)
        // Nothing is drawn on the speckled ground beyond the paper.
        let offPaper = found.lines.flatMap(\.points).filter { $0.x < 38 || $0.x > 322 || $0.y < 38 || $0.y > 172 }
        #expect(offPaper.isEmpty, "\(offPaper.count) points off the paper")
    }

    @Test func boldWritingIsLeftToTheDetectors() throws {
        let note = Self.note(pen: 14)
        let (found, painted) = try Self.find(note)
        #expect(found.areas == 0 && found.lines.isEmpty && found.keepOut.isEmpty)
        #expect(found.report.map(\.verdict) == ["bold"])
        let unchanged = painted == note.image
        #expect(unchanged)
    }

    @Test func chalkOnABoardIsWritingToo() throws {
        let note = Self.note(pen: 4, chalk: true)
        let (found, _) = try Self.find(note)
        #expect(found.areas == 1)
        #expect(Self.covered(note.letters, by: found.lines, within: 2.5) >= 0.9)
    }

    @Test func tooSmallOrNoInkIsNoWriting() throws {
        var note = Self.note()
        // A box over blank paper: no ink.
        note.area = [SIMD2(0.6, 0.25), SIMD2(0.75, 0.25), SIMD2(0.75, 0.32), SIMD2(0.6, 0.32)].map { SIMD2($0.x, $0.y) }
        #expect(try Self.find(note).0.report.map(\.verdict) == ["noInk"])
        // A box lower than the smallest writing drawn.
        note.area = [SIMD2(0.2, 0.5), SIMD2(0.4, 0.5), SIMD2(0.4, 0.52), SIMD2(0.2, 0.52)]
        let (found, painted) = try Self.find(note)
        let unchanged = painted == note.image
        #expect(found.report.map(\.verdict) == ["size"] && unchanged)
    }

    @Test func findingIsDeterministic() throws {
        let note = Self.note(heart: true, speckle: true)
        let (a, imageA) = try Self.find(note)
        let (b, imageB) = try Self.find(note)
        let same = a.lines.map(\.points) == b.lines.map(\.points) && a.keepOut == b.keepOut && imageA == imageB
        #expect(same)
    }

    // MARK: - Telling writing from what surrounds it

    @Test func aLineBoxedTwiceIsTracedOnce() throws {
        let note = Self.note()
        let (single, _) = try Self.find(note)
        // A box over the first word too, as a recognizer boxing words and lines would: the word's
        // area takes "Hi", leaves "you" to the line (its box holds it), and the line traces only
        // what the word left.
        let word = [SIMD2<Float>(66, 88), SIMD2(100, 88), SIMD2(100, 124), SIMD2(66, 124)].map {
            SIMD2($0.x / Float(Self.size.w), $0.y / Float(Self.size.h))
        }
        var image = note.image
        let both = try Writing.find(in: &image, areas: [word, note.area], minRadius: 3, cancel: .none)
        #expect(both.areas == 2)
        #expect(Self.covered(note.letters, by: both.lines, within: 2.5) >= 0.9)
        let length = { (w: Writing) in w.lines.reduce(Float(0)) { $0 + StrokeGraph.length($1.points, closed: $1.closed) } }
        #expect(abs(length(both) - length(single)) <= 0.1 * length(single), "\(length(both)) drawn against \(length(single))")
    }

    @Test func aDrawingTheWritingTouchesIsNotWriting() throws {
        for extra in [Extra.doodle, .underline] {
            let note = Self.note(extra: extra)
            let (found, _) = try Self.find(note)
            #expect(found.areas == 1, "\(extra)")
            #expect(Self.covered(note.letters, by: found.lines, within: 2.5) >= 0.9, "\(extra)")
            let drawn = Self.covered([note.extra], by: found.lines, within: 2.5)
            #expect(drawn <= 0.05, "\(extra): \(drawn) of it drawn")
        }
    }

    @Test func writingOnAGrainyGroundOrBrokenIntoCrumbsIsTexture() throws {
        for extra in [Extra.grain, .dashed] {
            let note = Self.note(extra: extra)
            let (found, painted) = try Self.find(note)
            #expect(found.report.map(\.verdict) == ["texture"], "\(extra)")
            let unchanged = found.lines.isEmpty && painted == note.image
            #expect(unchanged, "\(extra)")
        }
    }

    // MARK: - In a template

    /// The note as a coloring book: its paper's outline as the detectors would draw it.
    static func book(keepWriting: Bool = true) throws -> TemplateGenerator.Output {
        let note = Self.note()
        let (w, h) = size
        var values = [UInt8](repeating: 0, count: w * h)
        for y in 0..<h {
            for x in 0..<w {
                let d = min(abs(Float(x) - 40), abs(Float(x) - 319), abs(Float(y) - 40), abs(Float(y) - 169))
                let inside = x >= 38 && x <= 321 && y >= 38 && y <= 171
                if inside { values[y * w + x] = UInt8((0.95 * exp(-d * d / 8) * 255).rounded()) }
            }
        }
        var lineArt = LineArtSettings(style: .coloringBook)
        lineArt.keepWriting = keepWriting
        let settings = GenerationSettings(colorCount: 8, detail: 0.3, lineArt: lineArt)
        let input = LineArtInput(edges: EdgeMap(width: w, height: h, values: values), writing: [note.area])
        return try TemplateGenerator(settings: settings).generate(from: note.image, lineArt: input, cancel: .none)
    }

    @Test func aBookDrawsTheWritingInsideItsCellsWithTheNumbersOffIt() throws {
        let out = try Self.book()
        let t = out.template
        expectValid(t)
        #expect(out.lineArtStats?.writingAreas == 1)
        let scale = Float(t.width) / Float(Self.size.w)
        let art = try #require(t.lineArt)
        let strokes = art.strokes.map { s in
            DrawnLine(
                points: Array(art.strokePoints[Int(s.pointStart)..<Int(s.pointStart + s.pointCount)]).map { $0 - SIMD2(0.5, 0.5) },
                strength: [], layer: [], closed: false, free: (false, false), links: [], eye: false)
        }
        #expect(Self.covered(Self.note().letters, by: strokes, within: 2.5 * scale, scale: scale) >= 0.85)
        // The letters are ink, not areas: no region lies within the writing.
        let box = SIMD4<Float>(66, 88, 158, 124) * scale
        #expect(t.regions.allSatisfy { r in
            let b = r.bounds
            return !(Float(b.minX) > box.x && Float(b.maxX) < box.z && Float(b.minY) > box.y && Float(b.maxY) < box.w)
        })
        // And no number sits on them.
        for label in t.labels {
            let p = label.position
            #expect(!(p.x > box.x && p.x < box.z && p.y > box.y && p.y < box.w), "a number at \(p) on the writing")
        }
        // The same template every time.
        let again = try Self.book().template == t
        #expect(again)
        // Switched off, there is no writing.
        let off = try Self.book(keepWriting: false)
        let differs = off.template != t
        #expect(off.lineArtStats?.writingAreas == 0 && differs)
    }

    // MARK: - Keeping numbers off

    @Test func aLabelMovesOffTheWritingWhereItsRegionHasRoom() {
        var poly = FlatPolygon()
        poly.points = [SIMD2(0, 0), SIMD2(100, 0), SIMD2(100, 60), SIMD2(0, 60)]
        poly.closeRing()
        let keepOut = LabelKeepOut(rects: [SIMD4(10, 20, 90, 40)])
        let plain = PolyLabel.find(poly, precision: 0.25, seed: SIMD2(50, 30))
        #expect(keepOut.distance(plain.position.x, plain.position.y) < 0)
        let moved = PolyLabel.find(poly, precision: 0.25, seed: SIMD2(50, 30), keepOut: keepOut)
        // Above or below the writing: a band 20 high leaves a radius of 10.
        #expect(abs(moved.distance - 10) < 0.3, "\(moved)")
        #expect(keepOut.distance(moved.position.x, moved.position.y) >= moved.distance - 1e-6)
        #expect(LabelKeepOut(rects: []).distance(5, 5) == .infinity)
    }

    // MARK: - Settings

    @Test func keepWritingIsOnUnlessSaidOtherwise() throws {
        #expect(LineArtSettings().keepWriting && LineArtSettings(style: .layered).keepWriting)
        let decoded = try JSONDecoder().decode(LineArtSettings.self, from: Data(#"{"style":"coloringBook"}"#.utf8))
        #expect(decoded.keepWriting)
        var off = LineArtSettings()
        off.keepWriting = false
        #expect(try JSONDecoder().decode(LineArtSettings.self, from: JSONEncoder().encode(off)) == off)
    }
}
