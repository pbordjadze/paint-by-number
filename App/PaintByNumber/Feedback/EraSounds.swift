#if UNRELEASED
import Foundation
import PaintCore

/// What the hidden modes sound like (SideStore and Debug builds; painting-company row 381), in
/// painting's voice (`SoundPlayer`: the Sun's kalimba, the Moon's celesta, the same pentatonic
/// scales, so nothing here can clash with a painting's tune): the year wheel's steps, a music box
/// whose tine is lower the further back the year, and an era's year clicking into place with a
/// bell; each passage between eras timed to its drawing (`EraPassage`: tesserae set and lifted,
/// the nave's hum under the rose window's glass, a wash of water, and the way home's tiles let
/// go, the crescent rising, five stars); and Watercolor's water, each tap's sound what the tap
/// does (a wash, a drop, a bloom), the sheet drying, and its finish. The sounds are
/// `EraSynth`'s, made by the app as its other sounds are, and quieter than a painting's notes.
///
/// Settings › Sound's Sounds (Paint by Moonlight's, `SettingsKey.sounds`) turns them off, but the
/// wheel's, which each Settings with a wheel gates by its own switch (`eraClockSound`, set at the
/// root). They play on the ambient session, under the silent switch and the painter's music.
final class EraSounds {
    static let shared = EraSounds()

    private let player: SoundPlayer
    private let defaults: UserDefaults
    /// The moment, for the wheel's pace and the sheet's drying (a test's own).
    var now: () -> ContinuousClock.Instant = { .now }

    /// Watercolor's own tune, a note a wash, as painting's is a note a fill.
    private var melody = PaintingMelody()
    private var lastTick: ContinuousClock.Instant?
    private var preparedWheel = false
    /// The last tap of water or paint since the sheet was last dry.
    private var wetSince: ContinuousClock.Instant?
    private var variant = 0

    init(player: SoundPlayer = SoundPlayer(), defaults: UserDefaults = .standard) {
        self.player = player
        self.defaults = defaults
    }

    private var soundsOn: Bool { defaults.object(forKey: SettingsKey.sounds) as? Bool ?? SettingsDefault.sounds }
    private var sky: Sky { Sky.current(in: defaults) }

    // MARK: The wheel

    /// Steps closer than this sound as one, and steps faster than `brisk` softer: a flick through
    /// a century is a ripple, not a rattle.
    static let tickGap: Duration = .milliseconds(45)
    static let brisk: Duration = .milliseconds(90)

    /// The wheel came to row `row` of `rows` (0 the oldest year), lit when it opens an era.
    func wheelTurned(row: Int, of rows: Int, lit: Bool) {
        let now = self.now()
        let since = lastTick.map { now - $0 }
        if !lit, let since, since < Self.tickGap { return }
        lastTick = now
        let cue = Self.wheelCue(row: row, of: rows, lit: lit, since: since)
        player.play(cue.voice, volume: cue.volume)
        if !preparedWheel {
            preparedWheel = true
            // The rest of the wheel, and the passages it may open, are made while the painter
            // turns it, after this first step has sounded.
            player.prepare(Self.wheelVoices + [.passage(.tiles(sky)), .passage(.nave), .passage(.wash(sky)), .passage(.wayBack)])
        }
    }

    static let wheelVoices: [EraVoice] = (0..<12).map { .tick(step: $0) }

    /// Where a row sits on the Moon's scale: the oldest year lowest, the present highest.
    static func step(row: Int, of rows: Int) -> Int {
        guard rows > 1 else { return 11 }
        return Int((Double(min(max(row, 0), rows - 1)) / Double(rows - 1) * 11).rounded())
    }

    static func wheelCue(row: Int, of rows: Int, lit: Bool, since: Duration?) -> (voice: EraVoice, volume: Float) {
        let step = step(row: row, of: rows)
        if lit { return (.lit(step: step), 1) }
        let quick = since.map { $0 < brisk } ?? false
        return (.tick(step: step), quick ? 0.06 : 0.11)
    }

    // MARK: Passages

    /// A passage began: its sound, from its start, as `EraPassage` will draw it.
    func passage(to destination: Era, from origin: Era?, reduceMotion: Bool) {
        guard soundsOn else { return }
        player.play(.passage(Self.passageSound(to: destination, from: origin, reduceMotion: reduceMotion, sky: sky)), volume: 1)
    }

    /// The sound of the passage `EraPassage.draw` draws for the same arguments.
    static func passageSound(to destination: Era, from origin: Era?, reduceMotion: Bool, sky: Sky) -> EraPassageSound {
        if EraPassage.isWayBack(to: destination, from: origin, reduceMotion: reduceMotion) { return .wayBack }
        if reduceMotion { return .still(sky) }
        if destination == .glass || origin == .glass { return .nave }
        if destination == .watercolor || origin == .watercolor { return .wash(sky) }
        return .tiles(sky)
    }

    // MARK: Watercolor

    /// What a tap on a watercolor sheet did (`WatercolorPainting.tap`).
    enum WatercolorTap: Equatable {
        /// The paint in hand laid on its area; `finishes` when it was the last.
        case wash(finishes: Bool)
        /// Water on paper no wash has reached.
        case water
        /// Water on a laid wash, whatever was in hand (PaintCore's `WatercolorSim.tap`: a laid area
        /// takes water alone): a bloom.
        case bloom

        init(paint: Bool, wasLaid: Bool, finishes: Bool) {
            self = wasLaid ? .bloom : paint ? .wash(finishes: finishes) : .water
        }
    }

    /// A tap's sound. The tune moves on with each wash, as painting's does with each fill.
    func watercolor(_ tap: WatercolorTap) {
        let now = self.now()
        wetSince = now
        variant += 1
        guard soundsOn else {
            if case .wash = tap { _ = melody.next(at: now, under: sky) }
            return
        }
        for cue in Self.watercolorCues(tap, melody: &melody, at: now, sky: sky, variant: variant) {
            player.play(cue.voice, volume: cue.volume, delay: cue.delay)
        }
    }

    static func watercolorCues(_ tap: WatercolorTap, melody: inout PaintingMelody, at now: ContinuousClock.Instant,
                               sky: Sky, variant: Int) -> [(voice: EraVoice, volume: Float, delay: TimeInterval)] {
        switch tap {
        case let .wash(finishes):
            let note = melody.next(at: now, under: sky)
            var cues: [(voice: EraVoice, volume: Float, delay: TimeInterval)] = [(.wash(note.sky, index: note.index), 1, 0)]
            if finishes { cues.append((.finale(note.sky), 1, 0.7)) }
            return cues
        case .water:
            return [(.drop(variant: variant % 4), 1, 0)]
        case .bloom:
            return [(.bloom(index: melody.latest, variant: variant % 2), 1, 0)]
        }
    }

    /// How long after the last tap a sheet that has stopped moving is heard drying: a sheet still
    /// with a wash that sank in at once says nothing.
    static let dryAfter: Duration = .milliseconds(1200)

    /// A sheet opened: whatever the last was doing when it closed, this one hasn't been tapped.
    func sheetOpened() { wetSince = nil }

    /// The sheet has stopped moving (`WatercolorRenderer.onActivity`): the first time since a
    /// tap, and long enough after it, a star sounds over the tune's last note.
    func sheetDried() {
        guard let wet = wetSince else { return }
        wetSince = nil
        guard soundsOn, now() - wet >= Self.dryAfter else { return }
        player.play(.dried(index: melody.latest), volume: 1)
    }
}
#endif
