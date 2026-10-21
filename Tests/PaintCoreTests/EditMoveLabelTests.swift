import Foundation
import Testing
@testable import PaintCore

/// Refine's Move Number (`TemplateEditor.Edit.moveLabel`): a number dragged to another spot of its
/// cell, sized for the room there. On the editor's scene (`TemplateEditorTests`: sky above the
/// horizon at y ≈ 72, ground below with its detail stroke at y ≈ 120).
@Suite("Edit move label")
struct EditMoveLabelTests {
    typealias Edit = TemplateEditor.Edit

    static let scene = TemplateEditorTests.scene
    static let sky = SIMD2<Float>(104, 30), ground = SIMD2<Float>(100, 100)

    static func region(_ t: Template, _ p: SIMD2<Float>) throws -> Int { try TemplateEditorTests.region(t, p.x, p.y) }
    static func number(_ t: Template, _ p: SIMD2<Float>) throws -> Label { try #require(t.labels(ofRegion: Self.region(t, p)).first) }

    static func declined(_ edit: Edit, on t: Template) throws -> String? {
        let (u, outcome) = try TemplateEditor.apply(edit, to: t)
        if outcome.declined != nil { #expect(u == t && !outcome.changed) }
        return outcome.declined?.reason
    }

    /// The sky's number dragged to the sky's left: it sits where the finger lifted, sized for the
    /// room there, and nothing else changes, its cell's outline and fill neither.
    @Test func aNumberMovesWithinItsCell() throws {
        let t = Self.scene
        let sky = try Self.region(t, Self.sky)
        let label = try Self.number(t, Self.sky)
        let to = SIMD2<Float>(30, 30)
        let edit = Edit.moveLabel(from: label.position + SIMD2(1, 1), to: to)
        let (u, outcome) = try TemplateEditorTests.apply(edit, to: t)
        #expect(outcome.changed && outcome.labelsMoved == 1 && outcome.touchedRegions == [sky])
        let moved = try #require(u.labels(ofRegion: sky).first)
        #expect(moved.position == to)
        #expect(abs(moved.radius - (hypot(30, 42) - 27)) < 0.6, "the disc's outline is nearest: \(moved.radius)")
        #expect(moved.radius <= label.radius + 0.5, "never more than the cell's best spot holds")
        #expect(u.labels(ofRegion: sky).count == t.labels(ofRegion: sky).count)
        #expect(u.polygons(ofRegion: sky) == t.polygons(ofRegion: sky) && u.mesh == t.mesh && u.regionMap == t.regionMap)
        #expect(u.regions[sky].inscribedRadius == moved.radius)
        TemplateEditorTests.expectOthersUnchanged(t, u, outcome)
        #expect(try TemplateEditor.apply(edit, to: t).template.encoded() == u.encoded())
        #expect(try Template(encoded: u.encoded()) == u)

        // An edit elsewhere leaves it where it was put.
        let (v, _) = try TemplateEditorTests.apply(.paintArea(at: Self.ground, color: SIMD3(0.62, 0.2, -0.1)), to: u)
        #expect(v.labels(ofRegion: sky).first == moved)
    }

    /// Near the cell's edge the number shrinks to the room there; too near, or across the edge,
    /// or onto a line inside the cell, it stays where it was.
    @Test func aNumberNeedsRoomInItsOwnCell() throws {
        let t = Self.scene
        let label = try Self.number(t, Self.sky)
        let near = try TemplateEditorTests.apply(.moveLabel(from: label.position, to: SIMD2(100, 64)), to: t).0
        let small = try #require(near.labels(ofRegion: Self.region(t, Self.sky)).first)
        #expect(small.position == SIMD2(100, 64) && abs(small.radius - 8) < 0.5, "\(small.radius)")
        #expect(try Self.declined(.moveLabel(from: label.position, to: SIMD2(100, 71)), on: t)?.contains("room") == true)
        #expect(try Self.declined(.moveLabel(from: label.position, to: SIMD2(100, 130)), on: t)?.contains("room") == true)
        let groundLabel = try Self.number(t, Self.ground)
        #expect(try Self.declined(.moveLabel(from: groundLabel.position, to: SIMD2(96, 120.3)), on: t)?.contains("room") == true)
        // Off the canvas, and nowhere near a number.
        #expect(try Self.declined(.moveLabel(from: label.position, to: SIMD2(30, -5)), on: t)?.contains("room") == true)
        #expect(try Self.declined(.moveLabel(from: SIMD2(2, 2), to: SIMD2(30, 30)), on: t)?.contains("no number") == true)
    }

    /// A detail area's number moves by its own floor, about half the usual.
    @Test func aDetailAreasNumberHasItsOwnFloor() throws {
        let boxed = try TemplateEditorTests.apply(
            .draw(points: [SIMD2(100, 100), SIMD2(104, 100), SIMD2(104, 104), SIMD2(100, 104)], closed: true), to: Self.scene).0
        let box = try Self.region(boxed, SIMD2(102, 102))
        #expect(boxed.isDetailRegion(box))
        let label = try #require(boxed.labels(ofRegion: box).first)
        let (u, outcome) = try TemplateEditorTests.apply(.moveLabel(from: label.position, to: SIMD2(102.25, 102)), to: boxed)
        let moved = try #require(u.labels(ofRegion: box).first)
        #expect(outcome.labelsMoved == 1 && moved.position == SIMD2(102.25, 102) && abs(moved.radius - 1.75) < 0.01)
        #expect(u.isDetailRegion(box))
        #expect(try Self.declined(.moveLabel(from: label.position, to: SIMD2(103.5, 102)), on: boxed)?.contains("room") == true)
    }

    @Test func codingRoundTrips() throws {
        let edit = Edit.moveLabel(from: SIMD2(104, 30.5), to: SIMD2(30.25, 30))
        #expect(try JSONDecoder().decode(Edit.self, from: JSONEncoder().encode(edit)) == edit)
        let one = Data(#"{"kind": "moveLabel", "points": [[1, 2]]}"#.utf8)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(Edit.self, from: one) }
        #expect(TemplateEditor.recolored(edit, by: [.look(.moonlit, strength: 1)]) == edit)
    }
}
