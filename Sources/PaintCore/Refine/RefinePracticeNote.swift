import Foundation

/// The Tool Guide's practice picture for Writing (`RefinePractice` is every other page's): a
/// note on a wooden table beside a jar of honey. The note says "Back at six" and "Soup is hot" in
/// blue ink, with "feed the cat" under them in faint pencil; the jar's label is printed HONEY.
///
/// Unlike the evening, this picture is generated, as a painter's photo is: Writing's corrections
/// change what the generator traces, so its page has to make the template again as Refine does.
/// `lineArt` stands in for what the app's detectors would bring: an edge map of the picture's
/// outlines (the table's seams, the note, the jar, its lid and label) and, as text recognition
/// would find them, the boxes of the two inked lines and the label, but not the pencil line, so
/// the page has a line the app missed to mark.
///
/// Same inputs, same bytes: the photo and the maps are functions of nothing.
public enum RefinePracticeNote {
    public static let width = 1200
    public static let height = 900

    /// The lines of text, in pixels: their words, where they start, their baseline, the height of
    /// a capital, the pen, and the ink.
    struct Words {
        var text: String
        var x: Float
        var baseline: Float
        var size: Float
        var pen: Float
        var ink: SIMD3<Float>
        var printed = false
    }

    static let table = (top: srgb(0.62, 0.43, 0.27), bottom: srgb(0.5, 0.33, 0.2), seam: srgb(0.3, 0.19, 0.11))
    static let plank: Float = 180
    static let paper = (rect: SIMD4<Float>(100, 110, 730, 770), color: srgb(0.97, 0.94, 0.85))
    static let jar = (rect: SIMD4<Float>(800, 265, 1100, 800), top: srgb(0.93, 0.66, 0.2), bottom: srgb(0.74, 0.43, 0.1))
    static let lid = (rect: SIMD4<Float>(815, 200, 1085, 265), color: srgb(0.5, 0.31, 0.16))
    static let label = (rect: SIMD4<Float>(830, 450, 1070, 600), color: srgb(0.98, 0.97, 0.92))

    static let blueInk = srgb(0.13, 0.2, 0.48)
    static let pencil = srgb(0.6, 0.6, 0.58)

    /// The note's two inked lines, its pencil line, and the label.
    static let words: [Words] = [
        Words(text: "Back at six", x: 165, baseline: 285, size: 80, pen: 5, ink: blueInk),
        Words(text: "Soup is hot", x: 165, baseline: 455, size: 80, pen: 5, ink: blueInk),
        Words(text: "feed the cat", x: 170, baseline: 640, size: 72, pen: 3.5, ink: pencil),
        Words(text: "HONEY", x: 856, baseline: 552, size: 56, pen: 6, ink: srgb(0.12, 0.1, 0.09), printed: true),
    ]

    /// Which of `words` is the pencil line the app's text recognition missed.
    static let missed = 2

    /// The practice photo (sRGB), each pixel the average of 2 × 2 samples in linear light.
    public static func photo() -> RGBAImage {
        let strokes = words.map(Strokes.init)
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        let offsets: [Float] = [0.25, 0.75]
        pixels.withUnsafeMutableBufferPointer { buffer in
            let out = UncheckedSendable(buffer.baseAddress!)
            Parallel.forEachBand(height, minimumBandSize: 16) { rows in
                for y in rows {
                    for x in 0..<width {
                        var sum = SIMD3<Float>()
                        for sy in offsets {
                            for sx in offsets {
                                sum += color(at: SIMD2(Float(x) + sx, Float(y) + sy), strokes: strokes)
                            }
                        }
                        let c = sum / 4
                        let i = (y * width + x) * 4
                        out.value[i] = RefinePractice.encode(c.x)
                        out.value[i + 1] = RefinePractice.encode(c.y)
                        out.value[i + 2] = RefinePractice.encode(c.z)
                    }
                }
            }
        }
        return RGBAImage(width: width, height: height, pixels: pixels)
    }

    /// What the app's detectors would bring for the photo: its outlines as an edge map, and the
    /// lines of text recognition would find (all but the pencil line).
    public static func lineArt() -> LineArtInput {
        LineArtInput(edges: edges(), writing: foundText)
    }

    /// The boxes of the lines of text the app "found", normalized like `LineArtInput.writing`:
    /// "Back at six", "Soup is hot" and HONEY.
    public static var foundText: [[SIMD2<Float>]] {
        words.indices.filter { $0 != missed }.map { box(of: $0) }
    }

    /// The box around the pencil line, normalized: where a painter marks it.
    public static var missedText: [SIMD2<Float>] { box(of: missed) }

    /// A line of words' ink, grown by a fifth of its capital's height, as text recognition boxes
    /// it (corners clockwise from the top left).
    static func box(of index: Int) -> [SIMD2<Float>] {
        let bounds = Strokes(words[index]).bounds
        let grow = words[index].size * 0.2
        let w = Float(width), h = Float(height)
        let left = (bounds.x - grow) / w, top = (bounds.y - grow) / h
        let right = (bounds.z + grow) / w, bottom = (bounds.w + grow) / h
        return [SIMD2(left, top), SIMD2(right, top), SIMD2(right, bottom), SIMD2(left, bottom)]
    }

    // MARK: Drawing

    static func color(at p: SIMD2<Float>, strokes: [Strokes]) -> SIMD3<Float> {
        for stroke in strokes where stroke.inks(p) { return stroke.ink }
        if inside(p, label.rect) { return label.color }
        if inside(p, lid.rect) { return lid.color }
        if inside(p, jar.rect, corner: 40) {
            return RefinePractice.mix(jar.top, jar.bottom, (p.y - jar.rect.y) / (jar.rect.w - jar.rect.y))
        }
        if inside(p, paper.rect) { return paper.color }
        let inPlank = p.y.truncatingRemainder(dividingBy: plank)
        if p.y > plank / 2, inPlank < 3 { return table.seam }
        return RefinePractice.mix(table.top, table.bottom, p.y / Float(height))
    }

    static func inside(_ p: SIMD2<Float>, _ r: SIMD4<Float>, corner: Float = 0) -> Bool {
        guard p.x >= r.x, p.x <= r.z, p.y >= r.y, p.y <= r.w else { return false }
        guard corner > 0 else { return true }
        let cx = min(max(p.x, r.x + corner), r.z - corner), cy = min(max(p.y, r.y + corner), r.w - corner)
        return RefinePractice.distance(p, SIMD2(cx, cy)) <= corner
    }

    /// The outlines a contour detector would find, a little over a pixel wide.
    static func edges() -> EdgeMap {
        var values = [UInt8](repeating: 0, count: width * height)
        func stamp(_ a: SIMD2<Float>, _ b: SIMD2<Float>) {
            let length = RefinePractice.distance(a, b), steps = max(1, Int(length * 2))
            for k in 0...steps {
                let c = a + (b - a) * (Float(k) / Float(steps))
                for y in Int(c.y - 2)...Int(c.y + 2) where y >= 0 && y < height {
                    for x in Int(c.x - 2)...Int(c.x + 2) where x >= 0 && x < width {
                        let d = RefinePractice.distance(SIMD2(Float(x) + 0.5, Float(y) + 0.5), c)
                        let v = UInt8(max(0, min(255, 255 * (2 - d) / 1.2)))
                        values[y * width + x] = max(values[y * width + x], v)
                    }
                }
            }
        }
        func rect(_ r: SIMD4<Float>) {
            stamp(SIMD2(r.x, r.y), SIMD2(r.z, r.y))
            stamp(SIMD2(r.z, r.y), SIMD2(r.z, r.w))
            stamp(SIMD2(r.z, r.w), SIMD2(r.x, r.w))
            stamp(SIMD2(r.x, r.w), SIMD2(r.x, r.y))
        }
        // The seams, where the note and the jar don't cover them.
        var y = plank
        while y < Float(height) {
            let seamY = y + 1.5
            let covers = [paper.rect, jar.rect].filter { seamY >= $0.y && seamY <= $0.w }.sorted { $0.x < $1.x }
            var x: Float = 0
            for r in covers {
                if r.x > x { stamp(SIMD2(x, seamY), SIMD2(r.x, seamY)) }
                x = max(x, r.z)
            }
            if x < Float(width) { stamp(SIMD2(x, seamY), SIMD2(Float(width), seamY)) }
            y += plank
        }
        rect(paper.rect)
        rect(lid.rect)
        rect(label.rect)
        // The jar: its rounded outline, the lid across its top.
        let r = jar.rect, corner: Float = 40
        stamp(SIMD2(r.x, r.y + corner), SIMD2(r.x, r.w - corner))
        stamp(SIMD2(r.z, r.y + corner), SIMD2(r.z, r.w - corner))
        stamp(SIMD2(r.x + corner, r.y), SIMD2(r.z - corner, r.y))
        stamp(SIMD2(r.x + corner, r.w), SIMD2(r.z - corner, r.w))
        // Corners in image space (+y down): the angle runs clockwise on screen from `start`.
        for (center, start) in [
            (SIMD2(r.x + corner, r.w - corner), Float.pi / 2), (SIMD2(r.z - corner, r.w - corner), 0),
            (SIMD2(r.z - corner, r.y + corner), -Float.pi / 2), (SIMD2(r.x + corner, r.y + corner), Float.pi),
        ] {
            let points = (0...12).map { k in
                let angle = start + Float.pi / 2 * Float(k) / 12
                return center + corner * SIMD2(cos(angle), sin(angle))
            }
            for k in 1..<points.count { stamp(points[k - 1], points[k]) }
        }
        return EdgeMap(width: width, height: height, values: values)
    }

    /// A line of words as pen strokes in pixels, with each glyph's bounds for a quick look-up.
    struct Strokes {
        var ink: SIMD3<Float>
        var radius: Float
        /// Per glyph: its bounds grown by the pen (min x, min y, max x, max y) and its segments.
        var glyphs: [(bounds: SIMD4<Float>, segments: [(SIMD2<Float>, SIMD2<Float>)])] = []
        var bounds = SIMD4<Float>(.infinity, .infinity, -.infinity, -.infinity)

        init(_ words: Words) {
            ink = words.ink
            radius = words.pen / 2
            var x = words.x
            // A hand's slant and a little waver; print stands straight.
            let slant: Float = words.printed ? 0 : 0.16
            for (index, character) in words.text.enumerated() {
                let glyph = Glyph.of(character, printed: words.printed)
                var segments: [(SIMD2<Float>, SIMD2<Float>)] = []
                var glyphBounds = SIMD4<Float>(.infinity, .infinity, -.infinity, -.infinity)
                for stroke in glyph.strokes {
                    let points = stroke.map { p -> SIMD2<Float> in
                        let waver: Float = words.printed ? 0 : 0.025 * sin(Float(index) * 2.3 + p.x * 7)
                        let u = p.x + slant * p.y
                        return SIMD2(x + u * words.size, words.baseline - (p.y + waver) * words.size)
                    }
                    for point in points {
                        glyphBounds = SIMD4(
                            min(glyphBounds.x, point.x), min(glyphBounds.y, point.y),
                            max(glyphBounds.z, point.x), max(glyphBounds.w, point.y))
                    }
                    if points.count == 1 { segments.append((points[0], points[0])) }
                    for k in points.indices.dropFirst() { segments.append((points[k - 1], points[k])) }
                }
                if !segments.isEmpty {
                    bounds = SIMD4(
                        min(bounds.x, glyphBounds.x), min(bounds.y, glyphBounds.y),
                        max(bounds.z, glyphBounds.z), max(bounds.w, glyphBounds.w))
                    let r = radius + 1
                    glyphs.append((glyphBounds + SIMD4(-r, -r, r, r), segments))
                }
                x += glyph.advance * words.size
            }
        }

        func inks(_ p: SIMD2<Float>) -> Bool {
            for glyph in glyphs where p.x >= glyph.bounds.x && p.x <= glyph.bounds.z && p.y >= glyph.bounds.y && p.y <= glyph.bounds.w {
                for (a, b) in glyph.segments where Self.distance(p, a, b) <= radius { return true }
            }
            return false
        }

        static func distance(_ p: SIMD2<Float>, _ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float {
            let ab = b - a, length = (ab * ab).sum()
            let t = length > 0 ? min(max(((p - a) * ab).sum() / length, 0), 1) : 0
            return RefinePractice.distance(p, a + ab * t)
        }
    }

    /// A letter as pen strokes: units of a capital's height, origin on the baseline at the
    /// letter's left, +y up.
    struct Glyph {
        var strokes: [[SIMD2<Float>]]
        var advance: Float

        static let xHeight: Float = 0.55

        /// Points along an ellipse from `from` to `to` (radians, counterclockwise with +y up).
        static func arc(_ center: SIMD2<Float>, _ rx: Float, _ ry: Float, from: Float, to: Float, count: Int = 14) -> [SIMD2<Float>] {
            (0...count).map { k in
                let angle = from + (to - from) * Float(k) / Float(count)
                return center + SIMD2(rx * cos(angle), ry * sin(angle))
            }
        }

        static func degrees(_ d: Float) -> Float { d * .pi / 180 }

        // swiftlint:disable:next cyclomatic_complexity function_body_length
        static func of(_ character: Character, printed: Bool) -> Glyph {
            let h = xHeight
            let bowl = SIMD2<Float>(0.23, h / 2)
            switch (character, printed) {
            case (" ", _):
                return Glyph(strokes: [], advance: 0.35)
            case ("H", true):
                return Glyph(strokes: [[SIMD2(0, 1), SIMD2(0, 0)], [SIMD2(0.5, 1), SIMD2(0.5, 0)], [SIMD2(0, 0.5), SIMD2(0.5, 0.5)]], advance: 0.72)
            case ("O", true):
                return Glyph(strokes: [arc(SIMD2(0.3, 0.5), 0.3, 0.5, from: 0, to: 2 * .pi, count: 28)], advance: 0.78)
            case ("N", true):
                return Glyph(strokes: [[SIMD2(0, 0), SIMD2(0, 1), SIMD2(0.5, 0), SIMD2(0.5, 1)]], advance: 0.72)
            case ("E", true):
                return Glyph(strokes: [[SIMD2(0.45, 1), SIMD2(0, 1), SIMD2(0, 0), SIMD2(0.45, 0)], [SIMD2(0, 0.5), SIMD2(0.36, 0.5)]], advance: 0.62)
            case ("Y", true):
                return Glyph(strokes: [[SIMD2(0, 1), SIMD2(0.26, 0.5), SIMD2(0.52, 1)], [SIMD2(0.26, 0.5), SIMD2(0.26, 0)]], advance: 0.68)
            case ("B", _):
                return Glyph(strokes: [
                    [SIMD2(0.06, 1), SIMD2(0.06, 0)],
                    [SIMD2(0.06, 1), SIMD2(0.28, 1)] + arc(SIMD2(0.28, 0.76), 0.18, 0.24, from: degrees(90), to: degrees(-90))
                        + [SIMD2(0.06, 0.52)],
                    [SIMD2(0.06, 0.52), SIMD2(0.3, 0.52)] + arc(SIMD2(0.3, 0.26), 0.22, 0.26, from: degrees(90), to: degrees(-90))
                        + [SIMD2(0.06, 0)],
                ], advance: 0.62)
            case ("S", _):
                return Glyph(strokes: [[
                    SIMD2(0.42, 0.88), SIMD2(0.3, 1), SIMD2(0.14, 0.98), SIMD2(0.05, 0.85), SIMD2(0.09, 0.68), SIMD2(0.24, 0.56),
                    SIMD2(0.38, 0.45), SIMD2(0.45, 0.28), SIMD2(0.4, 0.1), SIMD2(0.25, 0), SIMD2(0.1, 0.03), SIMD2(0.02, 0.14),
                ]], advance: 0.56)
            case ("a", _):
                return Glyph(strokes: [arc(bowl, 0.2, h / 2, from: degrees(20), to: degrees(370)),
                                       [SIMD2(0.44, h), SIMD2(0.44, 0.04), SIMD2(0.5, 0)]], advance: 0.6)
            case ("c", _):
                return Glyph(strokes: [arc(bowl, 0.2, h / 2, from: degrees(40), to: degrees(320))], advance: 0.5)
            case ("d", _):
                return Glyph(strokes: [arc(bowl, 0.2, h / 2, from: degrees(20), to: degrees(370)),
                                       [SIMD2(0.44, 1), SIMD2(0.44, 0.04), SIMD2(0.5, 0)]], advance: 0.6)
            case ("e", _):
                return Glyph(strokes: [[SIMD2(0.04, h / 2), SIMD2(0.43, h / 2)]
                    + arc(bowl, 0.2, h / 2, from: 0, to: degrees(320))], advance: 0.54)
            case ("f", _):
                return Glyph(strokes: [arc(SIMD2(0.32, 0.86), 0.13, 0.13, from: degrees(20), to: degrees(180), count: 8)
                    + [SIMD2(0.19, 0)], [SIMD2(0.04, h), SIMD2(0.38, h)]], advance: 0.44)
            case ("h", _):
                return Glyph(strokes: [[SIMD2(0.06, 1), SIMD2(0.06, 0)],
                                       arc(SIMD2(0.25, h * 0.6), 0.19, h * 0.4, from: degrees(180), to: 0, count: 10)
                                           + [SIMD2(0.44, 0)]], advance: 0.56)
            case ("i", _):
                return Glyph(strokes: [[SIMD2(0.08, h), SIMD2(0.08, 0)], [SIMD2(0.09, h + 0.2)]], advance: 0.26)
            case ("k", _):
                return Glyph(strokes: [[SIMD2(0.06, 1), SIMD2(0.06, 0)], [SIMD2(0.4, h), SIMD2(0.06, 0.2), SIMD2(0.42, 0)]], advance: 0.5)
            case ("o", _):
                return Glyph(strokes: [arc(bowl, 0.2, h / 2, from: degrees(90), to: degrees(450), count: 20)], advance: 0.52)
            case ("p", _):
                return Glyph(strokes: [[SIMD2(0.06, h), SIMD2(0.06, -0.35)],
                                       arc(SIMD2(0.26, h / 2), 0.2, h / 2, from: degrees(160), to: degrees(-180), count: 18)],
                             advance: 0.56)
            case ("s", _):
                return Glyph(strokes: [[
                    SIMD2(0.36, h * 0.85), SIMD2(0.24, h), SIMD2(0.1, h * 0.92), SIMD2(0.08, h * 0.7), SIMD2(0.2, h * 0.55),
                    SIMD2(0.33, h * 0.45), SIMD2(0.39, h * 0.25), SIMD2(0.31, h * 0.05), SIMD2(0.17, 0), SIMD2(0.04, h * 0.12),
                ]], advance: 0.48)
            case ("t", _):
                return Glyph(strokes: [[SIMD2(0.15, 0.85), SIMD2(0.15, 0.06), SIMD2(0.3, 0)], [SIMD2(0.02, h), SIMD2(0.32, h)]], advance: 0.4)
            case ("u", _):
                return Glyph(strokes: [[SIMD2(0.06, h)] + arc(SIMD2(0.24, 0.18), 0.18, 0.18, from: degrees(180), to: degrees(360), count: 10)
                    + [SIMD2(0.42, h)], [SIMD2(0.42, h), SIMD2(0.42, 0)]], advance: 0.54)
            case ("x", _):
                return Glyph(strokes: [[SIMD2(0.03, h), SIMD2(0.4, 0)], [SIMD2(0.4, h), SIMD2(0.03, 0)]], advance: 0.48)
            default:
                preconditionFailure("the practice note has no glyph for \(character)")
            }
        }
    }

    static func srgb(_ r: Float, _ g: Float, _ b: Float) -> SIMD3<Float> { RefinePractice.srgb(r, g, b) }
}
