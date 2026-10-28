import Foundation
import Testing
@testable import PaintCore

/// Refine's cells for VoiceOver (`RefineCells`): each cell found at its roomiest number, its
/// neighbours, and the edits VoiceOver's actions make in place of Merge's and Move Number's drags,
/// on the editor tests' scene (a sky over a horizon, a square, a disc and the ground).
@Suite("Refine cells")
struct RefineCellsTests {
    static let scene = TemplateEditorTests.scene

    /// Every cell is found at its roomiest number, which lies in it.
    @Test func eachCellIsFoundAtItsRoomiestNumber() {
        let t = Self.scene
        let anchors = RefineCells.anchors(in: t)
        #expect(anchors.count == t.regions.count)
        for r in t.regions.indices {
            let roomiest = t.labels(ofRegion: r).map(\.radius).max()
            #expect(roomiest != nil, "region \(r) has no number")
            #expect(t.labels(ofRegion: r).contains { $0.position == anchors[r] && $0.radius == roomiest })
            #expect(t.region(at: anchors[r]) == r, "region \(r)'s anchor lies outside it")
        }
        #expect(RefineCells.anchor(of: -1, in: t) == nil && RefineCells.anchor(of: t.regions.count, in: t) == nil)
    }

    /// Neighbours share an edge, both ways, the frame being none, each once.
    @Test func neighboursShareAnEdgeBothWays() throws {
        let t = Self.scene
        for r in t.regions.indices {
            let around = RefineCells.neighbours(of: r, in: t)
            #expect(Set(around).count == around.count && !around.contains(r))
            for n in around {
                #expect(RefineCells.neighbours(of: n, in: t).contains(r), "\(n) doesn't border \(r) back")
                #expect(t.edges.contains { Set([Int($0.left), Int($0.right)]) == Set([r, n]) })
            }
        }
        let sky = try TemplateEditorTests.region(t, 100, 20), square = try TemplateEditorTests.region(t, 140, 55)
        #expect(RefineCells.neighbours(of: sky, in: t).contains(square))
    }

    /// Merge with a neighbour joins exactly the two, the cell it was asked on keeping its paint;
    /// a cell that is no neighbour gives no merge.
    @Test func mergeWithANeighbourJoinsJustTheTwo() throws {
        let t = Self.scene
        let probe = try TemplateEditor.MergeProbe(t)
        var made = 0
        for r in t.regions.indices {
            for n in RefineCells.neighbours(of: r, in: t) {
                guard let edit = RefineCells.merge(r, with: n, in: t, probe: probe) else { continue }
                let (u, outcome) = try TemplateEditorTests.apply(edit, to: t)
                #expect(outcome.regionsMerged == 1 && u.regions.count == t.regions.count - 1, "\(r) with \(n)")
                #expect(outcome.continued[r] == outcome.continued[n])
                #expect(u.palette[Int(u.regions[outcome.continued[r]].colorIndex)] == t.palette[Int(t.regions[r].colorIndex)])
                made += 1
            }
        }
        #expect(made >= t.regions.count, "\(made) merges of \(t.regions.count) cells")
        let apart = try #require(t.regions.indices.lazy.compactMap { r in
            t.regions.indices.first { $0 != r && !RefineCells.neighbours(of: r, in: t).contains($0) }.map { (r, $0) }
        }.first)
        #expect(RefineCells.merge(apart.0, with: apart.1, in: t, probe: probe) == nil)
    }

    /// Move Number moves the cell's roomiest number the way asked, inside the cell; the editor
    /// decides whether it fits there.
    @Test func moveNumberStepsTheNumberTheWayAsked() throws {
        let t = Self.scene
        let sky = try TemplateEditorTests.region(t, 100, 20)
        let before = try #require(RefineCells.anchor(of: sky, in: t))
        var moved = 0
        for direction in RefineCells.Direction.allCases {
            guard let edit = RefineCells.moveNumber(of: sky, direction, in: t) else { continue }
            guard case .moveLabel(let from, let to, _) = edit else { Issue.record("not a moved number: \(edit)"); continue }
            #expect(from == before && t.region(at: to) == sky)
            let way = to - from
            switch direction {
            case .up: #expect(way.y < 0 && way.x == 0)
            case .down: #expect(way.y > 0 && way.x == 0)
            case .left: #expect(way.x < 0 && way.y == 0)
            case .right: #expect(way.x > 0 && way.y == 0)
            }
            let (u, outcome) = try TemplateEditor.apply(edit, to: t)
            if outcome.declined == nil {
                #expect(outcome.labelsMoved == 1)
                #expect(u.labels(ofRegion: sky).contains { simdLength($0.position - to) <= Template.coordinateQuantum })
                moved += 1
            }
        }
        #expect(moved >= 1, "the sky's number moved no way")
        #expect(RefineCells.moveNumber(of: t.regions.count, .up, in: t) == nil)
    }
}
