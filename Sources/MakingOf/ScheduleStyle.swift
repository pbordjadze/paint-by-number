/// The numbers the show's schedule (`StrokeSchedule`, `FieldShow`'s lines and numbers, and `Timeline`
/// for the overlays) is tuned by, in one place: WHEN and WHERE things happen, worked out once per
/// show on the CPU. `RevealStyle` is the other style, and the two don't overlap: that one is what a
/// pixel looks like at a moment (colors, and the ramps a change takes to come in, which the
/// `Compositor` and the app's shader run for every pixel), and `FieldShow`'s own numbers are in
/// `FieldTuning.swift`. `making_of_reveal.py` has this one in capitals with underscores, and
/// `test_making_of_reveal.py` checks that they agree; change them together and regenerate
/// `fields-small.json`. Times are seconds, lengths pixels of the working image unless a unit says
/// otherwise.
public struct ScheduleStyle: Sendable, Equatable {
    public static let standard = ScheduleStyle()

    /// The step length the cards' fade was tuned at; a show's `pace` is this over its step.
    public var referenceStep = 1.5

    // MARK: Lines

    /// Between the samples of a line before they are snapped to the grid.
    public var staircaseSpacing = 1.5
    /// The ink value (0 paper, 1 full ink) a burning line starts at; it darkens to full ink over
    /// `outlines.inkRamp`.
    public var inkGrey = 0.45

    // MARK: Numbers

    /// How long a number takes to come in.
    public var numberFade = 0.1

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
    /// The finished drawing hands over to the real template over this long, as the steps end.
    public var handoff = 0.15

    public init() {}
}

/// When the show's steps begin and end, from the spec's `timing`: `intro`, then six steps of `step`.
public struct ScheduleTiming: Sendable, Equatable {
    public static let steps = 6
    /// The step whose lines are drawn (`ShowSpec.StepID.ink`'s place, which the spec insists on),
    /// and the step they relax in.
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

    /// How much faster than the reference step this one is, which the cards' fade scales by.
    public func pace(_ style: ScheduleStyle) -> Double { style.referenceStep / step }

    /// What the show is doing at time `t`: -1 before the first step, 0 to 5 in a step, 6 once the
    /// six are over (`stage_of` in `making_of_compose.py`).
    public func stage(at t: Double) -> Int {
        if t < intro { return -1 }
        if t >= end { return Self.steps }
        return min(Int(((t - intro) / step).rounded(.down)), Self.steps - 1)
    }
}
