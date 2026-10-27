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
        // Exactly the room at the point, to the outline (the sky has no stroke to keep off).
        let outline = EditWork.flatPolygon(u.polygons(ofRegion: sky).map { $0.map(Lattice.point) })
        #expect(moved.radius == Float(outline.signedDistance(30, 30)))
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

    /// `labelNear` is the grab's rule: the number it finds is the one the edit moves, and nothing
    /// is found where the edit finds no number.
    @Test func labelNearIsTheNumberMoved() throws {
        let t = TemplateEditorTests.rich
        var rng = SplitMix64(seed: 11)
        var moved = 0
        for _ in 0..<24 {
            let at = SIMD2(Float(rng.next() % UInt64(t.width * 4)) / 4, Float(rng.next() % UInt64(t.height * 4)) / 4)
            let held = TemplateEditor.labelNear(on: t, at: at, reach: TemplateEditor.tapReach)
            let (u, outcome) = try TemplateEditor.apply(.moveLabel(from: at, to: at + SIMD2(0.5, 0)), to: t)
            guard let held else {
                #expect(outcome.declined?.reason.contains("no number") == true)
                continue
            }
            #expect(t.labels(ofRegion: held.region).contains(held.label))
            #expect(simdLength(held.label.position - at) <= held.label.radius + TemplateEditor.tapReach + 0.01)
            guard outcome.changed else { continue }
            let before = Array(t.labels(ofRegion: held.region)), after = Array(u.labels(ofRegion: outcome.continued[held.region]))
            let k = try #require(before.firstIndex(of: held.label))
            #expect(after[k].position != held.label.position && after.enumerated().allSatisfy { $0.offset == k || $0.element == before[$0.offset] })
            moved += 1
        }
        #expect(moved >= 4)
        let label = try Self.number(Self.scene, Self.sky)
        let held = try #require(TemplateEditor.labelNear(on: Self.scene, at: label.position + SIMD2(1, 1), reach: TemplateEditor.tapReach))
        #expect(held.region == (try Self.region(Self.scene, Self.sky)) && held.label == label)
        #expect(TemplateEditor.labelNear(on: Self.scene, at: SIMD2(2, 2), reach: TemplateEditor.tapReach) == nil)
        #expect(TemplateEditor.labelNear(on: Self.scene, at: SIMD2(.nan, 2), reach: TemplateEditor.tapReach) == nil)
    }

    /// A wider reach grabs a number from farther off: the sky's number, 10 units past its circle,
    /// is out of the default reach and within 12 units'.
    @Test func reachWidensTheGrab() throws {
        let t = Self.scene
        let label = try Self.number(t, Self.sky)
        let from = label.position + SIMD2(label.radius + 10, 0)
        #expect(TemplateEditor.labelNear(on: t, at: from, reach: TemplateEditor.tapReach) == nil)
        #expect(try Self.declined(.moveLabel(from: from, to: SIMD2(30, 30)), on: t)?.contains("no number") == true)
        let held = try #require(TemplateEditor.labelNear(on: t, at: from, reach: 12))
        #expect(held.label == label)
        let (u, outcome) = try TemplateEditorTests.apply(.moveLabel(from: from, to: SIMD2(30, 30), reach: 12), to: t)
        #expect(outcome.labelsMoved == 1 && u.labels(ofRegion: held.region).first?.position == SIMD2(30, 30))
        // A reach held to the edit's bounds: none past 1024 units, none below 0.
        #expect(TemplateEditor.labelNear(on: t, at: from, reach: -.infinity) == nil)
        #expect(TemplateEditor.labelNear(on: t, at: from, reach: .nan) == nil)
    }

    /// The sky has three numbers: its main one at about (97, 30), others at (18.5, 44.5) and
    /// (176.5, 16.5). Dragged onto another, or so near that the discs their digits are drawn in
    /// (at most 0.045 × 144 units high, about 3.6 units round for one digit) would overlap, the
    /// main number stays where it was; just clear of them it moves, though the rooms of the two
    /// overlap.
    @Test func aNumberKeepsOffTheRegionsOthers() throws {
        let t = Self.scene
        let sky = try Self.region(t, Self.sky)
        let own = Array(t.labels(ofRegion: sky))
        #expect(own.count == 3)
        let main = own[0], other = own[1]
        let digits = LabelSizing.digitCount(colorIndex: t.regions[sky].colorIndex)
        let drawn = EditWork.largestNumberFraction * 144 * LabelSizing.runDiagonal(digits: digits) / (2 * LabelSizing.fill)
        #expect(other.radius > drawn && main.radius > drawn)
        for gap: Float in [0, 2, 2 * drawn - 0.5] {
            let onto = other.position + SIMD2(gap, 0)
            #expect(try Self.declined(.moveLabel(from: main.position, to: onto), on: t)?.contains("another") == true, "\(gap)")
        }
        let clear = other.position + SIMD2(2 * drawn + 0.5, 0)
        let (u, outcome) = try TemplateEditorTests.apply(.moveLabel(from: main.position, to: clear), to: t)
        #expect(outcome.labelsMoved == 1)
        let moved = Array(u.labels(ofRegion: sky))
        #expect(simdLength(moved[0].position - clear) < 0.02 && moved[1] == other && moved[2] == own[2])
        #expect(moved[0].radius + other.radius > simdLength(moved[0].position - other.position), "the rooms overlap")
    }

    @Test func codingRoundTrips() throws {
        let edit = Edit.moveLabel(from: SIMD2(104, 30.5), to: SIMD2(30.25, 30))
        #expect(try JSONDecoder().decode(Edit.self, from: JSONEncoder().encode(edit)) == edit)
        let reached = Edit.moveLabel(from: SIMD2(104, 30.5), to: SIMD2(30.25, 30), reach: 3.25)
        #expect(try JSONDecoder().decode(Edit.self, from: JSONEncoder().encode(reached)) == reached)
        let bare = Data(#"{"kind": "moveLabel", "points": [[1, 2], [3, 4]]}"#.utf8)
        #expect(try JSONDecoder().decode(Edit.self, from: bare) == .moveLabel(from: SIMD2(1, 2), to: SIMD2(3, 4), reach: TemplateEditor.tapReach))
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        #expect(try String(decoding: encoder.encode(reached), as: UTF8.self) == #"{"kind":"moveLabel","points":[[104,30.5],[30.25,30]],"reach":3.25}"#)
        let one = Data(#"{"kind": "moveLabel", "points": [[1, 2]]}"#.utf8)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(Edit.self, from: one) }
        #expect(TemplateEditor.recolored(edit, by: [.look(.moonlit, strength: 1)]) == edit)
    }
}
