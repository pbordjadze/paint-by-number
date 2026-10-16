import PaintCore

/// Why a show can't be made or played.
public struct ShowError: Error, Equatable, CustomStringConvertible {
    public let description: String
}

/// The making-of show, built once from a generation's pictures and finished template, and then a
/// pure function of the time: `frame(at:)` says what to draw at any moment (`ShowFrame`, whose
/// doc comment is what the app's view draws), cheaply, so it can seek, hold still for Reduce Motion
/// and play at any frame rate.
///
/// Building runs the whole pipeline of the show once (`init`: at 1024 x 682 about half a second on
/// four cores and a second on one, release on Linux x86; the show keeps about 37 MB, and the
/// build peaks about 30 MB above that):
/// 1. `CrewInputs.make` chooses where the guardians pop in and work and which seeds step 3 drops,
///    from the pictures and the template; `CrewPlan` plans them from that (from `seed`: the same
///    pictures, template, spec and seed give the same show on any device);
/// 2. `ShowLayers` derives the six layers of the pictures;
/// 3. `Arrival` spreads each step's change from where the crew works, and it is reduced to what
///    `frame` needs: per pixel the time each step's change reaches it (the `Compositor.Times`),
///    the lines' schedule (`StrokeSchedule`) and the numbers' (`NumberSchedule`). The per-step
///    fields themselves are dropped as soon as they are reduced.
///
/// `making_of_show.py` is the Python reference of the same, and `frames-small.json` (what it makes
/// of the small fixture) is what `ShowTests` compares frames and composites with.
public struct Show: Sendable {
    /// The pictures' size, which every place in a frame is in.
    public let size: (width: Int, height: Int)
    public let timeline: Timeline
    public let crew: CrewPlan
    /// The width the template's lines are drawn at, in pixels of the picture (`ShowTemplate.lineWidth`).
    public let lineWidth: Double

    /// Internal, for the tests that look at its planes.
    let compositor: Compositor
    private let strokes: StrokeSchedule
    private let numbers: NumberSchedule
    private let seeds: [PaintSeed]
    /// For each paint, when its last region has changed (`PaintFlow.Result.spread`).
    private let spread: [Double]
    /// In crew order.
    private let metrics: [SpriteMetrics]
    private let petHeight: Double
    private let steps: [ShowSpec.Step]
    private let cards: ShowSpec.Cards
    private let crewSpec: ShowSpec.Crew

    /// The show's whole length in seconds: the steps and the hold at the end.
    public var duration: Double { timeline.duration }

    /// - Parameters:
    ///   - sprites: each guardian's metrics by id (`SpriteMetrics.table(json:)` of the bundled
    ///     `pet-metrics.json`); every guardian of the spec's crew needs its own.
    ///   - exitBand: the pixels below the picture that the farewell walks off through, which the
    ///     plan depends on (the video frame's card band); `CrewInputs.defaultExitBand`.
    ///   - cancel: checked between the stages of the build.
    public init(
        pictures: ShowPictures, template: ShowTemplate, spec: ShowSpec, seed: UInt64,
        sprites: [String: SpriteMetrics], exitBand: Double = CrewInputs.defaultExitBand,
        cancel: CancellationCheck = .none
    ) throws {
        let (w, h) = (pictures.width, pictures.height)
        let (inputs, seeds) = try CrewInputs.make(pictures, template, spec: spec, seed: seed, exitBand: exitBand)
        let metrics = try inputs.pets.map { member in
            guard let found = sprites[member.id] else { throw ShowError(description: "no sprite metrics for \(member.id)") }
            return found
        }
        let crew = try CrewPlan(inputs, spec: spec)
        try cancel.throwIfCancelled()
        let layers = try ShowLayers(
            photo: pictures.working, structure: pictures.structure, smoothed: pictures.smoothed,
            palette: pictures.palette, simplified: pictures.simplified, sketch: spec.sketch, tones: spec.tones,
            keepingAnalysis: false, cancel: cancel)
        try cancel.throwIfCancelled()

        let timing = ScheduleTiming(spec)
        let streams = ShowStreams(seed: seed)
        let paints = try PaintColors(palette: pictures.palette)
        let paletteRegions = Labeling.regions(of: pictures.palette)
        let regions = Labeling.regions(of: pictures.simplified)
        func field(_ k: Int) throws -> Plane<Double> {
            try cancel.throwIfCancelled()
            return Arrival.field(step: k, visits: crew.visits[k], width: w, height: h, timing: timing, streams: streams)
        }
        /// A time for every pixel, in Float like the compositor's.
        func perPixel(_ plane: Plane<Double>) -> Plane<Float> {
            Plane(width: w, height: h, data: plane.data.map { Float($0) })
        }
        func perPixel(_ times: [Double], of labels: Plane<Int32>) -> Plane<Float> {
            Plane(width: w, height: h, data: labels.data.map { Float(times[Int($0)]) })
        }

        // each step's field is reduced to what frames need and dropped, but the last two, which the
        // lines' and numbers' schedules read
        let sketch = perPixel(try field(0))
        let shading = perPixel(try field(1))
        let flow = PaintFlow.times(
            seeds: seeds, paints: paints.index, paintCount: paints.keys.count, labels: paletteRegions.labels,
            labelCount: paletteRegions.count, following: try field(2), timing: timing)
        let mergedAt = Arrival.regionMinimum(try field(3), labels: regions.labels, count: regions.count)
        let inkArrival = try field(4)
        let liftAt = Arrival.regionMinimum(inkArrival, labels: regions.labels, count: regions.count)
        let relaxArrival = try field(5)
        let clearAt = Arrival.regionMinimum(relaxArrival, labels: regions.labels, count: regions.count)

        let compositor = Compositor(
            layers: layers,
            times: Compositor.Times(
                sketch: sketch, shading: shading, paints: perPixel(flow.regionTimes, of: paletteRegions.labels),
                merged: perPixel(mergedAt, of: regions.labels), lift: perPixel(liftAt, of: regions.labels),
                clear: perPixel(clearAt, of: regions.labels)),
            intro: spec.timing.intro, step: spec.timing.step)
        strokes = StrokeSchedule(
            strokes: inputs.strokes.map(Polyline.init), traces: crew.traces, inkArrival: inkArrival,
            relaxArrival: relaxArrival, spec: spec, petHeight: inputs.petHeight, streams: streams)
        numbers = NumberSchedule(
            numbers: template.numbers.map { (x: $0.x, y: $0.y, size: $0.size) }, clear: clearAt,
            regions: regions.labels, relaxArrival: relaxArrival, visits: crew.visits[ScheduleTiming.templateStep],
            timing: timing, petHeight: inputs.petHeight)

        size = (w, h)
        timeline = Timeline(spec)
        self.crew = crew
        lineWidth = template.lineWidth
        self.compositor = compositor
        self.seeds = seeds
        spread = flow.spread
        self.metrics = metrics
        petHeight = inputs.petHeight
        steps = spec.steps
        cards = spec.cards
        crewSpec = spec.crew
    }

    // MARK: A frame

    /// What to draw at time `t` (seconds into the show, which can be outside 0...`duration`: before
    /// it is the photo, after it the finished drawing without the crew). Pure, and cheap: the lines
    /// and guardians of one moment, no pixels.
    public func frame(at t: Double) -> ShowFrame {
        let stage = timeline.stage(at: t)
        let step = timeline.step(at: t)

        var card: CardDraw?
        if let k = step {
            let fade = timeline.cardFade(step: k, at: t)
            if fade > 0 {
                let opacity = cards.opacity * fade
                card = CardDraw(
                    step: k, caption: steps[k].caption, methods: steps[k].methods, opacity: opacity,
                    footnoteOpacity: opacity * cards.footnote)
            }
        }

        var rings: [SeedRing] = []
        if stage == 2 {
            rings = seeds.compactMap { timeline.ring($0, spread: spread[$0.paint], at: t) }
        }

        let fade = timeline.crewFade(at: t)
        var drawn: [(y: Double, order: Int, draw: SpriteDraw)] = []
        if fade > 0 {
            for (i, pet) in crew.pets.enumerated() {
                let state = pet.state(at: t)
                if let draw = SpriteDraw.make(
                    id: pet.id, state: state, since: t - pet.appear, fade: fade, height: petHeight,
                    pictureHeight: Double(size.height), metrics: metrics[i], crew: crewSpec)
                {
                    drawn.append((state.y, i, draw))
                }
            }
        }
        drawn.sort { ($0.y, $0.order) < ($1.y, $1.order) }        // farther ones first

        return ShowFrame(
            time: t, step: step,
            picture: PictureRecipe(stage: stage, time: t, handoff: timeline.handoff(at: t)),
            ink: strokes.lines(at: t),
            numbers: stage >= ScheduleTiming.templateStep
                ? (0..<self.numbers.times.count).map { self.numbers.alpha($0, at: t) } : [],
            seedRings: rings, sparks: [], stars: [], sprites: drawn.map(\.draw), card: card)
    }

    // MARK: The CPU reference

    /// Draws the picture of `frame` into `pixels` (the pictures' size): the layers blended as the
    /// recipe says, with the lines of `frame.ink` rasterized by `InkCoverage` at `lineWidth`. This is
    /// the part of a frame a shader does for every pixel, for a view to be checked against; the
    /// numbers, the hand-off to the real template, the rings, the guardians and the card are the
    /// view's own drawing and are not in it.
    public func composite(_ frame: ShowFrame, into pixels: inout Plane<SIMD4<UInt8>>) {
        precondition(pixels.width == size.width && pixels.height == size.height, "pixels are the pictures' size")
        let (w, h) = (size.width, size.height)
        let ink = frame.ink.isEmpty ? nil : InkCoverage.plane(frame.ink, width: w, height: h, lineWidth: lineWidth)
        let (t, stage) = (frame.picture.time, frame.picture.stage)
        pixels.data.withUnsafeMutableBufferPointer { buffer in
            let out = UncheckedSendable(buffer.baseAddress!)
            Parallel.forEachBand(h) { rows in
                for i in (rows.lowerBound * w)..<(rows.upperBound * w) {
                    let c = compositor.shade(i, at: t, stage: stage, ink: Double(ink?.data[i] ?? 0))
                    out.value[i] = SIMD4(Self.byte(c.x), Self.byte(c.y), Self.byte(c.z), 255)
                }
            }
        }
    }

    /// A 0...1 value as a byte, rounded half up like `(clip(v, 0, 1) * 255 + 0.5).astype(uint8)`.
    private static func byte(_ v: Double) -> UInt8 {
        UInt8(min(max(v * 255 + 0.5, 0), 255).rounded(.down))
    }
}
