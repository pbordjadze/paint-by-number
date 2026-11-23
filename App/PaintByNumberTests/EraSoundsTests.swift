#if UNRELEASED
import CoreGraphics
import Foundation
import PaintCore
import Testing
@testable import PaintByNumber

/// The hidden modes' sounds (`EraSounds`, `EraSynth`; painting-company row 381): which moment
/// plays which, on a player that says what it was asked for, and that every sound is made whole,
/// in time with the passage it goes with, and never louder than full scale.
@MainActor
struct EraSoundsTests {
    @MainActor
    private final class Rig {
        let player = SoundPlayer(playsAloud: false)
        let defaults: UserDefaults
        let sounds: EraSounds
        var clock = ContinuousClock.now
        private let suite = "era-sounds-tests-\(UUID().uuidString)"

        init(sky: SkySetting = .moon, soundsOn: Bool = true) {
            defaults = UserDefaults(suiteName: suite)!
            defaults.set(sky.rawValue, forKey: SettingsKey.sky)
            defaults.set(soundsOn, forKey: SettingsKey.sounds)
            sounds = EraSounds(player: player, defaults: defaults)
            sounds.now = { [unowned self] in clock }
        }

        func wait(_ duration: Duration) { clock += duration }

        var played: [EraVoice] {
            player.played().compactMap { if case let .era(voice) = $0.voice { voice } else { nil } }
        }

        deinit { UserDefaults.standard.removePersistentDomain(forName: suite) }
    }

    @Test func scalesAreThePaintingsOwn() {
        #expect(EraSynth.sunScale == SoundPlayer.sunScale)
        #expect(EraSynth.moonScale == SoundPlayer.moonScale)
    }

    @Test func passagesKeepTheDrawingsTime() {
        typealias T = EraSynth.Times
        #expect(T.wait == EraPassage.wait && T.cover == EraPassage.cover && T.hold == EraPassage.hold && T.lift == EraPassage.lift)
        #expect(T.WayBack.cover == EraWayBack.cover && T.WayBack.fall == EraWayBack.fall && T.WayBack.still == EraWayBack.still)
        #expect(T.WayBack.laid == EraWayBack.laid && T.WayBack.clears == EraWayBack.clears)
        let stars = EraWayBack.sky(in: CGSize(width: 1024, height: 1366)).stars
        #expect(stars.indices.map(T.WayBack.star) == stars.map(\.appears))
    }

    @Test func eachPassageSoundsAsItIsDrawn() {
        func sound(_ to: Era, _ from: Era?, reduce: Bool = false) -> EraPassageSound {
            EraSounds.passageSound(to: to, from: from, reduceMotion: reduce, sky: .sun)
        }
        #expect(sound(.byzantium, .moonlight) == .tiles(.sun))
        #expect(sound(.moonlight, .byzantium) == .wayBack)
        #expect(sound(.glass, .moonlight) == .nave)
        #expect(sound(.moonlight, .glass) == .nave)
        #expect(sound(.watercolor, .moonlight) == .wash(.sun))
        #expect(sound(.moonlight, .watercolor) == .wash(.sun))
        #expect(sound(.frame, .moonlight) == .tiles(.sun))
        #expect(sound(.moonlight, .frame) == .tiles(.sun))
        #expect(sound(.moonlight, .byzantium, reduce: true) == .still(.sun))
        #expect(sound(.glass, .moonlight, reduce: true) == .still(.sun))
    }

    @Test func aPassagePlaysUnlessSoundsAreOff() {
        let rig = Rig()
        rig.sounds.passage(to: .glass, from: .moonlight, reduceMotion: false)
        #expect(rig.played == [.passage(.nave)])
        let off = Rig(soundsOn: false)
        off.sounds.passage(to: .glass, from: .moonlight, reduceMotion: false)
        #expect(off.played.isEmpty)
    }

    @Test func theWheelIsLowerTheFurtherBack() {
        #expect(EraSounds.step(row: 0, of: 40) == 0)
        #expect(EraSounds.step(row: 39, of: 40) == 11)
        #expect(EraSounds.step(row: 20, of: 40) == 6)
        #expect(EraSounds.step(row: 99, of: 40) == 11)
        #expect(EraSounds.step(row: 0, of: 1) == 11)
    }

    @Test func aFlickRipplesAndAnEraClicksIntoPlace() {
        let rig = Rig()
        rig.sounds.wheelTurned(row: 39, of: 40, lit: false)
        rig.wait(.milliseconds(10))
        rig.sounds.wheelTurned(row: 38, of: 40, lit: false) // too close: one sound
        rig.wait(.milliseconds(50))
        rig.sounds.wheelTurned(row: 37, of: 40, lit: false)
        rig.wait(.milliseconds(5))
        rig.sounds.wheelTurned(row: 20, of: 40, lit: true) // an era's year is never swallowed
        #expect(rig.played == [.tick(step: 11), .tick(step: 10), .lit(step: 6)])
        let volumes = rig.player.played().map(\.volume)
        #expect(volumes == [0.44, 0.24, 1])
    }

    @Test func watercolorTapsSoundAsWhatTheyDo() {
        let rig = Rig()
        rig.sounds.watercolor(.wash(finishes: false))
        rig.sounds.watercolor(.wash(finishes: false))
        rig.sounds.watercolor(.water)
        rig.sounds.watercolor(.bloom)
        rig.sounds.watercolor(.wash(finishes: true))
        let tune = PaintingMelody.tune
        #expect(rig.played == [
            .wash(.moon, index: tune[0]), .wash(.moon, index: tune[1]),
            .drop(variant: 3), .bloom(index: tune[1], variant: 0),
            .wash(.moon, index: tune[2]), .finale(.moon),
        ])
        #expect(rig.player.played()[5].delay == 0.7)
    }

    @Test func aLaidAreaBloomsWhateverIsInHand() {
        typealias Tap = EraSounds.WatercolorTap
        #expect(Tap(paint: true, wasLaid: false, finishes: false) == .wash(finishes: false))
        #expect(Tap(paint: true, wasLaid: false, finishes: true) == .wash(finishes: true))
        #expect(Tap(paint: true, wasLaid: true, finishes: true) == .bloom)
        #expect(Tap(paint: false, wasLaid: true, finishes: false) == .bloom)
        #expect(Tap(paint: false, wasLaid: false, finishes: false) == .water)
    }

    @Test func soundsOffWatercolorIsSilentButTheTuneGoesOn() {
        let rig = Rig(soundsOn: false)
        rig.sounds.watercolor(.wash(finishes: false))
        rig.sounds.watercolor(.bloom)
        #expect(rig.played.isEmpty)
        rig.defaults.set(true, forKey: SettingsKey.sounds)
        rig.sounds.watercolor(.wash(finishes: false))
        #expect(rig.played == [.wash(.moon, index: PaintingMelody.tune[1])])
    }

    @Test func theSheetIsHeardDryingOnceAndNotAtOnce() {
        let rig = Rig()
        rig.sounds.sheetDried() // nothing wet yet
        rig.sounds.watercolor(.water)
        rig.wait(.milliseconds(300))
        rig.sounds.sheetDried() // sank in at once: silent
        rig.sounds.watercolor(.wash(finishes: false))
        rig.wait(.seconds(3))
        rig.sounds.sheetDried()
        rig.sounds.sheetDried() // still: once
        rig.sounds.watercolor(.water)
        rig.wait(.seconds(3))
        rig.sounds.sheetOpened() // left wet; another sheet opens dry
        rig.sounds.sheetDried()
        #expect(rig.played.filter { if case .dried = $0 { true } else { false } } == [.dried(index: PaintingMelody.tune[0])])
    }

    @Test(arguments: [
        EraVoice.tick(step: 0), .tick(step: 11), .lit(step: 5),
        .passage(.tiles(.sun)), .passage(.tiles(.moon)), .passage(.nave), .passage(.wash(.moon)),
        .passage(.wayBack), .passage(.still(.sun)),
        .wash(.sun, index: 11), .wash(.moon, index: 0), .drop(variant: 3), .bloom(index: 11, variant: 1),
        .dried(index: 4), .finale(.sun), .finale(.moon),
    ])
    func everySoundIsWholeAndUnderFullScale(_ voice: EraVoice) {
        let samples = EraSynth.samples(of: voice)
        #expect(!samples.isEmpty)
        #expect(samples.allSatisfy { $0.isFinite })
        #expect((samples.map(abs).max() ?? 0) < 0.6)
        // Each ends in silence: no click as its buffer stops.
        #expect(samples.suffix(64).allSatisfy { abs($0) < 0.002 })
        #expect(EraSynth.samples(of: voice) == samples)
    }

    @Test func thePlayerHandsTheSynthesisOver() {
        let player = SoundPlayer(playsAloud: false)
        #expect(player.samples(of: .era(.tick(step: 3))) == EraSynth.samples(of: .tick(step: 3)))
    }
}
#endif
