/// The numbers the reveal schedule (`Arrival`, `PaintFlow`, `StrokeSchedule`, `NumberSchedule`) is
/// tuned by, in one place. `making_of_reveal.py` has the same in capitals with underscores (a
/// lattice's cells are one pair there), and `test_making_of_reveal.py` checks that they agree;
/// change them together and regenerate `reveal-small.json`. Times are seconds, lengths pixels of
/// the working image unless a unit says otherwise.
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

    /// In pet heights: a number this near a working pet goes down just after it ...
    public var numberNear = 1.6
    /// ... this long after the pet's visit.
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

    public init() {}
}

/// When the show's steps begin and end, from the spec's `timing`: `intro`, then six steps of `step`.
public struct ScheduleTiming: Sendable, Equatable {
    public static let steps = 6
    /// The step whose lines are drawn by hand, and the step they relax in.
    public static let inkStep = CrewPlan.inkStep
    public static let templateStep = CrewPlan.inkStep + 1

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
}
