import Foundation
import PaintCore
import Testing
@testable import PaintByNumber

/// Which haptic and which sound each painting moment gets (`FeedbackEngine`), on players that say
/// what they were asked for: the simulator has no haptics and a test plays nothing aloud.
@MainActor
struct FeedbackEngineTests {
    @MainActor
    private final class Rig {
        let haptics = HapticsPlayer(isSupported: true)
        let sounds = SoundPlayer(playsAloud: false)
        let defaults: UserDefaults
        let engine: FeedbackEngine
        private let suite = "feedback-engine-tests-\(UUID().uuidString)"

        init(sky: SkySetting = .sun) {
            defaults = UserDefaults(suiteName: suite)!
            defaults.set(sky.rawValue, forKey: SettingsKey.sky)
            engine = FeedbackEngine(haptics: haptics, sounds: sounds, defaults: defaults)
        }

        deinit { UserDefaults.standard.removePersistentDomain(forName: suite) }
    }

    /// Three stripes, a color each: every fill finishes its color, and the third the painting.
    private let stripes = Fixtures.stripes(count: 3)
    /// Forty-eight tiles of a few colors.
    private let mosaic = Fixtures.mosaic

    private func center(_ template: Template, _ region: Int) -> SIMD2<Float> {
        template.labels(ofRegion: region).first?.position ?? template.anchor(ofRegion: region)
    }

    /// Paints `region` with a tap of its own color.
    private func paint(_ region: Int, in session: PaintingSession) {
        session.select(color: session.colorOf(region))
        session.tap(at: center(session.template, region), tolerance: 0)
    }

    /// Longer than the gaps under which fills share a haptic (45 ms) or a note (40 ms).
    private func rest() async throws { try await Task.sleep(for: .milliseconds(70)) }

    private typealias Cue = SoundPlayer.Cue

    private func expectClose(_ a: Float, _ b: Float, sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(abs(a - b) < 1e-4, "\(a) is not \(b)", sourceLocation: sourceLocation)
    }

    /// The same voices at the same times, as loud to a ten-thousandth.
    private func expect(_ cues: [Cue], _ expected: [Cue], sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(cues.map(\.voice) == expected.map(\.voice), sourceLocation: sourceLocation)
        #expect(cues.map(\.delay) == expected.map(\.delay), sourceLocation: sourceLocation)
        for (cue, wanted) in zip(cues, expected) { expectClose(cue.volume, wanted.volume, sourceLocation: sourceLocation) }
    }

    /// The mosaic's color with the most tiles, selected, and its tiles: room for four fills that
    /// finish nothing.
    private func roomiestColor(of session: PaintingSession) throws -> [Int] {
        let tiles = Dictionary(grouping: mosaic.regions.indices, by: session.colorOf)
        let (color, areas) = try #require(tiles.max { ($0.value.count, -$0.key) < ($1.value.count, -$1.key) })
        try #require(areas.count >= 5, "no color of the mosaic has five tiles")
        session.select(color: color)
        return areas.sorted()
    }

    /// A fill is a press and a note of the tune, both heavier for a bigger area: a tile of the
    /// mosaic, about a fiftieth of the canvas, plays at about nine tenths.
    @Test func aFillIsAPressAndTheTunesNextNote() async throws {
        let rig = Rig()
        let session = PaintingSession(template: mosaic)
        rig.engine.attach(to: session)
        let areas = try roomiestColor(of: session)
        let size = { (region: Int) -> Float in
            min(1, (self.mosaic.regions[region].area / Float(self.mosaic.width * self.mosaic.height)).squareRoot() * 6)
        }

        paint(areas[0], in: session)
        #expect(rig.haptics.played() == ["paint"])
        let press = try #require(rig.haptics.patterns().first)
        expectClose(press.events[0].intensity, 0.45 + 0.4 * size(areas[0]))
        // As long as the fill's animation (`fillDuration`).
        #expect(abs(press.events[1].duration - 0.4) < 1e-9)
        var cues = rig.sounds.played()
        // The tune's first note, on the Sun's scale.
        #expect(cues.map(\.voice) == [.note(.sun, index: 2)])
        expectClose(try #require(cues.first).volume, 0.18 + 0.22 * (0.35 + 0.65 * size(areas[0])))
        #expect((0.5..<1).contains(size(areas[0])), "the tile's size isn't what this test is about: \(size(areas[0]))")

        // Each later fill plays the tune's next note.
        try await rest()
        paint(areas[1], in: session)
        try await rest()
        paint(areas[2], in: session)
        cues = rig.sounds.played()
        #expect(cues.map(\.voice) == [.note(.sun, index: 2), .note(.sun, index: 3), .note(.sun, index: 4)])
        #expect(rig.haptics.played() == ["paint", "paint", "paint"])
    }

    /// A stroke's fills come faster than notes can sound: a fill within 40 ms of the last note
    /// plays none; at 40 ms it plays the tune's next.
    @Test func fillsCloseTogetherShareANote() throws {
        let rig = Rig()
        let session = PaintingSession(template: mosaic)
        rig.engine.attach(to: session)
        let areas = try roomiestColor(of: session)
        let start = ContinuousClock.now
        var elapsed = Duration.zero
        rig.engine.now = { start + elapsed }
        paint(areas[0], in: session)
        elapsed = .milliseconds(39)
        paint(areas[1], in: session)
        #expect(rig.sounds.played().map(\.voice) == [.note(.sun, index: 2)])
        elapsed = .milliseconds(40)
        paint(areas[2], in: session)
        #expect(rig.sounds.played().map(\.voice) == [.note(.sun, index: 2), .note(.sun, index: 3)])
        elapsed = .milliseconds(79)
        paint(areas[3], in: session)
        #expect(rig.sounds.played().count == 2)
    }

    /// After five seconds' rest the tune picks up where its next phrase begins.
    @Test func theTuneTakesABreath() throws {
        let rig = Rig()
        let session = PaintingSession(template: mosaic)
        rig.engine.attach(to: session)
        let areas = try roomiestColor(of: session)
        let start = ContinuousClock.now
        var elapsed = Duration.zero
        rig.engine.now = { start + elapsed }
        paint(areas[0], in: session)
        elapsed = .seconds(1)
        paint(areas[1], in: session)
        elapsed = .seconds(6)
        paint(areas[2], in: session)
        // The first phrase's first two notes, then the second phrase's first (`PaintingMelody.tune`).
        #expect(rig.sounds.played().map(\.voice) == [.note(.sun, index: 2), .note(.sun, index: 3), .note(.sun, index: 2)])
        #expect(PaintingMelody.tune[8] == 2 && PaintingMelody.breath == .seconds(5))
    }

    /// A tap on another color's area: the dull double tap and the thud.
    @Test func aWrongColorIsRejected() throws {
        let rig = Rig()
        let session = PaintingSession(template: mosaic)
        rig.engine.attach(to: session)
        let color = try #require(session.selectedColor)
        let other = try #require(mosaic.regions.indices.first { session.colorOf($0) != color })
        session.tap(at: center(mosaic, other), tolerance: 0)
        #expect(!session.isPainted(other))
        #expect(rig.haptics.played() == ["reject"])
        expect(rig.sounds.played(), SoundPlayer.rejectCues)
    }

    /// The fill that finishes a color adds the bright triple and the arpeggio from the note it
    /// played; the fill that finishes the painting gets the finale alone, not its color's too.
    @Test func aFinishedColorAndAFinishedPainting() async throws {
        let rig = Rig()
        let session = PaintingSession(template: stripes)
        rig.engine.attach(to: session)

        paint(0, in: session)
        #expect(rig.haptics.played() == ["paint", "colorComplete"])
        // A stripe is a third of the canvas: full strength, the loudest note.
        expectClose(try #require(rig.haptics.patterns().first).events[0].intensity, 0.85)
        expect(rig.sounds.played(), [Cue(voice: .note(.sun, index: 2), volume: 0.4)] + SoundPlayer.colorCompleteCues(sky: .sun, from: 2))

        try await rest()
        paint(1, in: session)
        try await rest()
        paint(2, in: session)
        #expect(session.isComplete)
        #expect(rig.haptics.played() == ["paint", "colorComplete", "paint", "colorComplete", "paint", "celebrate"])
        let expected = [Cue(voice: .note(.sun, index: 2), volume: 0.4)] + SoundPlayer.colorCompleteCues(sky: .sun, from: 2)
            + [Cue(voice: .note(.sun, index: 3), volume: 0.4)] + SoundPlayer.colorCompleteCues(sky: .sun, from: 3)
            + [Cue(voice: .note(.sun, index: 4), volume: 0.4)] + SoundPlayer.celebrateCues(sky: .sun)
        expect(rig.sounds.played(), expected)
    }

    /// By Moon the same moments play the Moon's voice and flourishes.
    @Test func theMoonPlaysItsOwnVoice() async throws {
        let rig = Rig(sky: .moon)
        let session = PaintingSession(template: stripes)
        rig.engine.attach(to: session)
        #expect(rig.engine.skyOfComingFill() == .moon)
        paint(0, in: session)
        try await rest()
        paint(1, in: session)
        try await rest()
        paint(2, in: session)
        let expected = [Cue(voice: .note(.moon, index: 2), volume: 0.34)] + SoundPlayer.colorCompleteCues(sky: .moon, from: 2)
            + [Cue(voice: .note(.moon, index: 3), volume: 0.34)] + SoundPlayer.colorCompleteCues(sky: .moon, from: 3)
            + [Cue(voice: .note(.moon, index: 4), volume: 0.34)] + SoundPlayer.celebrateCues(sky: .moon)
        expect(rig.sounds.played(), expected)
    }

    /// An undo and a change of color are each one light tap, with no sound; the hint and a
    /// stroke's end are silent.
    @Test func undoAndSelectionAreDetents() throws {
        let rig = Rig()
        let session = PaintingSession(template: mosaic)
        rig.engine.attach(to: session)
        let area = try roomiestColor(of: session)[0]
        paint(area, in: session)
        session.undo()
        rig.engine.selectionChanged()
        session.showHint()
        session.beginStroke()
        session.endStroke()
        #expect(rig.haptics.played() == ["paint", "tick", "tick"])
        #expect(rig.sounds.played().count == 1)
    }

    /// Refine's "an area of its own": a soft, short press.
    @Test func anAreaMadeIsASoftTap() throws {
        let rig = Rig()
        rig.engine.areaMade()
        let pattern = try #require(rig.haptics.patterns().first)
        #expect(pattern.name == "paint")
        expectClose(pattern.events[0].intensity, 0.57)
        #expect(abs(pattern.events[1].duration - 0.12) < 1e-9)
    }

    /// Settings › Haptics and Sounds are read at each moment: off, that side plays nothing.
    @Test func theSettingsSwitchEachSideOff() async throws {
        let rig = Rig()
        let session = PaintingSession(template: mosaic)
        rig.engine.attach(to: session)
        let areas = try roomiestColor(of: session)

        rig.defaults.set(false, forKey: SettingsKey.haptics)
        paint(areas[0], in: session)
        rig.engine.selectionChanged()
        #expect(rig.haptics.played().isEmpty)
        #expect(rig.sounds.played().count == 1)

        rig.defaults.set(true, forKey: SettingsKey.haptics)
        rig.defaults.set(false, forKey: SettingsKey.sounds)
        try await rest()
        paint(areas[1], in: session)
        #expect(rig.haptics.played() == ["paint"])
        #expect(rig.sounds.played().count == 1)

        // The tune played on with the sounds off: the next note heard is the third.
        rig.defaults.set(true, forKey: SettingsKey.sounds)
        try await rest()
        paint(areas[2], in: session)
        #expect(rig.sounds.played().map(\.voice) == [.note(.sun, index: 2), .note(.sun, index: 4)])
    }

    /// A session attached again (its screen appearing again) is still heard once.
    @Test func aSessionAttachedTwiceIsHeardOnce() throws {
        let rig = Rig()
        let session = PaintingSession(template: mosaic)
        rig.engine.attach(to: session)
        rig.engine.attach(to: session)
        let area = try roomiestColor(of: session)[0]
        paint(area, in: session)
        #expect(rig.haptics.played() == ["paint"])
        #expect(rig.sounds.played().count == 1)
    }
}
