import Foundation
import Testing
@testable import PaintCore

/// The painter's fills (`LineEdit.Kind.fill`, `CellMap.fill`): detail areas of the photo's color,
/// on `LineArtTests`' scene (a 192 × 144 canvas, 1.5 × the photo) with a speck of magenta in
/// its sky, as small as the Annunciation's gold stars were for the painter who outlined them.
@Suite("Fills")
struct FillTests {
    /// The speck's photo pixels (x 99...101, y 11...13) and its centre on the canvas.
    static let speck = (x: 99...101, y: 11...13)
    static let magenta = SIMD4<UInt8>(220, 40, 170, 255)
    static let centre = SIMD2<Float>(150.75, 18.75)

    /// The scene's photo with the speck: the segmentation merges it into the sky.
    static func photo() -> RGBAImage {
        var photo = LineArtTests.photo()
        for y in speck.y { for x in speck.x { photo[x, y] = magenta } }
        return photo
    }

    /// A closed square outline round `centre` (canvas units), `side` across, as the pen draws it.
    static func outline(_ centre: SIMD2<Float>, side: Float) -> LineEdit {
        let h = side / 2
        let corners = [SIMD2(-h, -h), SIMD2(h, -h), SIMD2(h, h), SIMD2(-h, h), SIMD2(-h, -h)].map { centre + $0 }
        return LineEditsTests.draw(corners)
    }

    /// The painter's shape round the speck: a square 6 units across, whose cell (5 pixels
    /// across inside the line) is too small for a number unless it is a detail area.
    static func star() -> LineEdit { outline(centre, side: 6) }

    static func fill(_ point: SIMD2<Float>) -> LineEdit {
        LineEdit(kind: .fill, points: LineEditsTests.path([point]))
    }

    static func generate(_ edits: [LineEdit]) throws -> TemplateGenerator.Output {
        try LineArtTests.generate(LineArtTests.settings(), photo: photo(), input: LineArtInput(edges: LineArtTests.edges(), edits: edits))
    }

    /// The story: a small shape outlined round the speck has too little room for a number, so
    /// it goes back into the sky and only its outline is drawn (her stars were 15 units across,
    /// each needing a 3-digit number). Filled, it is an area of its own
    /// in a new paint of the speck's color (the palette had none within a just-noticeable
    /// difference), kept against every merge, with a number at least a detail area's floor;
    /// the template holds every invariant, at each region's own floor.
    @Test func aFilledShapeBecomesADetailArea() throws {
        let shape = Self.star()
        let outlined = try Self.generate([shape])
        let sky = try #require(outlined.template.region(at: SIMD2<Float>(100, 20)))
        #expect(outlined.template.region(at: Self.centre) == sky, "The outline closed a cell without a fill")
        #expect(outlined.template.detailRegions.isEmpty)

        let out = try Self.generate([shape, Self.fill(Self.centre)])
        let t = out.template
        expectValid(t)
        #expect(out.vectorStats.labelRoomUnmet == 0)
        let stats = try #require(out.lineArtStats)
        #expect(stats.fills == 1 && stats.fillPaints == 1 && stats.detailAreas == 1)
        let star = try #require(t.region(at: Self.centre))
        #expect(star != t.region(at: SIMD2<Float>(100, 20)))
        #expect(t.detailRegions == [UInt32(star)] && t.isDetailRegion(star))
        #expect(t.regions.count == outlined.template.regions.count + 1)
        #expect(t.palette.count == outlined.template.palette.count + 1)
        let paint = t.palette[Int(t.regions[star].colorIndex)].oklab
        let sampled = LineEdit.photoColor(at: Self.centre / LineEditsTests.canvas, in: Self.photo())
        #expect(ColorScience.distance(paint, sampled) < 1e-4)
        // The new paint comes last: no other paint's number changed.
        #expect(Int(t.regions[star].colorIndex) == t.palette.count - 1)
        #expect(Array(t.palette.dropLast()) == outlined.template.palette)
        let labels = t.labels(ofRegion: star)
        try #require(labels.count == 1)
        let digits = LabelSizing.digitCount(colorIndex: t.regions[star].colorIndex)
        #expect(labels.first!.radius >= LabelSizing.minimumRadius(digits: digits, detail: true) - 1e-3)
        #expect(t.regions[star].area < 60, "The area isn't the outlined shape: \(t.regions[star].area)")
    }

    /// A fill whose color a paint already has (within a just-noticeable difference) takes it:
    /// a shape outlined inside the yellow square and filled keeps the square's paint, and the
    /// palette is the same.
    @Test func aFillReusesAMatchingPaint() throws {
        let inside = SIMD2<Float>(135, 60)
        let shape = Self.outline(inside, side: 9)
        let outlined = try Self.generate([shape]).template
        let out = try Self.generate([shape, Self.fill(inside)])
        let t = out.template
        expectValid(t)
        #expect(out.lineArtStats?.fillPaints == 0)
        #expect(t.palette == outlined.palette)
        let filled = try #require(t.region(at: inside)), square = try #require(t.region(at: SIMD2<Float>(160, 85)))
        #expect(filled != square && t.isDetailRegion(filled) && !t.isDetailRegion(square))
        #expect(t.regions[filled].colorIndex == t.regions[square].colorIndex)
    }

    /// Fills take effect in order: a later fill of the same cell replaces an earlier one, here
    /// the sky's color at the shape's edge after the speck's, and the other way round.
    @Test func aLaterFillReplacesAnEarlierOne() throws {
        let shape = Self.outline(Self.centre, side: 9)
        let edge = Self.centre + SIMD2(-3, -3)
        let skyLast = try Self.generate([shape, Self.fill(Self.centre), Self.fill(edge)]).template
        let speckLast = try Self.generate([shape, Self.fill(edge), Self.fill(Self.centre)]).template
        for t in [skyLast, speckLast] { expectValid(t) }
        let skyRegion = try #require(skyLast.region(at: SIMD2<Float>(100, 20)))
        let skyPaint = skyLast.regions[skyRegion].colorIndex
        let a = try #require(skyLast.region(at: Self.centre)), b = try #require(speckLast.region(at: Self.centre))
        #expect(skyLast.detailRegions.count == 1 && speckLast.detailRegions.count == 1)
        #expect(skyLast.regions[a].colorIndex == skyPaint)
        let magenta = ColorScience.encodedToOKLab(SIMD3(220, 40, 170) / 255, space: .sRGB)
        #expect(ColorScience.distance(speckLast.palette[Int(speckLast.regions[b].colorIndex)].oklab, magenta) < 0.05)
    }

    /// A fill in a shape left open fills the cell around it, which shows at once: the sky, all
    /// of it, is a detail area of the sky's color.
    @Test func aFillInAnOpenShapeFillsTheCellAroundIt() throws {
        let plain = try Self.generate([]).template
        let t = try Self.generate([Self.fill(SIMD2(100, 20))]).template
        expectValid(t)
        let sky = try #require(t.region(at: SIMD2<Float>(100, 20)))
        #expect(t.detailRegions == [UInt32(sky)])
        #expect(t.regions.count == plain.regions.count && t.palette == plain.palette)
        #expect(t.regions[sky].colorIndex == plain.regions[plain.region(at: SIMD2<Float>(100, 20))!].colorIndex)
    }

    /// Without fills a template is as it was, with no detail areas and no `DETL` chunk; fills
    /// off the canvas keep nothing; the same fills give the same bytes.
    @Test func withoutFillsNothingChanges() throws {
        let shape = Self.star()
        let outlined = try Self.generate([shape]).template
        #expect(outlined.detailRegions.isEmpty)
        let off = try Self.generate([shape, LineEdit(kind: .fill, points: [SIMD2(1.4, -0.3)]), LineEdit(kind: .fill, points: [])])
        #expect(off.template == outlined)
        #expect(off.lineArtStats?.detailAreas == 0)
        let tags = try LineArtCodingTests.chunks(outlined.encoded(), payloadEnd: LineArtCodingTests.chunkSectionStart(of: outlined))
        #expect(!tags.map(\.0).contains(Template.Chunk.detail))
        let edits = [shape, Self.fill(Self.centre)]
        #expect(try Self.generate(edits).template.encoded() == Self.generate(edits).template.encoded())
    }

    /// The photo's color at a fill: the median of the pixels round it, so a speck of another
    /// color under the tap doesn't decide it; at the photo's edge the window is cut; a pixel
    /// that isn't opaque is read over white.
    @Test func photoColorIsTheMedianRoundThePoint() {
        var photo = RGBAImage(width: 40, height: 30, fill: SIMD4(30, 60, 200, 255))
        photo[20, 15] = SIMD4(255, 255, 0, 255)
        let blue = ColorScience.encodedToOKLab(SIMD3(30, 60, 200) / 255, space: .sRGB)
        let at = LineEdit.photoColor(at: SIMD2(20.5 / 40, 15.5 / 30), in: photo)
        #expect(ColorScience.distance(at, blue) < 1e-5)
        #expect(ColorScience.distance(LineEdit.photoColor(at: SIMD2(0, 0), in: photo), blue) < 1e-5)
        #expect(ColorScience.distance(LineEdit.photoColor(at: SIMD2(.nan, 2), in: photo), blue) < 1e-5)
        let clear = RGBAImage(width: 8, height: 8, fill: SIMD4(0, 0, 0, 0))
        #expect(abs(LineEdit.photoColor(at: SIMD2(0.5, 0.5), in: clear).x - 1) < 1e-3)
        // A larger photo reads a larger window: 3 × 3 pixels of yellow in a 4000-px photo's
        // 11 × 11 don't make the median.
        var large = RGBAImage(width: 4000, height: 20, fill: SIMD4(30, 60, 200, 255))
        for y in 9...11 { for x in 1999...2001 { large[x, y] = SIMD4(255, 255, 0, 255) } }
        #expect(ColorScience.distance(LineEdit.photoColor(at: SIMD2(2000.5 / 4000, 10.5 / 20), in: large), blue) < 1e-5)
    }

    /// A detail area's label is judged by its own floor: the filled shape's label, short of a
    /// floor scaled so it passes as a detail area, is cramped once the template no longer calls
    /// the region one.
    @Test func validationJudgesEachRegionByItsFloor() throws {
        let t = try Self.generate([Self.star(), Self.fill(Self.centre)]).template
        let star = try #require(t.region(at: Self.centre))
        let label = try #require(t.labels(ofRegion: star).first)
        let factor = LabelSizing.roomFactor(digits: LabelSizing.digitCount(colorIndex: t.regions[star].colorIndex))
        let free = Float(Template.outlineDistance(t.polygons(ofRegion: star), label.position))
        let ratio = LabelSizing.detailMinimumRadius / LabelSizing.minimumRadius
        // A floor the detail area meets only at its own scale.
        let floor = free / factor / ratio * 0.98
        #expect(t.validate(minLabelRadius: floor).crampedLabelRegions.allSatisfy { $0 != star })
        var plain = t
        plain.detailRegions = []
        #expect(plain.validate(minLabelRadius: floor).crampedLabelRegions.contains(star))
        #expect(t.validate(minLabelRadius: free / factor / ratio * 1.05).crampedLabelRegions.contains(star))
    }
}
