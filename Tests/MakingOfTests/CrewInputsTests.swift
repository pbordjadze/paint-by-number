import Foundation
import PaintCore
import Testing
@testable import MakingOf

/// `CrewInputs.make` against `making_of_inputs.py`, which made `Fixtures/show-small/inputs-small.json`
/// from the same pictures and template: every number equal, not close.
@Suite struct CrewInputsTests {
    private func make(_ small: SmallShow, seed: UInt64 = SmallShow.seed, exitBand: Double = CrewInputs.defaultExitBand) throws -> (CrewInputs, [PaintSeed]) {
        try CrewInputs.make(small.pictures, small.show, spec: small.spec, seed: seed, exitBand: exitBand)
    }

    @Test func theSmallShowsInputsAreThePythons() throws {
        let small = try SmallShow()
        let (inputs, seeds) = try make(small)
        let want = small.expected.inputs.crewInputs
        #expect(inputs.pets == want.pets)
        #expect(inputs.candidates == want.candidates)
        #expect(inputs.strokes == want.strokes)
        #expect(inputs == want)
        #expect(seeds == small.expected.paintSeeds)
        #expect(small.expected.seed == SmallShow.seed)
    }

    @Test func homesAreTheFirstSpotsOfTheFirstStep() throws {
        let small = try SmallShow()
        let (inputs, _) = try make(small)
        #expect(inputs.candidates[0].prefix(3).map { [Int($0.x), Int($0.y)] } == small.expected.trace.homes)
        #expect(inputs.pets.map(\.start) == Array(inputs.candidates[0].prefix(3)))
        #expect(inputs.candidates.map(\.count) == [15, 12, 24, 12, 0, 12])
        #expect(inputs.pets.map(\.id) == small.spec.crew.pets)
    }

    @Test func aSecondCallIsTheFirst() throws {
        let small = try SmallShow()
        let first = try make(small), second = try make(small)
        #expect(first.0 == second.0 && first.1 == second.1)
    }

    @Test func theSeedChangesTheSpotsButNotTheLinesOrTheSeedsPaints() throws {
        let small = try SmallShow()
        let a = try make(small, seed: 7).0, b = try make(small, seed: 8).0
        #expect(a.seed == 7 && b.seed == 8)
        #expect(a.strokes == b.strokes && a.frameHeight == b.frameHeight && a.petHeight == b.petHeight)
        #expect(a.candidates[0] != b.candidates[0] && a.candidates[3] != b.candidates[3])
        #expect(a.candidates[2] != b.candidates[2])
    }

    @Test func eachStepsDrawsAreItsOwn() throws {
        // a step's spots come from its own stream: changing the pictures of another step's weights can't move them
        let small = try SmallShow()
        let (inputs, _) = try make(small)
        var rng = ShowStreams(seed: SmallShow.seed).stream(.spots, 1)
        let uniform = Sampling.sampleStops(
            weights: StopWeights(pictures: small.pictures, template: small.show, petHeight: inputs.petHeight, margin: small.spec.crew.margin).uniform(),
            width: small.pictures.width, count: 12, spacing: 0.1 * 216, rng: &rng)
        #expect(inputs.candidates[1] == uniform.map { Point(Double($0.x), Double($0.y)) })
    }

    @Test func spotsStayInTheRoomAndSeedsInTheirGrid() throws {
        let small = try SmallShow()
        let (inputs, seeds) = try make(small)
        let room = StopWeights(pictures: small.pictures, template: small.show, petHeight: inputs.petHeight, margin: small.spec.crew.margin)
        for k in [0, 1, 3, 5] {
            for spot in inputs.candidates[k] {
                #expect(room.columns.contains(Int(spot.x)) && room.rows.contains(Int(spot.y)), "step \(k) spot \(spot)")
            }
        }
        for seed in seeds {
            #expect(seed.x >= 10 && seed.x < 206 && seed.y >= 21 && seed.y < 136)
            #expect(Int(seed.x - 10) % 6 == 0 && Int(seed.y - 21) % 6 == 0)
        }
        // landing one after another, from a little after the third step begins
        #expect(seeds[0].time == small.spec.timing.intro + 2 * small.spec.timing.step + 0.12)
        #expect(zip(seeds, seeds.dropFirst()).allSatisfy { $0.time < $1.time })
    }

    @Test func sizesAndSpotsAreAtThePlanFilesPrecision() throws {
        let small = try SmallShow()
        let (inputs, _) = try make(small)
        let points = Array(inputs.candidates.joined()) + Array(inputs.strokes.joined())
        for value in [inputs.width, inputs.height, inputs.petHeight, inputs.frameHeight] + points.flatMap({ [$0.x, $0.y] }) {
            #expect(ExactMath.quantize(value, decimals: 2) == value)
        }
        #expect(ExactMath.quantize(inputs.intro, decimals: 4) == inputs.intro && ExactMath.quantize(inputs.step, decimals: 4) == inputs.step)
        #expect(inputs.petHeight == 23.04 && inputs.frameHeight == 144 + 232)
        #expect(try make(small, exitBand: 100).0.frameHeight == 244)
    }

    @Test func aTemplateOfAnotherPictureIsRefused() throws {
        let small = try SmallShow()
        let other = ShowTemplate(small.template, width: 100, height: 67)
        #expect(throws: CrewInputsError.self) {
            try CrewInputs.make(small.pictures, other, spec: small.spec, seed: 7)
        }
    }

    @Test func theCrewCanBePlannedFromThem() throws {
        let small = try SmallShow()
        let (inputs, _) = try make(small)
        let plan = try CrewPlan(inputs, spec: small.spec)
        #expect(plan.pets.map(\.id) == small.spec.crew.pets)
        #expect(plan.visits.count == 6 && !plan.traces.isEmpty)
    }

    @Test func moreBandsThanPetsAndMorePetsThanBands() throws {
        let small = try SmallShow()
        var spec = small.spec
        spec.crew.pets = ["a", "b", "c", "d", "e", "f", "g"]
        let (inputs, _) = try CrewInputs.make(small.pictures, small.show, spec: spec, seed: 7)
        #expect(inputs.pets.count == 7 && inputs.candidates[1].count == 28)
        // three bands left to right: the first holds 3 of 7 pets (0, 1, 2), the second 2 (3, 4), the third 2
        let homes = inputs.pets.map(\.start)
        let edges = [0.12 * 216, 0.12 * 216 + (0.88 * 216 - 0.12 * 216) / 3, 0.12 * 216 + 2 * (0.88 * 216 - 0.12 * 216) / 3, 0.88 * 216]
        for (i, home) in homes.enumerated() {
            let band = i * 3 / 7
            #expect(home.x >= edges[band].rounded(.down) && home.x < edges[band + 1].rounded(.up), "pet \(i) at \(home)")
        }
        spec.crew.bands = 1
        #expect(try CrewInputs.make(small.pictures, small.show, spec: spec, seed: 7).0.pets.count == 7)
    }
}

/// The pictures no photo makes: nothing to draw from, nowhere to stand.
@Suite struct CrewInputsFallbackTests {
    private func flat(_ width: Int, _ height: Int, structure: UInt8 = 0) throws -> ShowPictures {
        let color = Plane<SIMD4<UInt8>>(width: width, height: height, repeating: SIMD4(120, 130, 140, 255))
        return try ShowPictures(
            working: color, structure: Plane(width: width, height: height, repeating: structure), smoothed: color, palette: color,
            simplified: color)
    }

    private func spec(pets: Int) throws -> ShowSpec {
        var spec = try ShowSpec(json: shippedSpecData())
        spec.crew.pets = (0..<pets).map { "pet-\($0)" }
        return spec
    }

    @Test func aFlatPictureHasOnePaintAndOneSeed() throws {
        let small = try SmallShow()
        let pictures = try flat(216, 144)
        let (inputs, seeds) = try CrewInputs.make(pictures, ShowTemplate(small.template, width: 216, height: 144), spec: small.spec, seed: 7)
        #expect(seeds.count == 1 && seeds[0].paint == 0)
        #expect(inputs.candidates[2].count == 1)
        #expect(inputs.candidates[1].count == 12)
        _ = try CrewPlan(inputs, spec: small.spec)
    }

    private func points(_ pairs: [[Double]]) -> [Point] { pairs.map { Point($0[0], $0[1]) } }

    @Test func aPictureWithLittleRoomIsDrawnFromEverywhere() throws {
        // 20 x 14: rows 3..<6 and columns 2..<18 are the room, too narrow for a pet's height. The spots
        // are Python's, which has the same fallbacks (the cases are in test_making_of_inputs.py too).
        let small = try SmallShow()
        let (inputs, seeds) = try CrewInputs.make(
            flat(20, 14), ShowTemplate(small.template, width: 20, height: 14), spec: small.spec, seed: 7)
        #expect(inputs.candidates == [
            points([[3, 5], [10, 3], [16, 3], [9, 5], [15, 4], [4, 3], [5, 5], [11, 4], [13, 3], [2, 4], [8, 3], [17, 5], [13, 5], [17, 3], [7, 5]]),
            points([[12, 4], [4, 3], [4, 5], [14, 5], [6, 5], [16, 4], [6, 3], [10, 4], [8, 4], [14, 3], [2, 3], [2, 5]]),
            points([[13, 5]]),
            points([[6, 3], [15, 5], [11, 4], [17, 5], [17, 3], [4, 3], [13, 4], [15, 3], [2, 4], [8, 4], [4, 5], [6, 5]]),
            [],
            points([[3, 4], [5, 3], [17, 5], [10, 5]]),     // the four numbers' places: nothing else weighs anything
        ])
        #expect(seeds == [PaintSeed(time: 5.72, x: 13, y: 5, paint: 0)])
    }

    @Test func aPictureSmallerThanTheCrewSharesItsHomes() throws {
        // four cells, three bands of seven pets: each band finds the four cells and no more, so twelve
        // homes for twenty pets, who go round them
        let small = try SmallShow()
        let (inputs, seeds) = try CrewInputs.make(
            flat(2, 2), ShowTemplate(small.template, width: 2, height: 2), spec: spec(pets: 20), seed: 7)
        let homes = points([[0, 0], [0, 1], [1, 0], [1, 1], [1, 1], [0, 0], [1, 0], [0, 1], [1, 1], [1, 0], [0, 1], [0, 0]])
        #expect(Array(inputs.candidates[0].prefix(12)) == homes)
        #expect(inputs.candidates.map(\.count) == [16, 4, 0, 4, 0, 4] && seeds.isEmpty)
        #expect(inputs.pets.map(\.start) == (0..<20).map { homes[$0 % 12] })
    }

    @Test func noPetsIsRefused() throws {
        let small = try SmallShow()
        var none = small.spec
        none.crew.pets = []
        #expect(throws: CrewInputsError.self) { try CrewInputs.make(small.pictures, small.show, spec: none, seed: 7) }
    }

    @Test func theRealPipelineFeedsTheWholeChain() throws {
        let recorder = InputsSnapshotRecorder()
        let output = try TemplateGenerator(settings: GenerationSettings(colorCount: 8, detail: 0.5))
            .generate(from: InputsTestPhoto.make(), cancel: .none, observer: recorder.receive)
        let pictures = try ShowPictures(snapshots: recorder.values)
        let template = ShowTemplate(output.template, width: pictures.width, height: pictures.height)
        #expect(template.scale == 1 && !template.strokes.isEmpty)
        let spec = try ShowSpec(json: shippedSpecData())
        let (inputs, seeds) = try CrewInputs.make(pictures, template, spec: spec, seed: 11)
        #expect(inputs.width == Double(output.template.width) && inputs.strokes.count == template.strokes.count)
        #expect(!seeds.isEmpty && seeds.count <= 8)
        let plan = try CrewPlan(inputs, spec: spec)
        #expect(plan.pets.count == 3)
        let again = try CrewInputs.make(pictures, template, spec: spec, seed: 11)
        #expect(again.0 == inputs && again.1 == seeds)
    }

    @Test func aWidePictureThePipelineShrinksScalesItsLines() throws {
        // 1200 x 48 on the canvas, 1024 x 40 in the snapshots
        let recorder = InputsSnapshotRecorder()
        let image = RGBAImage(width: 800, height: 32, fill: SIMD4(60, 120, 180, 255))
        let output = try TemplateGenerator(settings: GenerationSettings(colorCount: 8, detail: 0.5))
            .generate(from: image, cancel: .none, observer: recorder.receive)
        let pictures = try ShowPictures(snapshots: recorder.values)
        #expect(output.template.width == 1200 && pictures.width == 1024 && pictures.height == 40)
        let template = ShowTemplate(output.template, width: pictures.width, height: pictures.height)
        #expect(template.scale == 1024.0 / 1200)
        // the canvas's bottom edge, 48, is 40.96 here: a point just below the picture's last row
        #expect(template.strokes.flatMap(\.points).map(\.y).max()! > Double(pictures.height))
        let spec = try ShowSpec(json: shippedSpecData())
        let (inputs, seeds) = try CrewInputs.make(pictures, template, spec: spec, seed: 7)
        #expect(inputs.width == 1024 && inputs.height == 40 && seeds.count == 1)
        _ = try CrewPlan(inputs, spec: spec)
    }
}
