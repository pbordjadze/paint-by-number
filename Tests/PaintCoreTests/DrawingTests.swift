import Foundation
import Testing
@testable import PaintCore

/// Start from a drawing: `DrawingScan`, `DrawingPalette` and the generator's drawing path
/// (`GenerationSettings.drawing`), on drawings made here: ink on paper, and the paper on a
/// table, askew and unevenly lit.
struct DrawingTests {
    /// A sheet of paper to draw on, ink black, the lines `pen` pixels wide.
    struct Sheet {
        var image: RGBAImage
        var pen: Float = 4

        init(width: Int, height: Int, paper: UInt8 = 250) {
            image = RGBAImage(width: width, height: height, fill: SIMD4(paper, paper, paper, 255))
        }

        mutating func ink(_ x: Int, _ y: Int, _ v: UInt8 = 20) {
            guard x >= 0, y >= 0, x < image.width, y < image.height else { return }
            let i = (y * image.width + x) * 4
            image.pixels[i] = v; image.pixels[i + 1] = v; image.pixels[i + 2] = v
        }

        /// A stroke from `a` to `b`.
        mutating func line(_ a: SIMD2<Float>, _ b: SIMD2<Float>, width: Float? = nil) {
            let r = (width ?? pen) / 2
            let lo = pointwiseMin(a, b) - SIMD2(repeating: r + 1), hi = pointwiseMax(a, b) + SIMD2(repeating: r + 1)
            let ab = b - a, l2 = simdLengthSquared(ab)
            for y in max(0, Int(lo.y))...min(image.height - 1, Int(hi.y)) {
                for x in max(0, Int(lo.x))...min(image.width - 1, Int(hi.x)) {
                    let p = SIMD2(Float(x), Float(y))
                    let t = l2 > 0 ? min(max(simdDot(p - a, ab) / l2, 0), 1) : 0
                    if simdLength(p - (a + ab * t)) <= r { ink(x, y) }
                }
            }
        }

        mutating func polyline(_ points: [SIMD2<Float>], closed: Bool = true) {
            for (a, b) in zip(points, points.dropFirst()) { line(a, b) }
            if closed, let first = points.first, let last = points.last { line(last, first) }
        }

        mutating func rectangle(_ x0: Float, _ y0: Float, _ x1: Float, _ y1: Float) {
            polyline([SIMD2(x0, y0), SIMD2(x1, y0), SIMD2(x1, y1), SIMD2(x0, y1)])
        }

        /// A circle outline, or a solid disc.
        mutating func circle(_ c: SIMD2<Float>, radius: Float, solid: Bool = false, gap: ClosedRange<Float>? = nil) {
            if solid {
                for y in Int(c.y - radius - 1)...Int(c.y + radius + 1) {
                    for x in Int(c.x - radius - 1)...Int(c.x + radius + 1)
                    where simdLength(SIMD2(Float(x), Float(y)) - c) <= radius { ink(x, y) }
                }
                return
            }
            let steps = Int(radius * 2)
            var points: [SIMD2<Float>] = []
            for k in 0...steps {
                let angle = Float(k) / Float(steps) * 2 * .pi
                if let gap, gap.contains(angle) {
                    if points.count > 1 { polyline(points, closed: false) }
                    points = []
                    continue
                }
                points.append(c + SIMD2(cos(angle), sin(angle)) * radius)
            }
            if points.count > 1 { polyline(points, closed: false) }
        }
    }

    /// A drawing of a rectangle, a circle and a solid disc on a 600 × 400 sheet.
    static func shapes() -> Sheet {
        var s = Sheet(width: 600, height: 400)
        s.rectangle(60, 60, 260, 340)
        s.circle(SIMD2(420, 150), radius: 80)
        s.circle(SIMD2(440, 310), radius: 45, solid: true)
        return s
    }

    static func settings(_ palette: DrawingPalette.Set = .crayons) -> GenerationSettings {
        GenerationSettings(drawing: DrawingSettings(palette: palette))
    }

    static func generate(_ image: RGBAImage, settings: GenerationSettings = settings()) throws -> TemplateGenerator.Output {
        try TemplateGenerator(settings: settings).generate(from: image, cancel: .none)
    }

    /// Pairs of 4-neighbouring regions.
    static func neighbours(of t: Template) -> Set<[UInt32]> {
        var pairs = Set<[UInt32]>()
        let m = t.regionMap
        for y in 0..<m.height {
            for x in 0..<m.width {
                let a = m[x, y]
                if x + 1 < m.width, m[x + 1, y] != a { pairs.insert([min(a, m[x + 1, y]), max(a, m[x + 1, y])]) }
                if y + 1 < m.height, m[x, y + 1] != a { pairs.insert([min(a, m[x, y + 1]), max(a, m[x, y + 1])]) }
            }
        }
        return pairs
    }

    @Test func eachShapeIsAnAreaAndASolidDiscIsInk() throws {
        let out = try Self.generate(Self.shapes().image)
        let t = out.template
        expectValid(t)
        #expect(t.regions.count == 4)
        #expect(t.lineArt?.style == .coloringBook)
        // The ground, the largest area, takes the set's first paint; the disc the ink.
        let largest = t.regions.indices.max { t.regions[$0].area < t.regions[$1].area }!
        #expect(t.palette[Int(t.regions[largest].colorIndex)] == DrawingPalette.colors(of: .crayons)[0])
        let disc = t.regionMap[440, 310]
        #expect(t.palette[Int(t.regions[Int(disc)].colorIndex)] == DrawingPalette.ink)
        #expect(t.regions[Int(t.regionMap[440, 310])].area > 5000, "the disc is the whole fill")
        #expect(t.palette.last == DrawingPalette.ink)
        // Every shape's area is bounded by drawn lines, no two neighbours alike.
        for pair in Self.neighbours(of: t) {
            #expect(t.regions[Int(pair[0])].colorIndex != t.regions[Int(pair[1])].colorIndex)
        }
        let drawn = t.lineArt!.edgeLayers.filter { $0 != LineLayer.color.rawValue }.count
        #expect(drawn > 0)
        #expect(t.lineArt!.edgeLayers.filter { $0 == LineLayer.color.rawValue }.count == 0)
    }

    @Test func theSameDrawingGivesTheSameBytes() throws {
        let image = Self.shapes().image
        let a = try Self.generate(image).template.encoded()
        let b = try Self.generate(image).template.encoded()
        #expect(a == b)
    }

    @Test func hatchingDrawsInsideItsAreaAndAGapStillCloses() throws {
        var s = Sheet(width: 600, height: 400)
        s.rectangle(40, 40, 300, 360)
        for k in 0..<20 { s.line(SIMD2(60, Float(60 + k * 14)), SIMD2(280, Float(60 + k * 14))) }
        // A circle with a gap of about 12 px in its outline.
        s.circle(SIMD2(450, 200), radius: 90, gap: 0.1...0.23)
        let out = try Self.generate(s.image)
        let t = out.template
        expectValid(t)
        #expect(t.regions.count == 3, "the ground, the hatched rectangle and the circle: \(t.regions.count)")
        #expect(t.regionMap[450, 200] != t.regionMap[10, 10], "the circle closed")
        #expect(t.lineArt!.strokes.count >= 15, "the hatching drawn inside: \(t.lineArt!.strokes.count) strokes")
    }

    @Test func aThickStrokeIsALineAndABlobIsAFill() throws {
        var s = Sheet(width: 600, height: 400)
        s.pen = 24
        s.line(SIMD2(40, 200), SIMD2(560, 200))
        s.circle(SIMD2(300, 90), radius: 50, solid: true)
        let solids = try DrawingScan.ink(of: s.image, width: 600, height: 400).solids
        #expect(solids[90 * 600 + 300])
        #expect(!solids[200 * 600 + 300])
        #expect(!solids[200 * 600 + 100])
    }

    @Test func aSheetOnATableIsFoundAndPulledSquare() throws {
        // The drawing on a 400 × 300 sheet, laid askew on a dark table, lit from one side.
        let sheet = Self.shapes()
        let w = 700, h = 600
        var photo = RGBAImage(width: w, height: h, fill: SIMD4(70, 50, 40, 255))
        let corners: [SIMD2<Float>] = [SIMD2(140, 110), SIMD2(560, 130), SIMD2(540, 470), SIMD2(120, 450)]
        let h0 = try #require(DrawingScan.homography(
            from: corners, to: [SIMD2(0, 0), SIMD2(600, 0), SIMD2(600, 400), SIMD2(0, 400)]))
        for y in 0..<h {
            for x in 0..<w {
                let p = SIMD3<Double>(Double(x), Double(y), 1)
                let q = SIMD3<Double>((h0[0] * p).sum(), (h0[1] * p).sum(), (h0[2] * p).sum())
                let sx = q.x / q.z, sy = q.y / q.z
                guard sx >= 0, sy >= 0, sx < 600, sy < 400 else { continue }
                let v = sheet.image[Int(sx), Int(sy)]
                let light = 0.6 + 0.4 * Float(x) / Float(w)
                let i = (y * w + x) * 4
                photo.pixels[i] = UInt8(Float(v.x) * light); photo.pixels[i + 1] = UInt8(Float(v.y) * light)
                photo.pixels[i + 2] = UInt8(Float(v.z) * light)
            }
        }
        let cleaned = try DrawingScan.clean(photo)
        #expect(cleaned.rectified)
        #expect(cleaned.corners.count == 4)
        for (found, truth) in zip(cleaned.corners, corners) {
            let d = simdLength(found * SIMD2(Float(w), Float(h)) - truth)
            #expect(d < 20, "corner \(found) vs \(truth / SIMD2(Float(w), Float(h)))")
        }
        let aspect = Float(cleaned.picture.width) / Float(cleaned.picture.height)
        #expect(abs(aspect - 1.5) < 0.1, "aspect \(aspect)")
        // Flat paper: the corners of the cleaned sheet are white, and the shapes are there.
        let corner = cleaned.picture[4, 4]
        #expect(corner.x > 240)
        let t = try Self.generate(cleaned.picture).template
        expectValid(t)
        #expect(t.regions.count == 4, "\(t.regions.count) areas")
    }

    @Test func aPlainSheetIsNotRectified() throws {
        let cleaned = try DrawingScan.clean(Self.shapes().image)
        #expect(!cleaned.rectified)
        #expect(cleaned.picture.width == 600 && cleaned.picture.height == 400)
        #expect(cleaned.picture[300, 200].x == 255, "paper comes out white")
        #expect(cleaned.picture[60, 200].x < 40, "ink stays ink")
    }

    @Test func thePaletteLaysNoTwoNeighboursAlike() throws {
        // A 6 × 6 chequerboard of areas, each its own region.
        let n = 6, cell = 20
        var labels = RegionMap(width: n * cell, height: n * cell, repeating: 0)
        for y in 0..<(n * cell) { for x in 0..<(n * cell) { labels[x, y] = UInt32((y / cell) * n + x / cell) } }
        let laid = DrawingPalette.assign(labels: labels, areaCount: n * n, set: .sea, paints: nil, seed: 1)
        #expect(laid.palette.count == DrawingPalette.paintCount(areas: n * n, available: 12))
        for y in 0..<n {
            for x in 0..<n {
                let a = Int(laid.regionColor[y * n + x])
                if x + 1 < n { #expect(a != Int(laid.regionColor[y * n + x + 1])) }
                if y + 1 < n { #expect(a != Int(laid.regionColor[(y + 1) * n + x])) }
            }
        }
        #expect(DrawingPalette.paintCount(areas: 3, available: 12) == DrawingPalette.minimumPaints)
        #expect(DrawingPalette.paintCount(areas: 300, available: 12) == 12)
        for set in DrawingPalette.Set.allCases {
            #expect(DrawingPalette.colors(of: set).count == 12)
            // Light paper first, nothing too dark for ink to read on.
            #expect(DrawingPalette.colors(of: set)[0].oklab.x > 0.95)
            #expect(DrawingPalette.colors(of: set).allSatisfy { $0.oklab.x > 0.45 })
        }
    }

    @Test func settingsWithoutADrawingEncodeAsBeforeAndDecodeTolerantly() throws {
        let plain = try JSONEncoder().encode(GenerationSettings())
        let keys = try #require(try JSONSerialization.jsonObject(with: plain) as? [String: Any])
        #expect(keys["drawing"] == nil)
        let decoded = try JSONDecoder().decode(GenerationSettings.self, from: plain)
        #expect(decoded.drawing == nil)

        let drawing = try JSONEncoder().encode(Self.settings(.earth))
        let back = try JSONDecoder().decode(GenerationSettings.self, from: drawing)
        #expect(back.drawing == DrawingSettings(palette: .earth))

        // A later app's set, or a drawing block this build can't read, is still a drawing.
        let later = Data(#"{"colorCount":24,"detail":0.5,"smoothness":0.5,"seed":1,"drawing":{"palette":"neon","paints":4}}"#.utf8)
        let laterSettings = try JSONDecoder().decode(GenerationSettings.self, from: later)
        #expect(laterSettings.drawing == DrawingSettings(palette: .crayons, paints: 4))
        let odd = Data(#"{"colorCount":24,"detail":0.5,"smoothness":0.5,"seed":1,"drawing":5}"#.utf8)
        #expect(try JSONDecoder().decode(GenerationSettings.self, from: odd).drawing == DrawingSettings())
        #expect(DrawingSettings(paints: 99).normalized.paints == 12)
        #expect(DrawingSettings(paints: 1).normalized.paints == DrawingPalette.minimumPaints)
    }

    @Test func aDrawingIsCancellable() throws {
        let counter = LockedCounter()
        let cancel = CancellationCheck { counter.increment() >= 3 }
        #expect(throws: CancellationError.self) {
            try TemplateGenerator(settings: Self.settings()).generate(from: Self.shapes().image, cancel: cancel)
        }
    }
}
