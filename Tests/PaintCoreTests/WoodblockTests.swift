import Foundation
import Testing
@testable import PaintCore

/// Woodblock (painting-company row 375): the mirrored template, the blocks, the carving that
/// never cuts what stays, and the print.
@Suite("Woodblock")
struct WoodblockTests {
    /// The line-art scene (`LineArtTests`: a disc, a square, a horizon) as a coloring book.
    static func template() throws -> Template {
        try LineArtTests.generate().template
    }

    @Test func aMirroredTemplateIsValidAndMirrorsBack() throws {
        let t = try Self.template()
        expectValid(t)
        let m = t.mirrored()
        expectValid(m)
        #expect(m.mirrored() == t)
        // A pixel and its mirror hold the same region.
        #expect(m.regionMap[0, 10] == t.regionMap[t.width - 1, 10])
        #expect(m.regions.map(\.area) == t.regions.map(\.area))
    }

    @Test func blocksAreTheKeyThenThePaintsLightToDark() throws {
        let plan = WoodblockPlan(template: try Self.template())
        #expect(plan.blocks.first?.kind == .key)
        let colors = plan.blocks.filter { $0.kind == .color }
        #expect(!colors.isEmpty)
        #expect(colors.map(\.number) == Array(1...colors.count), "numbered as the canvas numbers its paints")
        let lightness = colors.map { plan.template.palette[$0.paint!].oklab.x }
        #expect(lightness == lightness.sorted(by: >))
        // The scene's sky fills its top: a bokashi block shades it last.
        #expect(plan.blocks.last?.kind == .bokashi)
    }

    @Test func eachAreaIsNumberedOnce() throws {
        let t = try Self.template()
        let plan = WoodblockPlan(template: t)
        expectValid(plan.template)
        #expect(plan.template.regions.allSatisfy { $0.labelCount == 1 })
        #expect(plan.template.labels.count == plan.template.regions.count)
        for (i, r) in plan.template.regions.enumerated() {
            #expect(Int(plan.template.labels[Int(r.labelStart)].region) == i)
        }
    }

    @Test func theToolNeverCutsWhatStays() throws {
        let plan = WoodblockPlan(template: try Self.template())
        for b in plan.blocks.indices {
            let field = WoodblockField(plan: plan, block: b)
            #expect(field.standing > 0, "block \(b) prints something")
            var bench = WoodblockBench(plan: plan)
            // Scribble over the whole block, then tidy.
            let w = Float(bench.width), h = Float(bench.height)
            for k in 0..<40 {
                let y = h * (Float(k) + 0.5) / 40
                bench.carve(from: SIMD2(0, y), to: SIMD2(w, h - y), field: field)
            }
            bench.tidy(field: field)
            for i in 0..<(bench.width * bench.height) where field.stays(i) {
                #expect(bench.carved[2 * i] == 0)
            }
            #expect(bench.carvedFraction(field: field) == 1)
        }
    }

    @Test func aFullPrintWalksEveryStep() throws {
        let plan = WoodblockPlan(template: try Self.template())
        var bench = WoodblockBench(plan: plan)
        var field = WoodblockField(plan: plan, block: 0)
        let paper = bench.sheet
        var steps = 0
        while !bench.isDone(in: plan), steps < 100 {
            let before = bench.block
            bench.finishStep(plan: plan, field: field)
            if bench.block != before, !bench.isDone(in: plan) {
                field = WoodblockField(plan: plan, block: bench.block)
                if plan.blocks[bench.block].kind == .bokashi { bench.startInked(field: field) }
            }
            steps += 1
        }
        #expect(bench.isDone(in: plan))
        #expect(bench.sheet != paper)
        // The print is the sheet's mirror.
        let print = bench.print()
        #expect(print.pixels[0..<4] == bench.sheet[(4 * (bench.width - 1))..<(4 * bench.width)])
    }

    @Test func carvingPastTheShareTidiesAndMovesOn() throws {
        let plan = WoodblockPlan(template: try Self.template())
        let field = WoodblockField(plan: plan, block: 1)
        var bench = WoodblockBench(plan: plan)
        #expect(bench.advanceIfReady(field: field) == nil)
        for y in stride(from: Float(0), to: Float(bench.height), by: 2) {
            bench.carve(from: SIMD2(0, y), to: SIMD2(Float(bench.width), y), field: field)
        }
        #expect(bench.advanceIfReady(field: field) != nil)
        #expect(bench.step == .ink)
        #expect(bench.carvedFraction(field: field) == 1)
    }

    @Test func aLightRubPrintsLessThanAFullOne() throws {
        let plan = WoodblockPlan(template: try Self.template())
        let field = WoodblockField(plan: plan, block: 0)
        func printed(passes: Int) -> Int {
            var bench = WoodblockBench(plan: plan)
            bench.finishStep(plan: plan, field: field)
            bench.finishStep(plan: plan, field: field)
            bench.laySheet()
            for y in stride(from: Float(0), to: Float(bench.height), by: 4) {
                for _ in 0..<passes { bench.rub(from: SIMD2(0, y), to: SIMD2(Float(bench.width), y), radius: 3) }
            }
            bench.peel(plan: plan, field: field)
            return bench.sheet.enumerated().filter { $0.offset % 4 == 0 && $0.element < 128 }.count
        }
        #expect(printed(passes: 1) < printed(passes: 4))
        #expect(printed(passes: 4) > 0)
    }

    @Test func aBenchRoundTripsAndRefusesDamage() throws {
        let plan = WoodblockPlan(template: try Self.template())
        let field = WoodblockField(plan: plan, block: 0)
        var bench = WoodblockBench(plan: plan)
        bench.carve(from: SIMD2(2, 2), to: SIMD2(40, 30), field: field)
        let bytes = bench.encoded()
        #expect(try WoodblockBench(decoding: bytes, plan: plan) == bench)
        #expect(throws: WoodblockBench.CodingError.corrupt) { try WoodblockBench(decoding: Array(bytes.dropLast()), plan: plan) }
        #expect(throws: WoodblockBench.CodingError.notABench) { try WoodblockBench(decoding: [1, 2, 3], plan: plan) }
        var newer = bytes
        newer[4] = WoodblockBench.version + 1
        #expect(throws: WoodblockBench.CodingError.newerVersion) { try WoodblockBench(decoding: newer, plan: plan) }
        var wrongBlock = bytes
        wrongBlock[13] = 99
        #expect(throws: WoodblockBench.CodingError.corrupt) { try WoodblockBench(decoding: wrongBlock, plan: plan) }
        // A bench carved for other blocks (a later build's cut of the photo) isn't this plan's.
        var otherBlocks = bytes
        otherBlocks[17] ^= 0xFF
        #expect(throws: WoodblockBench.CodingError.corrupt) { try WoodblockBench(decoding: otherBlocks, plan: plan) }
    }

    @Test func aPaintAsPaleAsWashiIsLeftBare() throws {
        let plan = WoodblockPlan(template: try Self.template())
        let palette = plan.template.palette
        // Paper paints go last, so the blocks the painter carves are numbered from 1 up.
        let bare = palette.indices.filter { WoodblockPlan.isPaper(palette[$0].oklab) }
        #expect(bare.allSatisfy { $0 >= palette.count - bare.count })
        for b in plan.blocks where b.kind == .color {
            #expect(!WoodblockPlan.isPaper(palette[b.paint!].oklab))
        }
        #expect(WoodblockPlan.isPaper(SIMD3(0.92, 0.01, 0.02)))
        #expect(!WoodblockPlan.isPaper(SIMD3(0.92, 0.08, 0.02)))
    }
}
