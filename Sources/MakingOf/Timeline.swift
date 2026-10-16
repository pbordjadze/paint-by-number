import Foundation

/// A ring where a k-means++ seed of the paints step landed: popping in, then fading once its paint
/// has spread. The view draws it at (`x`, `y`) as a circle of `radius` in ink, `lineWidth` wide,
/// over a paper halo `halo` wider all round, with a dot of `dotRadius` at its middle, all at `alpha`.
public struct SeedRing: Sendable, Equatable {
    public var x: Double
    public var y: Double
    public var radius: Double
    public var alpha: Double

    /// How a ring is drawn, in pixels of the working image (`making_of_clip.py` draws the same).
    public static let lineWidth = 3.0
    public static let halo = 2.5
    public static let dotRadius = 2.6
}

/// When the show's parts come and go, from the spec's timing: the photo alone for `intro` seconds,
/// six steps of `step` seconds, the finished drawing held for `outro`. A pure function of the time
/// for each part, so the show can seek (and hold still for Reduce Motion):
///
/// - the stage: the photo (-1), one of the steps (0 to 5), the finished drawing (6);
/// - the card of each step, fading in and out inside its step, so two cards never show at once;
/// - the seed rings of the paints step;
/// - the crew's fade at the show's end, and the hand-off from the finished drawing to the real
///   template as the steps end.
///
/// `ScheduleStyle` holds the numbers (its overlays), `making_of_reveal.py` is the reference.
public struct Timeline: Sendable, Equatable {
    public let timing: ScheduleTiming
    /// Seconds the finished drawing is held after the steps.
    public let outro: Double
    private let cards: ShowSpec.Cards
    private let seeds: ShowSpec.Seeds
    private let style: ScheduleStyle

    public init(_ spec: ShowSpec, style: ScheduleStyle = .standard) {
        self.init(spec, outro: spec.timing.outro, style: style)
    }

    /// The spec's timing with a hold of its own: the field show's (`FieldShow.outro`), which has no
    /// farewell to wait for.
    public init(_ spec: ShowSpec, outro: Double, style: ScheduleStyle = .standard) {
        timing = ScheduleTiming(spec)
        self.outro = outro
        cards = spec.cards
        seeds = spec.seeds
        self.style = style
    }

    /// The show's whole length: the steps and the hold.
    public var duration: Double { timing.end + outro }

    /// -1 before the first step, 0 to 5 in a step, 6 from the end of the steps on.
    public func stage(at t: Double) -> Int { timing.stage(at: t) }

    /// The step playing at `t` (0 to 5), if one is.
    public func step(at t: Double) -> Int? {
        let stage = stage(at: t)
        return (0..<ScheduleTiming.steps).contains(stage) ? stage : nil
    }

    // MARK: Cards

    /// How far card `k` has faded in or out at `t` (0...1): in over the first `cardFade` of its step
    /// and out over the last, a brisker show (a shorter step) fading faster.
    public func cardFade(step k: Int, at t: Double) -> Double {
        let fade = style.cardFade / timing.pace(style).squareRoot()
        let local = t - timing.start(k)
        return ease(local / fade) * (1 - ease((local - (timing.step - fade)) / fade))
    }

    // MARK: Seed rings

    /// The ring of a seed at `t`, if it shows: it pops in when the seed drops, swelling a little
    /// on the way, and is gone `ringAfterSpread` after its paint (`spread`: the time the paint's
    /// last region has changed) has spread, or at the end of the paints step, whichever is first.
    public func ring(_ seed: PaintSeed, spread: Double, at t: Double) -> SeedRing? {
        guard t >= seed.time else { return nil }
        let gone = 1 - ease((t - (timing.start(2) + timing.step - style.ringGoneBefore)) / style.ringGoneFade)
        let u = min((t - seed.time) / style.ringPop, 1)
        let done = 1 - ease((t - spread - style.ringAfterSpread) / seeds.fade)
        let alpha = gone * done * min(u * style.ringRise, 1)
        guard alpha > 0 else { return nil }
        return SeedRing(x: seed.x, y: seed.y, radius: seeds.dot * (1 + style.ringSwell * sin(.pi * u) * (1 - u)), alpha: alpha)
    }

    // MARK: Crew and hand-off

    /// How much of the crew shows at `t` (0...1): all of it until the last `crewFadeOut` of the show,
    /// which dims it as the painting screen arrives, never while it waves.
    public func crewFade(at t: Double) -> Double {
        min(max((duration - t) / style.crewFadeOut, 0), 1)
    }

    /// How far the real template has taken over from the finished drawing (0...1): over `handoff`
    /// from the end of the steps.
    public func handoff(at t: Double) -> Double {
        ease((t - timing.end) / style.handoff)
    }
}
