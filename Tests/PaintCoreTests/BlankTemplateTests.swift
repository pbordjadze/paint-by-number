import Foundation
import Testing
@testable import PaintCore

/// Refine's Blank start (`TemplateEditor.blank`): the photo as one area, which the painter cuts
/// with the Pen. On a 160 × 120 canvas over a 320 × 240 photo whose left half is red and right
/// half blue.
@Suite("Blank start")
struct BlankTemplateTests {
    typealias Edit = TemplateEditor.Edit

    static let width = 160, height = 120
    static let red = SIMD4<UInt8>(200, 60, 40, 255), blue = SIMD4<UInt8>(40, 90, 200, 255)

    /// The photo: red left of x = 160, blue from there on, so red left of x = 80 on the canvas.
    static func photo() -> RGBAImage {
        var photo = RGBAImage(width: 320, height: 240, fill: red)
        for y in 0..<240 { for x in 160..<320 { photo[x, y] = blue } }
        return photo
    }

    static func lab(_ c: SIMD4<UInt8>) -> SIMD3<Float> {
        ColorScience.encodedToOKLab(SIMD3(Float(c.x), Float(c.y), Float(c.z)) / 255, space: .sRGB)
    }

    static func blank() throws -> Template {
        try TemplateEditor.blank(width: width, height: height, photo: photo(), colorSpace: .displayP3)
    }

    static func paint(of r: Int, in t: Template) -> SIMD3<Float> { t.palette[Int(t.regions[r].colorIndex)].oklab }

    /// One area, its ring the canvas frame, one paint of the photo's color, its number at the
    /// centre with all the room there is, and a coloring book with nothing drawn.
    @Test func aBlankIsOneAreaOverTheCanvas() throws {
        let t = try Self.blank()
        expectValid(t)
        #expect(t.width == Self.width && t.height == Self.height && t.colorSpace == .displayP3)
        #expect(t.regions.count == 1 && t.palette.count == 1 && t.rings.count == 1 && t.detailRegions.isEmpty)
        #expect(t.edges.count == 1 && t.edges[0].right == BoundaryEdge.outside)
        #expect(Array(t.points(of: t.edges[0])) == [SIMD2(0, 0), SIMD2(160, 0), SIMD2(160, 120), SIMD2(0, 120), SIMD2(0, 0)])
        #expect(t.regions[0].area == 160 * 120)
        #expect(t.regionMap.storage.allSatisfy { $0 == 0 })
        let labels = t.labels(ofRegion: 0)
        try #require(labels.count == 1)
        #expect(labels.first!.position == SIMD2(80, 60) && labels.first!.radius == 60 && t.regions[0].inscribedRadius == 60)
        let art = try #require(t.lineArt)
        #expect(art.style == .coloringBook && art.edgeLayers == [LineLayer.color.rawValue] && art.edgeWeights == [0])
        #expect(art.strokes.isEmpty && art.strokePoints.isEmpty && art.writingStrokes.isEmpty)
        #expect(t.pipelineVersion == TemplateGenerator.pipelineVersion)
        #expect(t.palette[0].oklab == LineEdit.photoColor(ofRegion: 0, in: t, image: Self.photo()))
        #expect(t.palette[0] == PaletteColor(oklab: t.palette[0].oklab, space: .displayP3))

        let plain = try TemplateEditor.blank(width: 90, height: 60, photo: RGBAImage(width: 30, height: 20, fill: Self.blue), colorSpace: .sRGB)
        expectValid(plain)
        #expect(ColorScience.distance(plain.palette[0].oklab, Self.lab(Self.blue)) < 1e-5)
        let none = try TemplateEditor.blank(width: 90, height: 60, photo: RGBAImage(width: 0, height: 0, pixels: []), colorSpace: .sRGB)
        #expect(none.palette[0].oklab == SIMD3(1, 0, 0), "no photo, the paper's white")
    }

    @Test func aBlankRoundTrips() throws {
        let t = try Self.blank()
        let decoded = try Template(encoded: t.encoded())
        #expect(decoded == t)
        #expect(decoded.encoded() == t.encoded())
    }

    @Test func theSameInputsGiveTheSameBytes() throws {
        #expect(try Self.blank().encoded() == Self.blank().encoded())
        let green = RGBAImage(width: 8, height: 8, fill: SIMD4(30, 160, 60, 255))
        let other = try TemplateEditor.blank(width: Self.width, height: Self.height, photo: green, colorSpace: .displayP3)
        #expect(other.encoded() != (try Self.blank().encoded()))
    }

    /// A Pen line from the frame to the frame along the color change, read as the app reads it
    /// (`painted`), cuts the area in two, each in its half's color.
    @Test func aLineAlongTheColorChangeCutsTwoAreasInTheTwoColors() throws {
        let t = try Self.blank()
        let edit = TemplateEditor.painted(.draw(points: [SIMD2(80, -6), SIMD2(80, 126)]), on: t, photo: Self.photo())
        guard case .draw(_, false, let paints?) = edit else { Issue.record("not a painted draw: \(edit)"); return }
        #expect(paints.count == 2)
        let (u, outcome) = try TemplateEditorTests.apply(edit, to: t)
        #expect(outcome.regionsSplit == 1 && outcome.joins == 2 && u.regions.count == 2)
        let left = try TemplateEditorTests.region(u, 40, 60), right = try TemplateEditorTests.region(u, 120, 60)
        #expect(left != right && u.regions[left].colorIndex != u.regions[right].colorIndex)
        #expect(ColorScience.distance(Self.paint(of: left, in: u), Self.lab(Self.red)) <= SegmentationParameters.jnd)
        #expect(ColorScience.distance(Self.paint(of: right, in: u), Self.lab(Self.blue)) <= SegmentationParameters.jnd)
        // The photo's one paint, which neither side kept, leaves the palette: every number paints.
        #expect(u.palette.count == 2 && Set(u.regions.map(\.colorIndex)) == [0, 1])
        for y in 0..<Self.height {
            for x in 0..<Self.width { #expect(Int(u.regionMap[x, y]) == (x < 80 ? left : right), "pixel \(x), \(y)") }
        }
        // The cut is drawn: an outline from the frame to the frame, where the line was drawn.
        let art = try #require(u.lineArt)
        let cut = try #require(u.edges.indices.first { u.edges[$0].right != BoundaryEdge.outside })
        #expect(art.edgeLayers[cut] == LineLayer.outline.rawValue && art.edgeWeights[cut] == 255)
        #expect(Set(u.points(of: u.edges[cut])) == [SIMD2(80, 0), SIMD2(80, 120)])
        #expect(try TemplateEditorTests.apply(edit, to: t).0 == u)
    }

    /// A loop drawn inside cuts out an area of its own, a hole in the one around it.
    @Test func aClosedLoopInsideCutsOutAnArea() throws {
        let t = try Self.blank()
        let loop: [SIMD2<Float>] = [SIMD2(105, 45), SIMD2(135, 45), SIMD2(135, 75), SIMD2(105, 75)]
        let edit = TemplateEditor.painted(.draw(points: loop, closed: true), on: t, photo: Self.photo())
        let (u, outcome) = try TemplateEditorTests.apply(edit, to: t)
        #expect(outcome.regionsSplit == 1 && u.regions.count == 2)
        let inside = try TemplateEditorTests.region(u, 120, 60), around = try TemplateEditorTests.region(u, 20, 20)
        #expect(inside != around && u.regions[around].ringCount == 2 && u.regions[inside].ringCount == 1)
        #expect(abs(u.regions[inside].area - 900) < 1e-3)
        #expect(ColorScience.distance(Self.paint(of: inside, in: u), Self.lab(Self.blue)) <= SegmentationParameters.jnd)
    }

    /// The other tools work on a blank too: a fill makes the area a detail area, a look recolors
    /// its paint, and the erasers find no ink to take out.
    @Test func aFillAndALookApplyAndTheErasersFindNothing() throws {
        let t = try Self.blank()
        let green = SIMD3<Float>(0.6, -0.15, 0.1)
        let (filled, fill) = try TemplateEditorTests.apply(.fill(at: SIMD2(40, 60), color: green), to: t)
        #expect(fill.fills == 1 && filled.detailRegions == [0] && filled.palette.count == 2)
        #expect(ColorScience.distance(Self.paint(of: 0, in: filled), green) < 1e-6)
        let (looked, look) = try TemplateEditorTests.apply(TemplateEditor.look(.moonlit, strength: 1, on: t), to: t)
        #expect(look.changed && look.paintsChanged == 1 && looked.palette != t.palette && looked.regions == t.regions)

        let rub = [SIMD2<Float>(0, 0), SIMD2(160, 120), SIMD2(0, 120), SIMD2(160, 0)]
        for edit in [Edit.erase(path: rub, radius: 20), .eraseLine(at: SIMD2(80, 0)), .eraseLine(at: SIMD2(80, 60))] {
            let (u, outcome) = try TemplateEditor.apply(edit, to: t)
            #expect(!outcome.changed && outcome.declined == nil && u == t, "\(edit)")
        }
    }

    /// A canvas too thin for the usual number is a detail area; one too thin for any number, or
    /// with no size, is no blank.
    @Test func aThinCanvasIsADetailAreaAndOneThinnerIsNone() throws {
        let photo = Self.photo()
        let thin = try TemplateEditor.blank(width: 40, height: 3, photo: photo, colorSpace: .sRGB)
        expectValid(thin)
        #expect(thin.detailRegions == [0])
        for (w, h) in [(40, 2), (0, 10), (10, -1), (Lattice.maximumCanvas + 1, 10)] {
            #expect(throws: TemplateEditor.Failure.self, "\(w) × \(h)") {
                try TemplateEditor.blank(width: w, height: h, photo: photo, colorSpace: .sRGB)
            }
        }
    }
}
