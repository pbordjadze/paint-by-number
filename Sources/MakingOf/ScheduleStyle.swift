/// The numbers the show's schedule (`Arrival`, `PaintFlow`, `StrokeSchedule`, and `Timeline` for the
/// overlays) is tuned by, in one place: WHEN and WHERE things happen, worked out
/// once per show on the CPU. `RevealStyle` is the other style, and the two don't overlap: that one is
/// what a pixel looks like at a moment (colors, and the ramps a change takes to come in, which the
/// `Compositor` and the app's shader run for every pixel). `making_of_reveal.py` has this one in
/// capitals with underscores (a lattice's cells are one pair there), and `test_making_of_reveal.py`
/// checks that they agree; change them together and regenerate `reveal-small.json` and
/// `fields-small.json`. Times are seconds, lengths pixels of the working image unless a unit says
/// otherwise.
public struct ScheduleStyle: Sendable, Equatable {
    public static let standard = ScheduleStyle()

    // MARK: Arrival

    /// The step length the speeds below were tuned at; a show's `pace` is this over its step.
    public var referenceStep = 1.5
    /// Picture widths per second (times pace) a step's change spreads from a visit at.
    public var arrivalSpeed = 0.55
    /// Every pixel of a step has changed this long before the step ends.
    public var stepMargin = 0.2
    /// Seconds of roughness of the change: broad swells (`coarseCellsX` by `coarseCellsY` cells) ...
    public var coarseNoise = 0.10
    public var coarseCellsX = 18
    public var coarseCellsY = 12
    /// ... and fine grain.
    public var fineNoise = 0.06
    public var fineCellsX = 60
    public var fineCellsY = 40

    // MARK: Paint flow

    /// From a seed dropping to its paint starting to flow out of it.
    public var seedDelay = 0.25
    /// A paint flows out at one picture width per this many seconds.
    public var seedSpeedDivisor = 1.3
    /// Into the paints step, before which no paint flows.
    public var paintFloor = 0.2
    /// How far a paint no seed landed on lags the crew's own change.
    public var unseededDelay = 0.3

    // MARK: Lines

    /// Between the samples of a line before they are snapped to the grid.
    public var staircaseSpacing = 1.5
    /// At most how long a line the crew doesn't walk waits once the crew's change reaches it.
    public var strokeJitter = 0.5
    /// Into the ink step, before which no line the crew doesn't walk begins.
    public var strokeEarliest = 0.3
    /// Picture widths per second (times pace) such a line is drawn at ...
    public var strokeSpeed = 0.45
    /// ... but never quicker than this, nor slower than `strokeMaxTime` (over pace).
    public var strokeMinTime = 0.25
    public var strokeMaxTime = 0.9
    /// Such a line is done this long before the ink step ends.
    public var inkEndMargin = 0.12
    /// The ink value (0 paper, 1 full ink) a line the crew doesn't walk starts at; it darkens to
    /// full ink over `outlines.inkRamp`.
    public var inkGrey = 0.45

    // MARK: Numbers

    /// In guardian heights: a number this near a working guardian goes down just after it ...
    public var numberNear = 1.6
    /// ... this long after the guardian's visit.
    public var numberAfterPet = 0.3
    /// Steps into the template step the other numbers wait for, at the earliest.
    public var numberLate = 0.55
    /// A number never comes in before its area has cleared to paper by this much ...
    public var numberAfterClear = 0.05
    /// ... nor before the outlines have relaxed at it by this much.
    public var numberAfterRelax = 0.45
    /// Every number is down this long before the show's steps end.
    public var numberEndMargin = 0.15
    /// How long a number takes to come in.
    public var numberFade = 0.1
    /// The radius of the disc a number owns, as a share of its size, and the least it can be (px).
    public var numberDisc = 0.9
    public var numberDiscMinimum = 4.0

    // MARK: Overlays

    /// A step's card fades in, and out again, over this long at the reference step (over the square
    /// root of the pace, so a brisker show fades faster).
    public var cardFade = 0.15
    /// A seed ring pops in over this long, swelling by this share of its radius on the way ...
    public var ringPop = 0.22
    public var ringSwell = 0.35
    /// ... and is opaque once a third of that has passed: its alpha rises this many times as fast.
    public var ringRise = 3.0
    /// Every ring is gone this long before the paints step ends, over `ringGoneFade` ...
    public var ringGoneBefore = 0.4
    public var ringGoneFade = 0.35
    /// ... and a ring fades this long after its paint has spread everywhere (the spec's
    /// `seeds.fade` is how long it takes).
    public var ringAfterSpread = 0.1
    /// Every guardian fades out over the last of this long of the show, as the painting screen arrives.
    public var crewFadeOut = 0.3
    /// The finished drawing hands over to the real template over this long, as the steps end.
    public var handoff = 0.15

    public init() {}
}

/// When the show's steps begin and end, from the spec's `timing`: `intro`, then six steps of `step`.
public struct ScheduleTiming: Sendable, Equatable {
    public static let steps = 6
    /// The step whose lines are drawn by hand (`ShowSpec.StepID.ink`'s place, which the spec
    /// insists on), and the step they relax in.
    public static let inkStep = 4
    public static let templateStep = inkStep + 1

    public var intro: Double
    public var step: Double

    public init(intro: Double, step: Double) {
        self.intro = intro
        self.step = step
    }

    public init(_ spec: ShowSpec) {
        self.init(intro: spec.timing.intro, step: spec.timing.step)
    }

    /// When step `k` begins.
    public func start(_ k: Int) -> Double { intro + Double(k) * step }

    /// When the last step ends.
    public var end: Double { intro + Double(Self.steps) * step }

    /// How much faster than the reference step this one is, which the speeds scale by.
    public func pace(_ style: ScheduleStyle) -> Double { style.referenceStep / step }

    /// What the show is doing at time `t`: -1 before the first step, 0 to 5 in a step, 6 once the
    /// six are over (`stage_of` in `making_of_compose.py`).
    public func stage(at t: Double) -> Int {
        if t < intro { return -1 }
        if t >= end { return Self.steps }
        return min(Int(((t - intro) / step).rounded(.down)), Self.steps - 1)
    }
}
