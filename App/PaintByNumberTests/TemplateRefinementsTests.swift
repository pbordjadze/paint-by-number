import CoreGraphics
import Foundation
import PaintCore
import Testing
@testable import PaintByNumber

/// The Refine step's refinements: the focus a brush paints, how it moves the importance and edge
/// maps, the text corrections, their file, and what they do to a template.
struct TemplateRefinementsTests {
    static func stroke(
        _ kind: TemplateRefinements.Stroke.Kind, _ points: [SIMD2<Float>], radius: Float = 0.1
    ) -> TemplateRefinements.Stroke {
        TemplateRefinements.Stroke(kind: kind, radius: radius, points: points)
    }

    /// A line of text the app found: a rectangle in `TextFinder`'s order.
    static let found: [SIMD2<Float>] = [SIMD2(0.1, 0.1), SIMD2(0.3, 0.1), SIMD2(0.3, 0.15), SIMD2(0.1, 0.15)]

    /// A stroke is +1 (more) or −1 (less) along its path, soft at its edge and nothing beyond it;
    /// a later stroke covers the ones before, and the eraser takes them back to nothing. The
    /// same strokes give the same grid.
    @Test func strokesPaintTheFocusInOrder() throws {
        var refinements = TemplateRefinements()
        #expect(refinements.isEmpty && refinements.focus(width: 10, height: 10) == nil)
        refinements.strokes = [Self.stroke(.more, [SIMD2(0.25, 0.5), SIMD2(0.75, 0.5)])]
        let more = try #require(refinements.focus(width: 100, height: 50))
        #expect(more[25 * 100 + 50] == 1)
        #expect(more[2 * 100 + 50] == 0)
        // The radius is 10 pixels (a tenth of the long side); its outer 35 % fades.
        #expect(more[34 * 100 + 50] > 0 && more[34 * 100 + 50] < 1)

        refinements.strokes.append(Self.stroke(.less, [SIMD2(0.5, 0.5)]))
        refinements.strokes.append(Self.stroke(.erase, [SIMD2(0.3, 0.5)]))
        let focus = try #require(refinements.focus(width: 100, height: 50))
        #expect(focus[25 * 100 + 50] == -1, "A later stroke doesn't cover an earlier one")
        #expect(focus[25 * 100 + 30] == 0, "The eraser didn't clear")
        #expect(focus[25 * 100 + 70] == 1)
        #expect(refinements.focus(width: 100, height: 50) == focus)
        #expect(refinements.changeCount == 3)
    }

    /// More detail raises importance to 1 and strengthens the edge maps, contours too; less
    /// lowers it to `lessImportance` and weakens them; the rest is left as it was.
    @Test func moreAndLessMoveImportanceAndTheEdgeMaps() throws {
        var refinements = TemplateRefinements()
        refinements.strokes = [Self.stroke(.more, [SIMD2(0.25, 0.5)]), Self.stroke(.less, [SIMD2(0.75, 0.5)])]
        let edges = EdgeMap(width: 100, height: 50, values: [UInt8](repeating: 100, count: 5000))
        let refined = refinements.refining(
            importance: PaintCore.Grid(width: 100, height: 50, repeating: 0.4), lineArt: LineArtInput(edges: edges, contours: edges),
            aspect: 2)
        let importance = try #require(refined.importance)
        #expect(importance[25, 25] == 1)
        #expect(abs(importance[75, 25] - TemplateRefinements.lessImportance) < 1e-6)
        #expect(importance[50, 3] == 0.4)
        let art = try #require(refined.lineArt)
        #expect(art.edges.values[25 * 100 + 25] == 130 && art.edges.values[25 * 100 + 75] == 55)
        #expect(art.contours?.values[25 * 100 + 75] == 55)
        #expect(art.edges.values[3 * 100 + 50] == 100)
    }

    /// Without a map from Vision, strokes brush a neutral one of the photo's shape; with nothing
    /// refined, the inputs pass through as they were.
    @Test func withoutVisionANeutralMapIsBrushed() throws {
        var refinements = TemplateRefinements()
        refinements.strokes = [Self.stroke(.more, [SIMD2(0.5, 0.5)])]
        let neutral = try #require(refinements.refining(importance: nil, lineArt: nil, aspect: 2).importance)
        #expect(neutral.width == 256 && neutral.height == 128)
        #expect(neutral[128, 64] == 1 && neutral[10, 10] == 0.5)

        let edges = EdgeMap(width: 4, height: 2, values: [1, 2, 3, 4, 5, 6, 7, 8])
        let untouched = TemplateRefinements().refining(importance: nil, lineArt: LineArtInput(edges: edges), aspect: 2)
        #expect(untouched.importance == nil && untouched.lineArt?.edges == edges)
    }

    /// A line the painter turned off goes, even found a little differently when regenerated; a
    /// line they marked joins, as a rectangle in `TextFinder`'s order and quantum; the maps stay.
    @Test func textCorrectionsEditTheWriting() throws {
        let edges = EdgeMap(width: 10, height: 10, values: [UInt8](repeating: 9, count: 100))
        var refinements = TemplateRefinements()
        refinements.hiddenText = [Self.found.map { $0 + SIMD2(0.005, 0.002) }]
        let marked = TemplateRefinements.textLine(from: SIMD2(0.8, 0.9), to: SIMD2(0.5, 0.7))
        refinements.addedText = [marked]
        let refined = refinements.refining(importance: nil, lineArt: LineArtInput(edges: edges, writing: [Self.found]), aspect: 1)
        #expect(refined.lineArt?.writing == [marked])
        #expect(refined.importance == nil && refined.lineArt?.edges == edges)

        let quantum = Float(TextFinder.quantum)
        #expect(marked.count == 4 && marked.allSatisfy { ($0 * quantum).rounded() == $0 * quantum })
        #expect(marked[0].x < marked[1].x && marked[1].y < marked[2].y && marked[3].x == marked[0].x)
        #expect(abs(marked[0].x - 0.5) < 1 / quantum && abs(marked[2].y - 0.9) < 1 / quantum)
        #expect(!TemplateRefinements.sameLine(Self.found, marked))
    }

    /// The file round-trips, and a stroke or field it can't read (from a newer app) is left out
    /// rather than costing the rest.
    @Test func refinementsRoundTripAndDecodeTolerantly() throws {
        var refinements = TemplateRefinements()
        refinements.strokes = [Self.stroke(.more, [SIMD2(0.2, 0.3), SIMD2(0.4, 0.5)]), Self.stroke(.erase, [SIMD2(0.3, 0.4)])]
        refinements.hiddenText = [Self.found]
        refinements.addedText = [TemplateRefinements.textLine(from: SIMD2(0.1, 0.6), to: SIMD2(0.4, 0.65))]
        let data = try JSONEncoder().encode(refinements)
        #expect(try JSONDecoder().decode(TemplateRefinements.self, from: data) == refinements)

        let newer = #"{"strokes":[{"kind":"blur","radius":0.1,"points":[[0.5,0.5]]},"#
            + #"{"kind":"less","radius":0.1,"points":[[0.5,0.5]]}],"hiddenText":"?","future":1}"#
        let tolerant = try JSONDecoder().decode(TemplateRefinements.self, from: Data(newer.utf8))
        #expect(tolerant.strokes == [Self.stroke(.less, [SIMD2(0.5, 0.5)])])
        #expect(tolerant.hiddenText.isEmpty && tolerant.addedText.isEmpty)
        #expect(try JSONDecoder().decode(TemplateRefinements.self, from: Data("{}".utf8)).isEmpty)
    }

    /// What is brushed shows in the template: more detail down one half leaves it more regions
    /// than less detail there does.
    @Test func brushedDetailMovesTheRegions() throws {
        let url = try #require(Bundle.main.url(forResource: "great-wave", withExtension: "jpg"))
        let photo = try PhotoLoader.load(url: url, maxPixelSize: 480)
        let aspect = Float(photo.width) / Float(photo.height)
        func regionsOnTheLeft(_ kind: TemplateRefinements.Stroke.Kind) throws -> Int {
            var refinements = TemplateRefinements()
            refinements.strokes = [Self.stroke(kind, [SIMD2(0.22, 0.05), SIMD2(0.22, 0.95)], radius: 0.18)]
            let inputs = refinements.refining(importance: nil, lineArt: nil, aspect: aspect)
            let template = try TemplateGenerator(settings: GenerationSettings(colorCount: 16, detail: 0.3))
                .generate(from: photo, importance: inputs.importance, cancel: .none)
                .template
            return Set(template.labels.filter { $0.position.x < 0.4 * Float(template.width) }.map(\.region)).count
        }
        let more = try regionsOnTheLeft(.more), less = try regionsOnTheLeft(.less)
        #expect(Double(more) > 1.5 * Double(less), "More detail left \(more) regions, less detail \(less)")
    }
}
