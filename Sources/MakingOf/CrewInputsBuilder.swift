import PaintCore

extension CrewInputs {
    /// The pixels below the picture the farewell walks off the bottom of: the video frame's card band.
    public static let defaultExitBand = 232.0

    /// What the crew is planned from, chosen from a generation's pictures and template: where each
    /// guardian pops in, the spots every step's jobs are done at, the lines to draw, and with them the
    /// seeds step 3 drops. `making_of_inputs.py` is the reference and makes the same numbers bit for
    /// bit; the sizes and spots come at the precision the plan file keeps (0.01 px, 0.0001 s).
    ///
    /// Every random draw is a `ShowStreams` stream of `seed` (the planner's `CrewPlan` draws from
    /// `SplitMix64(seed:)` itself), so a change to one step's weights can't move another step's
    /// spots. The guardians pop in one to a band of the picture (the spec's `bands`, left to right), each at
    /// its first job; step 2's jobs are at the seeds, step 4's are the strokes, and the others
    /// (`pets * 4` spots each) are drawn by `StopWeights`.
    ///
    /// - Parameters:
    ///   - exitBand: pixels below the picture that the farewell walks off through.
    public static func make(
        _ pictures: ShowPictures, _ template: ShowTemplate, spec: ShowSpec, seed: UInt64, exitBand: Double = defaultExitBand
    ) throws -> (CrewInputs, [PaintSeed]) {
        let w = pictures.width, h = pictures.height
        guard template.width == w, template.height == h else {
            throw CrewInputsError(description: "the template is for a \(template.width)x\(template.height) picture, not \(w)x\(h)")
        }
        guard !spec.crew.pets.isEmpty else { throw CrewInputsError(description: "a crew is one pet or more") }
        let streams = ShowStreams(seed: seed)
        let steps = ShowSpec.StepID.allCases.count
        let intro = ExactMath.quantize(spec.timing.intro, decimals: 4)
        let step = ExactMath.quantize(spec.timing.step, decimals: 4)
        let petHeight = ExactMath.quantize(spec.crew.height * Double(min(w, h)), decimals: 2)
        let weights = StopWeights(pictures: pictures, template: template, petHeight: petHeight, margin: spec.crew.margin)
        let pets = spec.crew.pets.count

        // They pop in one to a band, each at its first job, so the first step starts everywhere at once.
        let bands = max(1, min(spec.crew.bands, pets))
        let lo = spec.crew.margin * Double(w), hi = (1 - spec.crew.margin) * Double(w)
        let edges = (0..<bands).map { truncated(lo + (hi - lo) / Double(bands) * Double($0)) } + [truncated(hi)]
        let structure = weights.structure()
        var homeStream = streams.stream(.homes, 0)
        var homes: [Spot] = []
        let reach = 0.2 * Double(w)
        for band in 0..<bands {
            var plane = [Double](repeating: 0, count: structure.count)
            let columns = max(edges[band], 0)..<max(min(edges[band + 1], w), edges[band])
            for y in 0..<h {
                for x in columns { plane[y * w + x] = structure[y * w + x] }
            }
            for home in homes {                 // apart across band edges too
                let r = truncated(reach) + 1
                for y in max(home.y - r, 0)..<min(home.y + r + 1, h) {
                    for x in max(home.x - r, 0)..<min(home.x + r + 1, w)
                    where Double((x - home.x) * (x - home.x) + (y - home.y) * (y - home.y)) < reach * reach {
                        plane[y * w + x] = 0
                    }
                }
            }
            let share = (0..<pets).filter { $0 * bands / pets == band }.count
            homes += Sampling.sampleStops(weights: plane, width: w, count: share, spacing: reach, rng: &homeStream)
        }

        let paints = try PaintColors(palette: pictures.palette)
        let seeds = PaintSeeds.seeds(pictures: pictures, paints: paints, spec: spec, seed: seed)

        var candidates: [[Spot]] = []
        for k in 0..<steps {
            switch k {
            case 2:
                candidates.append(seeds.map { Spot(x: Int($0.x), y: Int($0.y)) })
            case CrewPlan.inkStep:
                candidates.append([])           // its lines are the strokes
            default:
                var rng = streams.stream(.spots, k)
                let spots = Sampling.sampleStops(
                    weights: weights.plane(forStep: k), width: w, count: pets * 4, spacing: 0.1 * Double(w), rng: &rng)
                candidates.append(k == 0 ? homes + spots : spots)   // each guardian pops in at its first job
            }
        }

        func px(_ v: Double) -> Double { ExactMath.quantize(v, decimals: 2) }
        func point(_ x: Double, _ y: Double) -> Point { Point(px(x), px(y)) }
        let inputs = CrewInputs(
            width: px(Double(w)), height: px(Double(h)), petHeight: petHeight, intro: intro, step: step, seed: seed,
            pets: spec.crew.pets.enumerated().map { i, id in
                .init(id: id, start: point(Double(homes[i % homes.count].x), Double(homes[i % homes.count].y)))
            },
            candidates: candidates.map { $0.map { point(Double($0.x), Double($0.y)) } },
            strokes: template.strokes.map { $0.points.map { point($0.x, $0.y) } },
            frameHeight: px(Double(h) + exitBand))
        return (inputs, seeds)
    }
}
