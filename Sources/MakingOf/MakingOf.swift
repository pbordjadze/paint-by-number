import Foundation
import PaintCore

/// MakingOf: the crew of the making-of show, planned and moved. The show plays after the painter
/// taps Start: three of the app's pets walk over the painter's photo, and each step of the
/// pipeline is revealed where they work (`ShowSpec`, `making-of.json`).
///
/// `CrewPlan` hands the jobs out (who works where, when, and which lines are drawn by walking
/// along them) from plain data, and `PetPlan.state(at:)` says where a pet is, which sprite row
/// and frame it shows, how it squashes and leans, at any moment. Both are pure functions of their
/// inputs: the same photo, spots, strokes and seed give the same show on any device, from
/// PaintCore's `SplitMix64`, the only random source.
///
/// `tools/factory/making_of_pets.py` is the reference: this is its port, line by line, and
/// `Tests/MakingOfTests/Fixtures/plan-parrots.json` proves the two equal. Change them together
/// and regenerate the fixture, from the repository root (`$OUT`: any folder outside it; `$PBN`: a
/// built pbn; the clip tool needs numpy, Pillow and node with resvg, see
/// `tools/factory/making_of_layers.py`):
///
///     python3 -c "from PIL import Image; Image.open('Tests/Corpus/parrots.jpg').convert('RGB').save('$OUT/parrots.ppm')"
///     for n in contours drawing; do python3 -c "from PIL import Image; Image.open('tools/baseline/lines/parrots-$n.png').convert('L').save('$OUT/parrots-$n.pgm')"; done
///     $PBN generate $OUT/parrots.ppm $OUT/gen --colors 24 --detail 0.5 --line-style coloringBook \
///       --edges $OUT/parrots-contours.pgm --lines $OUT/parrots-drawing.pgm --snapshots $OUT/gen/snap
///     python3 tools/factory/making_of_clip.py $OUT/gen $OUT/gen/snap /dev/null \
///       --pets App/PaintByNumber/Resources --plan-json Tests/MakingOfTests/Fixtures/plan-parrots.json
///
/// Planning draws every random number from SplitMix64, in a fixed order: the pets' order of
/// appearing, their order of waving, each job's work time as the steps are planned, then each
/// walk's bend.
public struct CrewPlan: Sendable, Equatable {
    /// The step whose lines the pets draw by walking along them: `ShowSpec.StepID.ink`'s place,
    /// which the spec insists on.
    public static let inkStep = 4

    public let pets: [PetPlan]
    /// For each step, the points its change spreads from.
    public let visits: [[Visit]]
    /// The lines drawn by walking, in the ink step.
    public let traces: [Trace]

    public init(_ inputs: CrewInputs, spec: ShowSpec) throws {
        try Self.validate(inputs)
        let steps = ShowSpec.StepID.allCases.count
        let h = inputs.petHeight
        let starts = (0..<steps).map { inputs.intro + Double($0) * inputs.step }
        let end = inputs.intro + Double(steps) * inputs.step
        var rng = SplitMix64(seed: inputs.seed)
        let order = rng.permutation(inputs.pets.count)
        let wave = rng.permutation(inputs.pets.count)
        var pets: [PetPlan] = []
        for (i, member) in inputs.pets.enumerated() {
            let appear = 0.04 + 0.035 * Double(order[i])
            let start = Stop(
                arrive: appear, leave: appear + 0.05, x: member.start.x, y: member.start.y, kind: .appear, path: nil)
            pets.append(PetPlan(
                id: member.id, start: start, height: h, stepEnds: starts.map { $0 + inputs.step }, spec: spec))
        }
        var planner = Planner(
            pets: pets, rng: rng, crew: spec.crew, size: Point(inputs.width, inputs.height), petHeight: h,
            beat: inputs.step * spec.crew.beat, origin: inputs.intro)
        let strokes = inputs.strokes.map(Polyline.init)
        var visits: [[Visit]] = []
        var traces: [Trace] = []
        for k in 0..<steps {
            let seeds: [Visit]
            if k == Self.inkStep {
                (seeds, traces) = planner.trace(from: starts[k], to: starts[k] + inputs.step - 0.15, strokes: strokes, k: k)
            } else {
                seeds = planner.step(
                    from: starts[k], to: starts[k] + inputs.step - 0.15, candidates: inputs.candidates[k], k: k)
            }
            visits.append(seeds.isEmpty ? [Visit(time: starts[k] + 0.1, x: inputs.width / 2, y: inputs.height / 2)] : seeds)
        }
        planner.farewell(waveAt: wave.map { end - 0.05 + 0.03 * Double($0) }, frameHeight: inputs.frameHeight)
        planner.finishPets()
        self.pets = planner.pets
        self.visits = visits
        self.traces = traces
    }

    private static func validate(_ inputs: CrewInputs) throws {
        func fail(_ why: String) -> CrewInputsError { CrewInputsError(description: why) }
        let sizes = [inputs.width, inputs.height, inputs.petHeight, inputs.step, inputs.frameHeight]
        guard sizes.allSatisfy({ $0.isFinite && $0 > 0 }), inputs.intro.isFinite, inputs.intro >= 0 else {
            throw fail("sizes and times must be finite, and the sizes and the step positive")
        }
        guard (1...20).contains(inputs.pets.count) else { throw fail("a crew is one to twenty pets") }
        guard inputs.candidates.count == ShowSpec.StepID.allCases.count else {
            throw fail("candidates must list the spots of each of the \(ShowSpec.StepID.allCases.count) steps")
        }
        let points = inputs.pets.map(\.start) + inputs.candidates.joined() + inputs.strokes.joined()
        guard points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { throw fail("every spot must be finite") }
    }
}

/// What a crew is planned from, all plain data. Spots and sizes are in pixels of the working
/// image, times in seconds.
public struct CrewInputs: Sendable, Equatable {
    public struct Member: Sendable, Equatable {
        public var id: String
        /// Where it pops in.
        public var start: Point

        public init(id: String, start: Point) {
            self.id = id
            self.start = start
        }
    }

    public var width: Double
    public var height: Double
    /// A pet's height in pixels: the spec's crew `height` times the picture's shorter side.
    public var petHeight: Double
    public var intro: Double
    /// The seconds each of the six steps lasts (the spec's `timing.step`, unless something else
    /// sets the pace).
    public var step: Double
    public var seed: UInt64
    /// The pets, in crew order.
    public var pets: [Member]
    /// For each step, the spots its jobs are done at (the ink step's are ignored: its jobs are the
    /// strokes).
    public var candidates: [[Point]]
    /// The template's lines, which the ink step draws by walking along them.
    public var strokes: [[Point]]
    /// The video frame's height, which the farewell walks off the bottom of.
    public var frameHeight: Double

    public init(
        width: Double, height: Double, petHeight: Double, intro: Double, step: Double, seed: UInt64,
        pets: [Member], candidates: [[Point]], strokes: [[Point]], frameHeight: Double
    ) {
        self.width = width
        self.height = height
        self.petHeight = petHeight
        self.intro = intro
        self.step = step
        self.seed = seed
        self.pets = pets
        self.candidates = candidates
        self.strokes = strokes
        self.frameHeight = frameHeight
    }
}

/// The inputs a crew can't be planned from.
public struct CrewInputsError: Error, Equatable, CustomStringConvertible {
    public let description: String
}
