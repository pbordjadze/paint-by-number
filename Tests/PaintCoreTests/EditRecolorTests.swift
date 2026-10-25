import Foundation
import Testing
@testable import PaintCore

/// Refine's Looks and Edit Paint (`TemplateEditor.Edit.look`, `.repaint`): paints alone change, paints that
/// meet become one and the numbers after them close up, areas that then share a paint across an
/// undrawn boundary join, edits laid later bring their colors through, and the looks' math is
/// pinned, since paintings record a look by name.
@Suite("Edit recolor")
struct EditRecolorTests {
    typealias Edit = TemplateEditor.Edit

    static let scene = TemplateEditorTests.scene
    static let rich = TemplateEditorTests.rich

    /// Everything of a template but its paints: what a recolor without merges leaves alone.
    static func expectSameShapes(_ a: Template, _ b: Template, sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(a.regions.count == b.regions.count, sourceLocation: sourceLocation)
        #expect(a.edges == b.edges && a.points == b.points && a.labels == b.labels, sourceLocation: sourceLocation)
        #expect(a.regionMap == b.regionMap && a.lineArt?.strokes == b.lineArt?.strokes, sourceLocation: sourceLocation)
        #expect(a.regions.map(\.colorIndex) == b.regions.map(\.colorIndex), sourceLocation: sourceLocation)
    }

    @Test func aLookChangesThePaintsAlone() throws {
        let t = Self.rich
        let (u, outcome) = try TemplateEditorTests.apply(.look(.goldenHour, strength: 0.5), to: t)
        try #require(outcome.paintsMerged == 0, "a gentle look met no paints")
        #expect(outcome.changed && outcome.paintsChanged == t.palette.count && outcome.regionsMerged == 0)
        Self.expectSameShapes(t, u)
        for (p, q) in zip(t.palette, u.palette) {
            #expect(q.oklab == TemplateEditor.recolor(p.oklab, by: .look(.goldenHour, strength: 0.5)))
        }
        // The same edit gives the same bytes.
        let (again, _) = try TemplateEditor.apply(.look(.goldenHour, strength: 0.5), to: t)
        #expect(again.encoded() == u.encoded())
    }

    @Test func aLookAtNoStrengthChangesNothing() throws {
        let (u, outcome) = try TemplateEditor.apply(.look(.moonlit, strength: 0), to: Self.rich)
        #expect(!outcome.changed && outcome.declined == nil && u == Self.rich)
        var trail = EditTrail(base: Self.rich)
        #expect(trail.add(.look(.sepia, strength: 0)) == .nothing && trail.edits.isEmpty)
    }

    @Test func everyLookGivesAValidTemplate() throws {
        for look in TemplateEditor.Look.allCases {
            let edit = TemplateEditor.look(look, strength: 1, on: Self.rich)
            let (u, outcome) = try TemplateEditorTests.apply(edit, to: Self.rich)
            #expect(outcome.changed, "\(look)")
            #expect(u.palette.count == Self.rich.palette.count - outcome.paintsMerged, "\(look)")
            for i in u.palette.indices {
                for j in 0..<i where ColorScience.distance(u.palette[i].oklab, u.palette[j].oklab) < SegmentationParameters.jnd {
                    Issue.record("\(look): paints \(j + 1) and \(i + 1) are closer than a just-noticeable difference")
                }
            }
            let used = Set(u.regions.map(\.colorIndex))
            #expect(used.count == u.palette.count, "\(look): every paint is used")
        }
    }

    @Test func aRepaintChangesOnePaint() throws {
        let t = Self.rich
        let k = 3
        let from = t.palette[k].oklab
        let to = SIMD3<Float>(0.5, 0.1, -0.1)
        let (u, outcome) = try TemplateEditorTests.apply(.repaint(from: from, to: to, family: false), to: t)
        #expect(outcome.paintsChanged == 1 && outcome.paintsMerged == 0)
        Self.expectSameShapes(t, u)
        for i in t.palette.indices {
            #expect(u.palette[i] == (i == k ? PaletteColor(oklab: to, space: t.colorSpace) : t.palette[i]))
        }
    }

    /// A paint made another paint's color becomes that paint: the lower number stays, the numbers
    /// after the higher close up, and areas the two paints kept apart across an undrawn boundary
    /// become one.
    @Test func aRepaintOntoAnotherPaintMakesThemOne() throws {
        let t = Self.rich
        // Two paints that meet across an undrawn edge.
        let art = try #require(t.lineArt)
        let e = try #require(t.edges.indices.first { e in
            art.edgeLayers[e] == LineLayer.color.rawValue && t.edges[e].right != BoundaryEdge.outside
                && t.regions[Int(t.edges[e].left)].colorIndex != t.regions[Int(t.edges[e].right)].colorIndex
        })
        let a = Int(t.regions[Int(t.edges[e].left)].colorIndex), b = Int(t.regions[Int(t.edges[e].right)].colorIndex)
        let (low, high) = (min(a, b), max(a, b))
        let (u, outcome) = try TemplateEditorTests.apply(
            .repaint(from: t.palette[high].oklab, to: t.palette[low].oklab, family: false), to: t)
        #expect(outcome.paintsMerged == 1 && outcome.regionsMerged >= 1)
        #expect(u.palette.count == t.palette.count - 1)
        #expect(u.palette[low] == t.palette[low])
        for i in (high + 1)..<t.palette.count { #expect(u.palette[i - 1] == t.palette[i], "the numbers after it close up") }
        #expect(Set(u.regions.map(\.colorIndex)).count == u.palette.count)
        #expect(u.regions.count == t.regions.count - outcome.regionsMerged)
        // No undrawn edge is left between two areas of one paint the edit made one.
        let uArt = try #require(u.lineArt)
        for (i, edge) in u.edges.enumerated() where uArt.edgeLayers[i] == LineLayer.color.rawValue && edge.right != BoundaryEdge.outside {
            let l = u.regions[Int(edge.left)].colorIndex, r = u.regions[Int(edge.right)].colorIndex
            #expect(!(l == r && l == UInt32(low)), "areas of the merged paint still meet across an undrawn edge")
        }
    }

    @Test func aFamilyMovesWithItsSwatch() {
        let red = SIMD3<Float>(0.6, 0.2, 0.1), blue = SIMD3<Float>(0.6, -0.05, -0.2)
        let edit = Edit.repaint(from: red, to: blue, family: true)
        #expect(TemplateEditor.recolor(red, by: edit) == blue)
        // A darker red of the same hue turns with it; a green and a gray stay.
        let darkRed = SIMD3<Float>(0.4, 0.15, 0.07)
        let moved = TemplateEditor.recolor(darkRed, by: edit)
        #expect(moved.z < 0 && abs(moved.x - 0.4) < 1e-6, "\(moved)")
        let green = SIMD3<Float>(0.6, -0.15, 0.1), gray = SIMD3<Float>(0.5, 0.005, 0.005)
        #expect(TemplateEditor.recolor(green, by: edit) == green)
        #expect(TemplateEditor.recolor(gray, by: edit) == gray)
        // Without its family, only the swatch's own color moves.
        #expect(TemplateEditor.recolor(darkRed, by: .repaint(from: red, to: blue, family: false)) == darkRed)
        // A gray swatch's family is the colors near it.
        let grayEdit = Edit.repaint(from: gray, to: SIMD3(0.3, 0, 0), family: true)
        #expect(TemplateEditor.recolor(SIMD3(0.52, 0.0, 0.01), by: grayEdit).x < 0.4)
        #expect(TemplateEditor.recolor(SIMD3(0.8, 0.0, 0.0), by: grayEdit) == SIMD3(0.8, 0.0, 0.0))
    }

    /// A fill laid after a look takes the look's color, as a drawn line's pieces do.
    @Test func laterEditsBringTheirColorsThroughALook() throws {
        let look = TemplateEditor.look(.moonlit, strength: 1, on: Self.scene)
        let photoColor = SIMD3<Float>(0.7, -0.1, 0.1)
        let fill = Edit.fill(at: SIMD2(140, 55), color: photoColor)
        var trail = EditTrail(base: Self.scene)
        #expect(trail.add(look).isMade)
        #expect(trail.add(fill).isMade)
        let t = trail.template
        let r = try TemplateEditorTests.region(t, 140, 55)
        let paint = t.palette[Int(t.regions[r].colorIndex)].oklab
        #expect(ColorScience.distance(paint, TemplateEditor.recolor(photoColor, by: look)) <= SegmentationParameters.jnd)
        // The list laid at once, and laid again from the base, give the same template.
        #expect(try TemplateEditor.apply([look, fill], to: Self.scene).template == t)
        var again = EditTrail(base: Self.scene)
        try again.move(to: [look, fill])
        #expect(again.template == t)
        // Taking the look back lays the fill in the photo's color.
        try trail.move(to: [fill])
        let plain = try TemplateEditor.apply(fill, to: Self.scene).template
        #expect(trail.template == plain)
    }

    /// A look that did nothing is no ground for the edits after it.
    @Test func aLookThatChangedNothingLeavesLaterColorsAlone() throws {
        let fill = Edit.fill(at: SIMD2(140, 55), color: SIMD3(0.7, -0.1, 0.1))
        let laid = try TemplateEditor.apply([.look(.sepia, strength: 0), fill], to: Self.scene).template
        #expect(laid == (try TemplateEditor.apply(fill, to: Self.scene).template))
        var trail = EditTrail(base: Self.scene)
        try trail.move(to: [.look(.sepia, strength: 0), fill])
        #expect(trail.template == laid)
    }

    /// The looks' math is a file format: a recorded look must give the same paints in every later
    /// build. These are the bits each look gives a few colors today.
    @Test func looksArePinned() {
        let colors: [SIMD3<Float>] = [SIMD3(0.2, 0.05, -0.1), SIMD3(0.55, -0.12, 0.08), SIMD3(0.9, 0.01, 0.02)]
        let lightness: [Float] = [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9]
        var digest: UInt64 = 1469598103934665603
        for look in TemplateEditor.Look.allCases {
            for c in colors {
                let out = TemplateEditor.recolor(c, by: .look(look, strength: 0.75, lightness: lightness))
                for v in [out.x, out.y, out.z] { digest = (digest ^ UInt64(v.bitPattern)) &* 1099511628211 }
            }
        }
        #expect(digest == Self.lookDigest, "a look's math changed: \(digest)")
        #expect(TemplateEditor.Look.allCases.map(\.rawValue)
            == ["moonlit", "goldenHour", "pastel", "sepia", "garden", "starryNight", "waterLilies", "greatWave"])
    }

    static let lookDigest: UInt64 = 15864780550302597421

    @Test func aLookRecordsThePaintingsLightness() {
        guard case .look(_, _, let lightness) = TemplateEditor.look(.starryNight, strength: 1, on: Self.rich) else {
            Issue.record("not a look")
            return
        }
        #expect(lightness.count == 9 && lightness == lightness.sorted())
        let ls = Self.rich.palette.map(\.oklab.x)
        #expect(lightness.first == ls.min() && lightness.last == ls.max())
        guard case .look(_, _, let none) = TemplateEditor.look(.moonlit, strength: 1, on: Self.rich) else { return }
        #expect(none.isEmpty, "a look that doesn't place paints on a ramp records nothing")
    }

    @Test func recolorsAreKeptInFiles() throws {
        let edits: [Edit] = [
            .look(.starryNight, strength: 0.5, lightness: [0.25, 0.5, 0.75]),
            .look(.moonlit, strength: 1),
            .repaint(from: SIMD3(0.5, 0.125, 0), to: SIMD3(0.25, 0, -0.125), family: true),
        ]
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let json = String(decoding: try encoder.encode(edits), as: UTF8.self)
        #expect(json == #"[{"kind":"look","lightness":[0.25,0.5,0.75],"look":"starryNight","points":[],"strength":0.5},"#
            + #"{"kind":"look","look":"moonlit","points":[],"strength":1},"#
            + #"{"color":[0.25,0,-0.125],"family":true,"from":[0.5,0.125,0],"kind":"repaint","points":[]}]"#)
        #expect(try JSONDecoder().decode([Edit].self, from: Data(json.utf8)) == edits)
        // A missing family is false; a look this build doesn't know fails that edit.
        let bare = #"{"kind":"repaint","points":[],"from":[0.5,0,0],"color":[0.4,0,0]}"#
        #expect(try JSONDecoder().decode(Edit.self, from: Data(bare.utf8))
            == .repaint(from: SIMD3(0.5, 0, 0), to: SIMD3(0.4, 0, 0), family: false))
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(Edit.self, from: Data(#"{"kind":"look","points":[],"look":"cubist","strength":1}"#.utf8))
        }
    }
}
