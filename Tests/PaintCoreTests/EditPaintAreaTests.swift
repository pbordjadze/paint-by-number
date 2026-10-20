import Foundation
import Testing
@testable import PaintCore

/// Refine's Only This Area (`TemplateEditor.Edit.paintArea`): one area takes another paint, the
/// one a fill would, and nothing else changes; a paint it leaves with no area goes, the numbers
/// after it closing up; an area it then shares a paint with across an undrawn boundary joins it.
/// On the editor's scene (`TemplateEditorTests`: sky above y ≈ 72, each of its four regions the
/// only area of its paint) with two boxes drawn in the sky, and on the crowded book
/// (`TemplateEditorTests.rich`) for an area too cramped for two digits.
@Suite("Edit paint area")
struct EditPaintAreaTests {
    typealias Edit = TemplateEditor.Edit

    static let scene = TemplateEditorTests.scene
    /// Two boxes in the sky, crossing nothing, and a point inside each.
    static let boxA: [SIMD2<Float>] = [SIMD2(90, 12), SIMD2(112, 12), SIMD2(112, 28), SIMD2(90, 28)]
    static let boxB: [SIMD2<Float>] = [SIMD2(130, 12), SIMD2(152, 12), SIMD2(152, 28), SIMD2(130, 28)]
    static let inA = SIMD2<Float>(101, 20), inB = SIMD2<Float>(141, 20)
    /// The sky above the split, and below it.
    static let upper = SIMD2<Float>(100, 5), lower = SIMD2<Float>(100, 50)
    static let ground = SIMD2<Float>(100, 130), square = SIMD2<Float>(144, 69)
    static let magenta = SIMD3<Float>(0.62, 0.2, -0.1)

    /// The scene with the boxes drawn, two small areas of the sky's paint, and the sky split below
    /// them at y = 40, both sides read in the sky's color: the lower sky, the smaller, took a shade
    /// of it across the split's undrawn boundary, a paint of its own added last.
    static let base: Template = {
        let sky = scene.palette[Int(scene.regions[scene.region(at: upper)!].colorIndex)].oklab
        let edits: [Edit] = [
            .draw(points: boxA, closed: true), .draw(points: boxB, closed: true),
            .split(points: [SIMD2(0, 40), SIMD2(192, 40)], paints: [.init(at: upper, color: sky), .init(at: lower, color: sky)]),
        ]
        return try! TemplateEditor.apply(edits, to: scene).template
    }()

    static func region(_ t: Template, _ p: SIMD2<Float>) throws -> Int { try TemplateEditorTests.region(t, p.x, p.y) }

    static func paint(_ t: Template, _ p: SIMD2<Float>) throws -> SIMD3<Float> {
        t.palette[Int(t.regions[try region(t, p)].colorIndex)].oklab
    }

    @Test func theBaseHasTwoBoxesOfTheSkysPaint() throws {
        let t = Self.base
        let sky = try Self.region(t, Self.upper), a = try Self.region(t, Self.inA), b = try Self.region(t, Self.inB)
        let below = try Self.region(t, Self.lower)
        #expect(Set([sky, a, b, below]).count == 4)
        #expect(t.regions[a].colorIndex == t.regions[sky].colorIndex && t.regions[b].colorIndex == t.regions[sky].colorIndex)
        #expect(t.palette.count == Self.scene.palette.count + 1 && Int(t.regions[below].colorIndex) == Self.scene.palette.count)
        #expect(t.detailRegions.isEmpty)
        expectValid(t)
    }

    /// One box takes a new paint, added last; every other region, its numbers, every paint and
    /// the drawing are as they were, bit for bit.
    @Test func oneAreaTakesANewPaintAndNothingElseChanges() throws {
        let t = Self.base
        let a = try Self.region(t, Self.inA)
        let (u, outcome) = try TemplateEditorTests.apply(.paintArea(at: Self.inA, color: Self.magenta), to: t)
        #expect(outcome.changed && outcome.recolored == 1 && outcome.paintsAdded == 1)
        #expect(outcome.paintsMerged == 0 && outcome.regionsMerged == 0 && outcome.fills == 0 && outcome.detailAreas == 0)
        #expect(u.palette == t.palette + [PaletteColor(oklab: Self.magenta, space: t.colorSpace)])
        #expect(Int(u.regions[a].colorIndex) == t.palette.count && !u.isDetailRegion(a))
        #expect(outcome.touchedRegions == [a] && outcome.continued == Array(t.regions.indices))
        #expect(u.regions.count == t.regions.count && u.detailRegions == t.detailRegions)
        for r in t.regions.indices where r != a {
            #expect(u.regions[r] == t.regions[r], "region \(r)")
            #expect(Array(u.labels(ofRegion: r)) == Array(t.labels(ofRegion: r)), "region \(r)'s numbers")
            #expect(TemplateEditorTests.snapshot(u, r) == TemplateEditorTests.snapshot(t, r), "region \(r)")
        }
        #expect(u.edges == t.edges && u.points == t.points && u.regionMap == t.regionMap && u.lineArt == t.lineArt)
        #expect(u.polygons(ofRegion: a) == t.polygons(ofRegion: a), "the area keeps its outline")
        // The same edit gives the same bytes.
        #expect(try TemplateEditor.apply(.paintArea(at: Self.inA, color: Self.magenta), to: t).template.encoded() == u.encoded())
    }

    /// The second box given the same color takes the paint the first one did. An area given a
    /// color its own paint is nearest has nothing to change.
    @Test func theSameColorReusesItsPaint() throws {
        let (u, _) = try TemplateEditorTests.apply(.paintArea(at: Self.inA, color: Self.magenta), to: Self.base)
        let (v, outcome) = try TemplateEditorTests.apply(.paintArea(at: Self.inB, color: Self.magenta), to: u)
        #expect(outcome.changed && outcome.paintsAdded == 0 && v.palette == u.palette)
        let a = try Self.region(v, Self.inA), b = try Self.region(v, Self.inB)
        #expect(v.regions[b].colorIndex == v.regions[a].colorIndex && Int(v.regions[b].colorIndex) == Self.base.palette.count)

        let (same, nothing) = try TemplateEditor.apply(.paintArea(at: Self.inA, color: Self.magenta + SIMD3(0.005, 0, 0)), to: v)
        #expect(!nothing.changed && nothing.declined == nil && same == v)
        var trail = EditTrail(base: Self.base)
        #expect(trail.add(.paintArea(at: Self.inA, color: Self.magenta)).isMade)
        #expect(trail.add(.paintArea(at: Self.inA, color: Self.magenta)) == .nothing && trail.edits.count == 1)
    }

    /// A color within a just-noticeable difference of a paint takes that paint, not a new one.
    @Test func aColorNearAPaintTakesIt() throws {
        let t = Self.base
        let ground = try Self.region(t, Self.ground)
        let near = t.palette[Int(t.regions[ground].colorIndex)].oklab + SIMD3(0.012, 0, 0)
        let (u, outcome) = try TemplateEditorTests.apply(.paintArea(at: Self.inA, color: near), to: t)
        #expect(outcome.changed && outcome.paintsAdded == 0 && u.palette == t.palette)
        #expect(u.regions[try Self.region(u, Self.inA)].colorIndex == t.regions[ground].colorIndex)
    }

    /// The lower sky given the sky's own paint meets the upper sky across the split's undrawn
    /// boundary: the two are one area again, the larger keeping its index, and the shade the split
    /// gave the lower sky, its only area gone, leaves the palette.
    @Test func anAreaJoinsItsNewPaintAcrossAnUndrawnBoundary() throws {
        let t = Self.base
        let upper = try Self.region(t, Self.upper), lower = try Self.region(t, Self.lower)
        let sky = try Self.paint(t, Self.upper)
        let (u, outcome) = try TemplateEditorTests.apply(.paintArea(at: Self.lower, color: sky), to: t)
        #expect(outcome.changed && outcome.regionsMerged == 1 && outcome.paintsMerged == 1 && outcome.paintsAdded == 0)
        #expect(u.regions.count == t.regions.count - 1 && u.palette == Array(t.palette.dropLast()))
        let joined = try Self.region(u, Self.upper)
        #expect(try Self.region(u, Self.lower) == joined && outcome.continued[lower] == joined && outcome.continued[upper] == joined)
        #expect(u.palette[Int(u.regions[joined].colorIndex)].oklab == sky)
        let art = try #require(u.lineArt)
        for (e, edge) in u.edges.enumerated() where art.edgeLayers[e] == LineLayer.color.rawValue && edge.right != BoundaryEdge.outside {
            #expect(u.regions[Int(edge.left)].colorIndex != u.regions[Int(edge.right)].colorIndex, "an undrawn edge inside one area")
        }
        for p in [Self.inA, Self.inB, Self.ground, Self.square] {
            let r = try Self.region(t, p)
            #expect(TemplateEditorTests.snapshot(t, r) == TemplateEditorTests.snapshot(u, outcome.continued[r]), "\(p)")
        }
    }

    /// The square is its paint's only area: given the ground's paint, its own leaves the palette
    /// and the numbers after it close up, as a repaint's merge closes them, so no paint is left
    /// with no area; every region keeps its color, and the shapes are as they were.
    @Test func aPaintsOnlyAreaGivenAnotherPaintTakesItsPaintOutOfThePalette() throws {
        let t = Self.scene
        let square = try Self.region(t, Self.square), ground = try Self.region(t, Self.ground)
        let gone = Int(t.regions[square].colorIndex)
        try #require(t.regions.indices.filter { Int(t.regions[$0].colorIndex) == gone } == [square], "the square is its paint's only area")
        try #require(gone < t.palette.count - 1, "paints come after it")
        let groundPaint = t.palette[Int(t.regions[ground].colorIndex)].oklab
        let (u, outcome) = try TemplateEditorTests.apply(.paintArea(at: Self.square, color: groundPaint), to: t)
        #expect(outcome.changed && outcome.paintsMerged == 1 && outcome.paintsAdded == 0 && outcome.regionsMerged == 0)
        var palette = t.palette
        palette.remove(at: gone)
        #expect(u.palette == palette)
        #expect(u.regions.count == t.regions.count)
        for r in t.regions.indices {
            let was = r == square ? Int(t.regions[ground].colorIndex) : Int(t.regions[r].colorIndex)
            #expect(Int(u.regions[r].colorIndex) == (was > gone ? was - 1 : was), "region \(r)'s number")
            #expect(u.palette[Int(u.regions[r].colorIndex)] == t.palette[was], "region \(r)'s color")
        }
        #expect(Set(u.regions.map(\.colorIndex)).count == u.palette.count, "every paint has an area")
        #expect(u.edges == t.edges && u.points == t.points && u.regionMap == t.regionMap && u.lineArt == t.lineArt)
        for r in t.regions.indices where r != square {
            #expect(Array(u.labels(ofRegion: r)) == Array(t.labels(ofRegion: r)), "region \(r)'s numbers")
        }
    }

    /// An area stays what it was: a detail area (a fill's) is one still; a box that was not one
    /// stays not (`oneAreaTakesANewPaintAndNothingElseChanges`).
    @Test func aDetailAreaStaysOne() throws {
        let (filled, _) = try TemplateEditorTests.apply(.fill(at: Self.inA, color: Self.magenta), to: Self.base)
        let a = try Self.region(filled, Self.inA)
        try #require(filled.isDetailRegion(a))
        let cyan = SIMD3<Float>(0.8, -0.12, -0.08)
        let (u, outcome) = try TemplateEditorTests.apply(.paintArea(at: Self.inA, color: cyan), to: filled)
        let painted = try Self.region(u, Self.inA)
        #expect(outcome.changed && u.detailRegions == filled.detailRegions && u.isDetailRegion(painted))
        // The fill's paint had no other area: it went, and the new one took its number.
        #expect(u.palette.count == filled.palette.count && u.palette.last == PaletteColor(oklab: cyan, space: u.colorSpace))
    }

    /// A box at a roomy number of a one-digit paint on the crowded book: room there for one digit
    /// and not two, so a paint of two digits is declined, the template left as it was; one of a
    /// single digit is made.
    @Test func anAreaTooCrampedForItsNewNumberIsDeclined() throws {
        let t = TemplateEditorTests.rich
        try #require(t.palette.count >= 10)
        let art = try #require(t.lineArt)
        let host = try #require(t.regions.indices.first { r in
            t.regions[r].colorIndex < 9 && !t.isDetailRegion(r) && t.regions[r].inscribedRadius >= 8
                && !art.strokes.contains { Int($0.region) == r }
        })
        let c = TemplateEditorTests.quantized(try #require(t.labels(ofRegion: host).first).position)
        let h: Float = 2.75
        let box = [c + SIMD2(-h, -h), c + SIMD2(h, -h), c + SIMD2(h, h), c + SIMD2(-h, h)]
        let (boxed, drawn) = try TemplateEditorTests.apply(.draw(points: box, closed: true), to: t)
        try #require(drawn.regionsSplit == 1)
        let small = try Self.region(boxed, c)
        let own = boxed.regions[small].colorIndex
        try #require(own == t.regions[host].colorIndex && !boxed.isDetailRegion(small))
        #expect(LabelSizing.minimumRadius(digits: 1) <= boxed.regions[small].inscribedRadius
            && boxed.regions[small].inscribedRadius < LabelSizing.minimumRadius(digits: 2))

        // Paint 10.
        let (same, declined) = try TemplateEditor.apply(.paintArea(at: c, color: boxed.palette[9].oklab), to: boxed)
        #expect(declined.declined?.reason.contains("no room") == true && !declined.changed && same == boxed)
        var trail = EditTrail(base: boxed)
        if case .declined = trail.add(.paintArea(at: c, color: boxed.palette[9].oklab)) {} else { Issue.record("a cramped area was painted") }

        let other = try #require((0..<9).first { UInt32($0) != own })
        let (u, made) = try TemplateEditorTests.apply(.paintArea(at: c, color: boxed.palette[other].oklab), to: boxed)
        let painted = try Self.region(u, c)
        #expect(made.changed && u.regions[painted].colorIndex == UInt32(other))
    }

    /// Its color is one of the template on screen, the look already in it (the area card's picker
    /// and palette chips read it so), so a look laid before leaves it as sent: a paint's own color
    /// picked after a look lands on that paint, and a new color is the paint as sent. It is no
    /// recolor itself, so a look or Photo taking the looks out keeps it.
    @Test func aLookLaidBeforeLeavesItsColorAsSent() throws {
        let look = TemplateEditor.look(.moonlit, strength: 1, on: Self.base)
        let fresh = Edit.paintArea(at: Self.inB, color: Self.magenta)
        #expect(!TemplateEditor.isRecolor(fresh))
        #expect(TemplateEditor.recolored(fresh, by: [look]) == fresh)
        var trail = EditTrail(base: Self.base)
        #expect(trail.add(look).isMade)
        let looked = trail.template
        // The ground's paint as the screen shows it, under the look.
        let pick = Edit.paintArea(at: Self.inA, color: try Self.paint(looked, Self.ground))
        #expect(trail.add(pick).isMade)
        let picked = trail.template
        expectValid(picked)
        let a = try Self.region(picked, Self.inA), ground = try Self.region(picked, Self.ground)
        #expect(picked.regions[a].colorIndex == picked.regions[ground].colorIndex && picked.palette == looked.palette)

        #expect(trail.add(fresh).isMade)
        expectValid(trail.template)
        #expect(try Self.paint(trail.template, Self.inB) == Self.magenta)
        #expect(trail.template.palette.count == looked.palette.count + 1)
        // The list laid at once gives the same template.
        #expect(try TemplateEditor.apply([look, pick, fresh], to: Self.base).template == trail.template)
    }

    /// A tap off the canvas, or numbers that aren't, change nothing; reading the photo for an edit
    /// (`TemplateEditor.painted`) leaves this one as it is.
    @Test func editsThatCannotBeMadeChangeNothing() throws {
        let t = Self.base
        for edit in [
            Edit.paintArea(at: SIMD2(1e9, -1e9), color: Self.magenta), .paintArea(at: SIMD2(.nan, 5), color: Self.magenta),
            .paintArea(at: Self.inA, color: SIMD3(.nan, 0, 0)), .paintArea(at: SIMD2(.infinity, 5), color: Self.magenta),
        ] {
            let (same, outcome) = try TemplateEditor.apply(edit, to: t)
            #expect(same == t && !outcome.changed, "\(edit)")
        }
        let photo = RGBAImage(width: t.width, height: t.height, pixels: [UInt8](repeating: 255, count: t.width * t.height * 4))
        let edit = Edit.paintArea(at: Self.inA, color: Self.magenta)
        #expect(TemplateEditor.painted(edit, on: t, photo: photo) == edit)
    }

    /// Kept in a file as a fill is: its point and its color.
    @Test func itIsKeptInFiles() throws {
        let edit = Edit.paintArea(at: SIMD2(140, 55), color: SIMD3(0.7, -0.125, 0.0625))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let json = String(decoding: try encoder.encode([edit]), as: UTF8.self)
        #expect(json == #"[{"color":[0.7,-0.125,0.0625],"kind":"paintArea","points":[[140,55]]}]"#)
        #expect(try JSONDecoder().decode([Edit].self, from: Data(json.utf8)) == [edit])
        for bad in [
            #"{"kind":"paintArea","points":[[1,2]]}"#, #"{"kind":"paintArea","points":[],"color":[0.5,0,0]}"#,
            #"{"kind":"paintArea","points":[[1,2]],"color":[0.5,0]}"#,
        ] {
            #expect(throws: DecodingError.self, "\(bad)") { try JSONDecoder().decode(Edit.self, from: Data(bad.utf8)) }
        }
    }
}
