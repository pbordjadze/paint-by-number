import Foundation

/// The numbers the field show is tuned by, one block as in `making_of_fields.py` (change the two
/// together and write `fields-small.json` again, see `FieldShow`). Times are seconds, lengths pixels
/// of the working image unless a unit says otherwise; "of the field" is pixels of the fields, which
/// are computed at `1 / scale` of the picture's size.
extension FieldShow {
    /// Seconds the finished drawing holds: there is no goodbye to wait for.
    public static let outro = 1.6
    /// The fields are computed at 1 / `scale` of the picture's size.
    static let scale = 2
    /// Rounds of `Geodesic`'s four sweeps.
    static let sweeps = 3
    /// How much of a field's pace is its rank (the rest is its plain stretch).
    static let paceMix = 0.8
    /// Ranks the pacing interpolates between.
    static let paceKnots = 2048
    /// Noise lattice points across (it wraps).
    static let lattice = 129

    /// Step 1: count, spacing (of the width) and the span of the moments (s) of the seeds ...
    static let sketchSeeds = 9, sketchSpacing = 0.12, sketchBirths = 0.5
    /// ... the speed off the survivors (flat), on them (gain, power) ...
    static let sketchFlat = 0.05, sketchGain = 2.5, sketchPower = 0.7
    /// ... and the noise's scale (px) and strength.
    static let sketchRough = (scale: 70.0, strength: 0.35)
    /// Seconds before the step ends: the last pixel's graphite and wash still fit.
    static let sketchEnd = 1.05

    /// Step 2: the same for the blooms.
    static let bloomSeeds = 15, bloomSpacing = 0.11, bloomBirths = 1.0
    /// How hard an edge stops a bloom: speed / (1 + this * structure^2).
    static let bloomEdge = 60.0
    static let bloomRough = (scale: 55.0, strength: 0.55)
    static let bloomEnd = 0.3

    /// Step 3: how much slower a paint runs outside its own areas.
    static let dyeOutside = 14.0
    /// Pixels of the field per second of the seeds' drop times.
    static let dyeBirth = 40.0
    static let dyeRough = (scale: 40.0, strength: 0.4)
    /// Pixels later a paint no seed landed on starts, from the nearest seed.
    static let dyeUnseeded = 60.0
    static let dyeStart = 0.2, dyeEnd = 0.3

    /// Step 4: the bits melt over this much of the step, smallest first ...
    static let meltSpan = 0.55
    /// ... of the mean size: how much chance shuffles that order ...
    static let meltJitter = 0.8
    /// ... seconds per pixel from a bit's border to its middle ...
    static let meltRate = 0.06
    /// ... and no bit takes longer to melt than this far in (px).
    static let meltReach = 40.0
    /// The rest (the sketch fading): the noise's scale, then from and to as a share of the step.
    static let meltDrift = (scale: 90.0, from: 0.1, to: 0.6)
    static let meltEnd = 0.25

    /// Step 5: the fuse's seeds, and the fuses are lit at moments this far apart (px of the field).
    static let fuseSeeds = 7, fuseBirths = 30.0
    /// How much slower a fuse jumps a gap than it burns along a line.
    static let fuseOffLine = 30.0
    /// Seconds before the ink step ends: the last segment still darkens to ink.
    static let fuseEnd = 0.55
    /// Seconds a spark shows at a burning tip.
    public static let sparkLife = 0.06
    /// At most per line at once.
    static let sparksPerLine = 2

    /// Step 6: the second fuse relaxes the outlines into curves: its seeds, the moments it is lit at
    /// (px of the field), and the share of the step it takes.
    static let relaxSeeds = 5, relaxBirths = 20.0, relaxSpan = 0.55
    /// When the areas clear: the noise's scale, then from and to as a share of the step.
    static let clearDrift = (scale: 90.0, from: 0.25, to: 0.7)
    /// Seconds: a number comes out this long after its area has cleared, plus a draw of up to the
    /// spread, and at the latest this long before the step ends.
    static let numberAfter = 0.1, numberSpread = 0.55, numberEnd = 0.2
    /// Seconds a number's ring opens and fades ...
    public static let starLife = 0.35
    /// ... from this share of the number's size, growing by this much of it (at least this many px) ...
    static let starRadius = (from: 0.6, growing: 0.9, least: 3.0)
    /// ... at this opacity at first.
    static let starAlpha = 0.35

    /// Steps 2 to 4: how much darker a front's rim is ...
    public static let tideDepth = SIMD3<Double>(0.09, 0.12, 0.06)
    /// ... and how long (s) it takes to pass.
    public static let tideWidth = 0.07
    /// Step 5: a merged region's grey lifts this long after the fuse first reaches it, and this long
    /// before the step ends at the latest.
    static let liftAfter = 0.15, liftEnd = 0.3

    /// The compositor's numbers for this show: graphite goes down as the front passes, not after it.
    /// `RevealStyle.standard` with the ramps of the fronts changed.
    public static let style: RevealStyle = {
        var style = RevealStyle.standard
        style.graphiteDelay = 0.05
        style.graphiteByStructure = 0.15
        style.graphiteRamp = 0.14
        style.drainRamp = 0.45
        style.washDelay = 0.4
        style.washMargin = 0.75
        style.washRamp = 0.6
        style.softEarly = 0.14
        style.settleDepth = 0.0
        style.liftRamp = 0.25
        style.clearRamp = 0.18
        return style
    }()
}
