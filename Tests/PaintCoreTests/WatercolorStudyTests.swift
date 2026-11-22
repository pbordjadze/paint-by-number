import Foundation
import Testing
@testable import PaintCore

/// Watercolor's Making Of as a study sheet (painting-company row 373): the painting's paints
/// tried on paper of its size, never the painting itself.
@Suite struct WatercolorStudyTests {
    static let painting = WatercolorTests.template

    @Test func theStudyTriesThePaintingsPaintsAndNotItsPicture() throws {
        let p = Self.painting
        let study = try WatercolorStudy(painting: p)
        let t = study.template
        #expect(t.width == p.width && t.height == p.height)
        // Every area but the paper is one of the painting's paints, under the painting's number.
        let used = Set(p.regions.map(\.colorIndex))
        for (r, region) in t.regions.enumerated() where r != study.paper {
            #expect(used.contains(region.colorIndex))
            #expect(t.palette[Int(region.colorIndex)] == p.palette[Int(region.colorIndex)])
        }
        // The study is its own few shapes, not the painting's areas.
        #expect(t.regions.count <= WatercolorStudy.chartPaints + 3 + 1 + 2 + 1)
        #expect(study.chart.count == min(WatercolorStudy.chartPaints, used.count))
        #expect(!study.band.isEmpty && study.stripe != nil && !study.discs.isEmpty)
        // The paper has no number; every other area has one.
        #expect(t.regions[study.paper].labelCount == 0)
        #expect(!t.labels.contains { Int($0.region) == study.paper })
        for r in t.regions.indices where r != study.paper { #expect(t.regions[r].labelCount > 0) }
    }

    @Test func itPlaysEveryPassageAndNeverPaintsThePaper() throws {
        let study = try WatercolorStudy(painting: Self.painting)
        func play() -> WatercolorSim {
            let sheet = WatercolorSheet(template: study.template, seed: 9)
            let plan = WatercolorMakingOf(study: study, sheet: sheet)
            #expect(!plan.log.taps.contains { $0.region == study.paper })
            // Blooms are water into a wash already laid.
            let painted = plan.log.taps.filter(\.paint)
            for drop in plan.log.taps where !drop.paint {
                #expect(painted.contains { $0.region == drop.region && $0.step < drop.step })
            }
            let sim = WatercolorSim(sheet: sheet)
            var cursor = 0, frame = 0
            while !plan.isSettled(sim, cursor: cursor), frame < 600 {
                plan.play(sim, to: plan.step(at: Double(frame) / 30), cursor: &cursor)
                frame += 1
            }
            #expect(Double(frame) / 30 < 10)
            #expect(!sim.laid[study.paper])
            #expect(sim.laidCount == study.template.regions.count - 1)
            return sim
        }
        #expect(WatercolorTests.digest(play()) == WatercolorTests.digest(play()))
    }
}
