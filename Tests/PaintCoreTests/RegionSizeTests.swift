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
        #expect(kept.measuredRadius(ofRegion: top).complete)
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

    /// The search stops at the first disc over the limit, so its answer then is only a lower
    /// bound: a square lobe 60 across on an arm 10 wide, its number in the arm with little room.
    /// The first spots tried are in the arm or at the lobe's rim, wide enough for a limit of 4;
    /// a limit of 40 finds the lobe's middle.
    @Test func aLimitedSearchAnswersOnlyThatTheRegionIsBigger() throws {
        let w = 180, h = 80
        let classes = (0..<w * h).map { i -> UInt32 in
            let x = i % w, y = i / w
            let arm = (10..<170).contains(x) && (35..<45).contains(y), lobe = (110..<170).contains(x) && (10..<70).contains(y)
            return arm || lobe ? 0 : 1
        }
        var t = try VectorizerTests.vectorize(VectorizerTests.segmentation(width: w, height: h, classes: classes))
        let shape = Int(t.regionMap[30, 40])
        #expect(abs(t.regions[shape].inscribedRadius - 30) < 1)
        t.regions[shape].inscribedRadius = 3
        t.labels[Int(t.regions[shape].labelStart)] = Label(position: SIMD2(30, 40), radius: 3, region: UInt32(shape))

        let low = t.measuredRadius(ofRegion: shape, upTo: 4)
        #expect(low.radius > 4 && low.radius < 20, "\(low)")
        #expect(low.complete)
        let whole = t.measuredRadius(ofRegion: shape, upTo: 40)
        #expect(abs(whole.radius - 30) < 1 && whole.complete, "\(whole)")
        #expect(abs(t.inscribedRadius(ofRegion: shape) - 30) < 1)
    }

    /// A disc the search saw just over the limit is over it as a Float too.
    @Test func aDiscOverTheLimitStaysOverItOnceRounded() throws {
        var t = try Self.vectorize(LabelKeepOut(rects: []))
        let top = Int(t.regionMap[60, 20])
        let size = t.regions[top].inscribedRadius
        t.regions[top].inscribedRadius = 3
        for limit in [size.nextDown, size.nextDown.nextDown, size - 0.001] {
            #expect(t.inscribedRadius(ofRegion: top, upTo: limit) > limit)
        }
    }

    /// The search's work is bounded. Grout 2 wide around 900 tiles, each a hole of its outline:
    /// to show that it holds no larger disc than its number's would take hundreds of thousands
    /// of spots, each measured against every vertex. The search runs out and the grout reads as
    /// it is stored (or as the widest spot found, a crossing), as it did before regions were
    /// measured; so does a long thin wave. The tiles, and every ordinary region, are measured
    /// to the end.
    @Test func aSearchThatRunsOutOfWorkAnswersTheStoredRadius() throws {
        let side = 240
        let grid = (0..<side * side).map { i -> UInt32 in (i % side) % 8 < 2 || (i / side) % 8 < 2 ? 0 : 1 }
        let tiled = try VectorizerTests.vectorize(VectorizerTests.segmentation(width: side, height: side, classes: grid))
        let grout = Int(tiled.regionMap[0, 0])
        #expect(tiled.regions[grout].ringCount > 800)
        for limit in [Float.infinity, 5] {
            let measured = tiled.measuredRadius(ofRegion: grout, upTo: limit)
            // Never more than grout 2 wide holds at a crossing, its tiles' corners rounded.
            #expect(!measured.complete, "\(measured)")
            #expect(measured.radius >= tiled.regions[grout].inscribedRadius && measured.radius < 2.5, "\(measured)")
        }
        let tile = Int(tiled.regionMap[5, 5])
        #expect(tiled.measuredRadius(ofRegion: tile).complete)

        let w = 600, h = 200
        let wave = (0..<w * h).map { i -> UInt32 in
            let x = Double(i % w), y = Double(i / w)
            return abs(y - (100 + 30 * sin(x / 30))) < 1.5 ? 0 : 1
        }
        let waved = try VectorizerTests.vectorize(VectorizerTests.segmentation(width: w, height: h, classes: wave))
        let strip = Int(waved.regionMap[0, 100])
        #expect(waved.regionMap[599, Int(100 + 30 * sin(599.0 / 30))] == UInt32(strip), "one strip across the canvas")
        let measured = waved.measuredRadius(ofRegion: strip)
        #expect(!measured.complete, "\(measured)")
        #expect(measured.radius >= waved.regions[strip].inscribedRadius && measured.radius < 2, "\(measured)")
        // The wide regions beside it, asked with a limit as a tap asks, show a disc at once.
        for r in waved.regions.indices where r != strip {
            let beside = waved.measuredRadius(ofRegion: r, upTo: 10)
            #expect(beside.complete && beside.radius > 10)
        }

        // Ordinary templates never run out.
        for t in [TemplateEditorTests.scene, try TemplateEditorTests.richBook()] {
            for r in t.regions.indices { #expect(t.measuredRadius(ofRegion: r).complete, "region \(r)") }
        }
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
