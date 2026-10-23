import Foundation
import PaintCore

/// The making-of show with no crew: each step's change grows from seeds over the picture itself, in
/// a pattern of its own that follows what the step does: `size`, `lineWidth`, `timeline`,
/// `duration`, `frame(at:)` and `composite` are what a view plays, and its frames carry two marks of
/// their own (`ShowFrame.sparks`, `ShowFrame.stars`). It replaced the crew's show, which the app
/// played first; its Swift port was retired on October 23, 2026, and its Python left this repository
/// with the Marginarium. Paul's decision (October 23): the Marginarium is private for now; it leaves
/// every build and this repository. Its archive is in the private painting-company repository.
///
///  1. **sketch**: graphite races along the structure like frost along cracks; the color drains and
///     the paper washes in behind it, outward from the lines.
///  2. **shading**: watercolor blooms open from drops born at random moments, slow to a stop at
///     edges and seep past them, each with a darker tide line at its rim.
///  3. **paints**: the real k-means++ seeds drop as rings (`PaintSeeds`), and each paint runs through its own areas like dye, jumping slowly between them.
///  4. **merged**: the tiny bits melt into their neighbors from the outside in, smallest first.
///  5. **ink**: the lines burn along the drawing like a fuse, branching at every junction, a spark at
///     every burning tip, grey at first and darkening to ink.
///  6. **template**: a second fuse relaxes the outlines into curves; the areas clear in drifts; the
///     numbers come out like stars, each with a faint ring.
///
/// It is built from the same parts as the crew's show (the k-means++ seeds and the paints, the merged
/// regions, the template's lines and numbers, the layers, the compositor's formulas, the cards, the
/// rings and the lines' stair steps), and what differs is when each part changes: an arrival time
/// from each step's seeds through a cost field (`Geodesic`), roughened by domain-warped noise
/// (`FieldNoise`), then paced by rank (`FieldMath.paced`), so the change covers the picture evenly
/// whatever the field's outliers. The fields are computed at half the picture's size and grown back
/// bilinearly. The compositor's own numbers are `style`; the fronts of steps 2 to 4 get a tide line
/// (`tideDepth`) in `composite`; the hold at the end is `outro`.
///
/// Every random draw is SplitMix64's (`ShowStream.fields` on, one stream for each step and one for
/// the noise) and every pick is made from integer weights (`Sampling`), so the same pictures,
/// template, spec and seed pick the same seeds and orders on any device. The fields are smooth
/// float64 values of sums, products and minima (and a few `exp`, `log` and `pow`), which agree with
/// the Python's far closer than a frame shows; nothing sums floating point per band, so a show is the
/// same on any number of cores.
///
/// Building (`init`) computes the fields of the six steps once: at 1024 x 682 about 0.7 s on four
/// cores and 1.6 s on one (release, Linux x86); the show keeps about 35 MB, and the build peaks about
/// 35 MB above that. After it `frame(at:)` is a pure function of the time.
///
/// `making_of_fields.py` is the Python reference of the same (`FieldShow`, which `making_of_clip.py
/// --no-crew` plays), and `fields-small.json` (what it makes of the small fixture, written by
/// `tools/tests/test_making_of_fields.py --write-goldens`) is what `FieldShowTests` compares the
/// seeds, fields, frames and composites with.
public struct FieldShow: Sendable {
    /// The pictures' size, which every place in a frame is in.
    public let size: (width: Int, height: Int)
    /// The spec's timing with this show's hold (`outro`): `timeline.timing` says when the steps and
    /// their cards come and go.
    public let timeline: Timeline
    /// The width the template's lines are drawn at, in pixels of the picture (`ShowTemplate.lineWidth`).
    public let lineWidth: Double

    /// Internal, for the tests that look at its planes.
    let compositor: Compositor
    let strokes: [StrokeSchedule.Stroke]
    let fuses: [[Double]]
    let numberTimes: [Double]
    let seeds: [PaintSeed]
    /// For each paint, when its last pixel has changed.
    let spread: [Double]
    /// What chance decided, which the tests pin.
    let picks: FieldBuild.Picks
    private let numbers: [ShowTemplate.Number]
    private let steps: [ShowSpec.Step]
    private let cards: ShowSpec.Cards
    private let outlines: ShowSpec.Outlines

    /// The show's whole length in seconds: the steps and the hold at the end.
    public var duration: Double { timeline.duration }

    /// Throws a `ShowError` if the template is not for pictures of this size or they are under 8 px.
    ///
    /// - Parameter cancel: checked between the stages of the build.
    public init(
        pictures: ShowPictures, template: ShowTemplate, spec: ShowSpec, seed: UInt64, cancel: CancellationCheck = .none
    ) throws {
        let (w, h) = (pictures.width, pictures.height)
        guard template.width == w, template.height == h else {
            throw ShowError(description: "the template is for a \(template.width)x\(template.height) picture, not \(w)x\(h)")
        }
        guard min(w, h) >= 4 * Self.scale else { throw ShowError(description: "a \(w)x\(h) picture is too small to show") }
        let paints = try PaintColors(palette: pictures.palette)
        let seeds = PaintSeeds.seeds(pictures: pictures, paints: paints, spec: spec, seed: seed)
        let layers = try ShowLayers(
            photo: pictures.working, structure: pictures.structure, smoothed: pictures.smoothed,
            palette: pictures.palette, simplified: pictures.simplified, sketch: spec.sketch, tones: spec.tones,
            style: Self.style, keepingAnalysis: false, cancel: cancel)
        try cancel.throwIfCancelled()
        let built = try FieldBuild.make(
            pictures: pictures, survivors: layers.survivors, template: template, spec: spec, seed: seed,
            seeds: seeds, paints: paints, cancel: cancel)

        size = (w, h)
        timeline = Timeline(spec, outro: Self.outro)
        lineWidth = template.lineWidth
        compositor = Compositor(layers: layers, times: built.times, intro: spec.timing.intro, step: spec.timing.step)
        strokes = built.strokes
        fuses = built.fuses
        numberTimes = built.numberTimes
        self.seeds = seeds
        spread = built.spread
        picks = built.picks
        numbers = template.numbers
        steps = spec.steps
        cards = spec.cards
        outlines = spec.outlines
    }

    // MARK: A frame

    /// What to draw at time `t` (seconds into the show, which can be outside 0...`duration`: before
    /// it is the photo, after it the finished drawing). Pure, and cheap: the lines, sparks and stars
    /// of one moment, no pixels.
    public func frame(at t: Double) -> ShowFrame {
        let stage = timeline.stage(at: t)
        let step = timeline.step(at: t)

        var ink: [InkLine] = []
        var sparks: [Spark] = []
        if stage == ScheduleTiming.inkStep {
            (ink, sparks) = burning(at: t)
        } else if stage >= ScheduleTiming.templateStep {
            ink = StrokeSchedule.relaxed(strokes, at: t < timeline.timing.end ? t : .infinity, over: outlines.relax)
        }

        var numbers: [Double] = []
        var stars: [Star] = []
        if stage >= ScheduleTiming.templateStep {
            let fade = ScheduleStyle.standard.numberFade
            numbers = numberTimes.map { ease((t - $0) / fade) }
            for (number, at) in zip(self.numbers, numberTimes) {
                let u = (t - at) / Self.starLife
                if u > 0 && u < 1 {
                    let first = max(number.size * Self.starRadius.from, Self.starRadius.least)
                    stars.append(Star(
                        x: number.x, y: number.y, radius: first + number.size * Self.starRadius.growing * u,
                        alpha: Self.starAlpha * (1 - u)))
                }
            }
        }

        var rings: [SeedRing] = []
        if stage == 2 {
            rings = seeds.compactMap { timeline.ring($0, spread: spread[$0.paint], at: t) }
        }

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

        return ShowFrame(
            time: t, step: step, picture: PictureRecipe(stage: stage, time: t, handoff: timeline.handoff(at: t)),
            ink: ink, numbers: numbers, seedRings: rings, sparks: sparks, stars: stars, card: card)
    }

    /// The ink step's lines at time `t`: every segment the fuse has reached at both ends, grey at
    /// first and darkening to ink in eighths, as runs of one value; and the sparks at the burning
    /// tips. A line the fuse has not reached a whole segment of has neither.
    func burning(at t: Double) -> (lines: [InkLine], sparks: [Spark]) {
        let ramp = outlines.inkRamp
        let grey = ScheduleStyle.standard.inkGrey
        var lines: [InkLine] = []
        var sparks: [Spark] = []
        for (stroke, at) in zip(strokes, fuses) {
            guard t >= stroke.start else { continue }                  // the fuse has not reached its first point
            let reached = (0..<at.count - 1).map { max(at[$0], at[$0 + 1]) }
            guard reached.contains(where: { $0 <= t }) else { continue }
            let value = reached.map { seg -> Double in
                let u = min(max((t - seg) / ramp, 0), 1)
                let eighths = ((grey * (1 - u) + u) * 8).rounded(.down) / 8
                return min(eighths + 1.0 / 16, 1.0)
            }
            var i = 0
            while i < reached.count {
                if reached[i] > t {
                    i += 1
                    continue
                }
                var j = i
                while j + 1 < reached.count && reached[j + 1] <= t && value[j + 1] == value[i] { j += 1 }
                lines.append(InkLine(stroke: stroke.index, points: Array(stroke.jagged[i...(j + 1)]), value: value[i]))
                i = j + 1
            }
            let hot = at.indices.filter { at[$0] <= t && at[$0] > t - Self.sparkLife }
            for k in stride(from: 0, to: hot.count, by: max(1, hot.count / Self.sparksPerLine)) {
                let point = stroke.jagged[hot[k]]
                sparks.append(Spark(x: point.x, y: point.y, heat: 1 - (t - at[hot[k]]) / Self.sparkLife))
            }
        }
        return (lines, sparks)
    }

    // MARK: The CPU reference

    /// Draws the picture of `frame` into `pixels` (the pictures' size): the layers blended as the
    /// recipe says, with the lines of `frame.ink` rasterized by `InkCoverage` at `lineWidth`, and the
    /// tide line along the fronts of steps 2 to 4 (`tideDepth` darker for `tideWidth` seconds just
    /// behind where the change is arriving, the Python's `TideCompositor`). This is the part of a frame a shader does for every pixel, for a view to be
    /// checked against; the numbers, the hand-off to the real template, the rings, the sparks and
    /// stars and the card are the view's own drawing and are not in it.
    public func composite(_ frame: ShowFrame, into pixels: inout Plane<SIMD4<UInt8>>) {
        precondition(pixels.width == size.width && pixels.height == size.height, "pixels are the pictures' size")
        let (w, h) = (size.width, size.height)
        let ink = frame.ink.isEmpty ? nil : InkCoverage.plane(frame.ink, width: w, height: h, lineWidth: lineWidth)
        let (t, stage) = (frame.picture.time, frame.picture.stage)
        let times = compositor.times
        let front = stage == 1 ? times.shading : stage == 2 ? times.paints : stage == 3 ? times.merged : nil
        let depth = (1...3).contains(stage) ? Self.tideDepth[stage - 1] : 0
        pixels.data.withUnsafeMutableBufferPointer { buffer in
            let out = UncheckedSendable(buffer.baseAddress!)
            FieldBands.forEach(h) { rows in
                for i in (rows.lowerBound * w)..<(rows.upperBound * w) {
                    var c = compositor.shade(i, at: t, stage: stage, ink: Double(ink?.data[i] ?? 0))
                    if let front {
                        let u = (t - Double(front.data[i])) / Self.tideWidth
                        if u > 0 { c *= 1 - depth * exp(-3 * ((u - 0.6) * (u - 0.6))) }
                    }
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

/// Why a show can't be made.
public struct ShowError: Error, Equatable, CustomStringConvertible {
    public let description: String
}
