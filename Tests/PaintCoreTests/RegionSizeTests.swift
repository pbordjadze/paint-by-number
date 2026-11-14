import Foundation
import Testing
@testable import PaintCore

/// `Template.inscribedRadius(ofRegion:upTo:)`: a region's size, whatever room its number was
/// left where it moved to (`Region.inscribedRadius`).
@Suite("Region size")
struct RegionSizeTests {
    /// Two bands, each 120 by 40.
    static let bands = VectorizerTests.segmentation(width: 120, height: 80, classes: (0..<120 * 80).map { UInt32($0 / (120 * 40)) })

    static func vectorize(_ keepOut: LabelKeepOut) throws -> Template {
        try Vectorizer.vectorizeWithStats(Self.bands, settings: GenerationSettings(), keepOut: keepOut, cancel: .none, clock: StageClock()).template
    }

    /// Where every number sits at its pole, a region's size is exactly what the template stores.
    @Test func aRegionWithItsNumberAtThePoleIsItsStoredRadius() throws {
        for t in [TemplateEditorTests.scene, try TemplateEditorTests.richBook(), try Self.vectorize(LabelKeepOut(rects: []))] {
            for r in t.regions.indices {
                #expect(t.inscribedRadius(ofRegion: r) == t.regions[r].inscribedRadius, "region \(r)")
                #expect(t.inscribedRadius(ofRegion: r, upTo: 3) == t.regions[r].inscribedRadius, "region \(r)")
            }
        }
    }

    /// Writing across the middle of the top band moves its number into the strip above or below
    /// it, 16 high: the stored radius is that strip's, the region is as big as it was.
    @Test func aNumberMovedOffWritingLeavesItsRegionItsSize() throws {
        let plain = try Self.vectorize(LabelKeepOut(rects: []))
        let kept = try Self.vectorize(LabelKeepOut(rects: [SIMD4(0, 16, 120, 24)]))
        let top = Int(plain.regionMap[60, 20]), bottom = Int(plain.regionMap[60, 60])
        #expect(abs(plain.regions[top].inscribedRadius - 20) < 0.5)
        #expect(abs(kept.regions[top].inscribedRadius - 8) < 0.5, "\(kept.regions[top].inscribedRadius)")
        #expect(kept.labels(ofRegion: top).first?.radius == kept.regions[top].inscribedRadius)
        #expect(kept.polygons(ofRegion: top) == plain.polygons(ofRegion: top))

        let size = kept.inscribedRadius(ofRegion: top)
        #expect(abs(size - plain.regions[top].inscribedRadius) <= Float(Vectorizer.labelPrecision), "\(size)")
        // The other band's number never moved.
        #expect(kept.inscribedRadius(ofRegion: bottom) == plain.regions[bottom].inscribedRadius)

        // With a limit the search stops at the first disc over it; a stored radius over the
        // limit is answered as it is.
        #expect(kept.inscribedRadius(ofRegion: top, upTo: 10) > 10)
        #expect(kept.inscribedRadius(ofRegion: top, upTo: 30) == size)
        #expect(kept.inscribedRadius(ofRegion: top, upTo: 5) == kept.regions[top].inscribedRadius)
        #expect(try Template(encoded: kept.encoded()).inscribedRadius(ofRegion: top) == size)
    }

    /// Move Number: the number sized for the room where the painter put it, its cell no smaller.
    @Test func aNumberThePainterMovedLeavesItsRegionItsSize() throws {
        let t = TemplateEditorTests.scene
        let sky = try TemplateEditorTests.region(t, 104, 30)
        let label = try #require(t.labels(ofRegion: sky).first)
        let u = try TemplateEditorTests.apply(.moveLabel(from: label.position, to: SIMD2(100, 64)), to: t).0
        #expect(abs(u.regions[sky].inscribedRadius - 8) < 0.5)
        #expect(label.radius > 12)
        #expect(abs(u.inscribedRadius(ofRegion: sky) - label.radius) <= Float(Vectorizer.labelPrecision))
        #expect(u.inscribedRadius(ofRegion: sky, upTo: 10) > 10)
    }

    /// A region without an outline (a template with no vector geometry) has only what it stores.
    @Test func aRegionWithoutAnOutlineKeepsItsStoredRadius() {
        let blank = Template(
            width: 10, height: 10, colorSpace: .sRGB, palette: [],
            regions: [Region(colorIndex: 0, area: 100, bounds: .empty, inscribedRadius: 2)],
            points: [], edges: [], ringEdges: [], rings: [], labels: [], mesh: FillMesh(),
            regionMap: RegionMap(width: 10, height: 10, repeating: 0))
        #expect(blank.inscribedRadius(ofRegion: 0) == 2)
    }

    /// Auto's tiny regions are counted by size: a wide region whose number has little room where
    /// it moved to is no crumb.
    @Test func autoCountsTinyRegionsBySize() throws {
        let image = TestScenes.scene(width: 240, height: 160)
        let output = try TemplateGenerator().generate(from: image, cancel: .none)
        let t = output.template
        let working = Resample.area(image, width: t.width, height: t.height)
        let importance = AutoSettings.importance(for: working, map: nil)
        let wide = try #require(t.regions.indices.max { t.regions[$0].inscribedRadius < t.regions[$1].inscribedRadius })
        #expect(t.regions[wide].inscribedRadius > 10)
        var squeezed = output
        squeezed.template.regions[wide].inscribedRadius = 2.5
        squeezed.template.labels[Int(t.regions[wide].labelStart)].radius = 2.5
        for taste in [AutoTaste.fidelity, .finished] {
            let before = AutoSettings.score(output, working: working, importance: importance, preference: .relaxed, taste: taste)
            let after = AutoSettings.score(squeezed, working: working, importance: importance, preference: .relaxed, taste: taste)
            #expect(after.tinyRegions == before.tinyRegions && after.subjectTinyRegions == before.subjectTinyRegions)
        }
    }
}
