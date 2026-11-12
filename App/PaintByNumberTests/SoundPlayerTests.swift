import Foundation
import Testing
@testable import PaintByNumber

/// What each painting moment sounds like: which notes of which voice, how loud and when
/// (`SoundPlayer.Cue`), the scales they are on, and each voice's own sound (`ToneSynth`), pinned by
/// its length, peak, loudness and pitch. Nothing else hears a sound that changed.
struct SoundPlayerTests {
    private typealias Cue = SoundPlayer.Cue

    private func expect(_ cues: [Cue], _ expected: [Cue], sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(cues.map(\.voice) == expected.map(\.voice), sourceLocation: sourceLocation)
        guard cues.count == expected.count else { return }
        for (i, (cue, wanted)) in zip(cues, expected).enumerated() {
            #expect(abs(cue.volume - wanted.volume) < 1e-5, "cue \(i): volume \(cue.volume)", sourceLocation: sourceLocation)
            #expect(abs(cue.delay - wanted.delay) < 1e-9, "cue \(i): delay \(cue.delay)", sourceLocation: sourceLocation)
        }
    }

    private func note(_ sky: Sky, _ index: Int, ends: Bool = false) -> PaintingMelody.Note {
        PaintingMelody.Note(sky: sky, index: index, endsPhrase: ends)
    }

    // MARK: The scales

    /// Sun: D major pentatonic over two octaves from D4. Moon: the same notes from the B below.
    @Test func theScalesAreTheSameFiveNotesAThirdApart() {
        #expect(SoundPlayer.sunScale == [293.66, 329.63, 369.99, 440.00, 493.88, 587.33, 659.26, 739.99, 880.00, 987.77, 1174.66, 1318.51])
        #expect(SoundPlayer.moonScale == [246.94, 293.66, 329.63, 369.99, 440.00, 493.88, 587.33, 659.26, 739.99, 880.00, 987.77, 1174.66])
        #expect(SoundPlayer.scale(of: .sun) == SoundPlayer.sunScale)
        #expect(SoundPlayer.scale(of: .moon) == SoundPlayer.moonScale)
        // Every note of the tune is on both.
        #expect(PaintingMelody.tune.allSatisfy { SoundPlayer.sunScale.indices.contains($0) })
    }

    // MARK: The moments

    /// A fill plays its note, louder for a bigger area, between 0.18 and 0.40; the Moon's bell a
    /// little softer.
    @Test func aFillPlaysItsNoteLouderForABiggerArea() {
        expect(SoundPlayer.paintCues(note(.sun, 3), velocity: 0.5), [Cue(voice: .note(.sun, index: 3), volume: 0.29)])
        expect(SoundPlayer.paintCues(note(.sun, 0), velocity: -1), [Cue(voice: .note(.sun, index: 0), volume: 0.18)])
        expect(SoundPlayer.paintCues(note(.sun, 11), velocity: 2), [Cue(voice: .note(.sun, index: 11), volume: 0.40)])
        expect(SoundPlayer.paintCues(note(.moon, 3), velocity: 0.5), [Cue(voice: .note(.moon, index: 3), volume: 0.2465)])
        // The Sun never twinkles, wherever its phrase rests.
        expect(SoundPlayer.paintCues(note(.sun, 1, ends: true), velocity: 0.5), [Cue(voice: .note(.sun, index: 1), volume: 0.29)])
    }

    /// Where the Moon's phrase comes to rest a quiet star twinkles an octave above, 0.12 s after.
    @Test func theMoonTwinklesWhereAPhraseRests() {
        expect(SoundPlayer.paintCues(note(.moon, 1, ends: true), velocity: 0.5), [
            Cue(voice: .note(.moon, index: 1), volume: 0.2465),
            Cue(voice: .twinkle(index: 1), volume: 0.086275, delay: 0.12),
        ])
    }

    @Test func aWrongColorIsOneThud() {
        expect(SoundPlayer.rejectCues, [Cue(voice: .thud, volume: 0.35)])
    }

    /// A finished color: three notes rising from the tune's latest, the Moon's slower and softer;
    /// from high in the scale the arpeggio starts no higher than it can finish.
    @Test func aFinishedColorIsARisingArpeggio() {
        expect(SoundPlayer.colorCompleteCues(sky: .sun, from: 2), [
            Cue(voice: .note(.sun, index: 2), volume: 0.3, delay: 0.12),
            Cue(voice: .note(.sun, index: 4), volume: 0.3, delay: 0.205),
            Cue(voice: .note(.sun, index: 6), volume: 0.3, delay: 0.29),
        ])
        expect(SoundPlayer.colorCompleteCues(sky: .moon, from: 2), [
            Cue(voice: .note(.moon, index: 2), volume: 0.255, delay: 0.14),
            Cue(voice: .note(.moon, index: 4), volume: 0.255, delay: 0.26),
            Cue(voice: .note(.moon, index: 6), volume: 0.255, delay: 0.38),
        ])
        #expect(SoundPlayer.colorCompleteCues(sky: .sun, from: 8).map(\.voice)
            == [.note(.sun, index: 7), .note(.sun, index: 9), .note(.sun, index: 11)])
        #expect(SoundPlayer.colorCompleteCues(sky: .moon, from: 11).map(\.voice)
            == [.note(.moon, index: 7), .note(.moon, index: 9), .note(.moon, index: 11)])
    }

    /// The Sun's finale: a run up all twelve notes, a little louder each, to an open chord.
    @Test func theSunsFinaleRunsUpToAChord() {
        var expected = (0..<12).map { Cue(voice: .note(.sun, index: $0), volume: 0.22 + 0.01 * Float($0), delay: 0.07 * Double($0)) }
        expected += [5, 7, 9, 11].map { Cue(voice: .note(.sun, index: $0), volume: 0.28, delay: 0.96) }
        let cues = SoundPlayer.celebrateCues(sky: .sun)
        expect(cues, expected)
        // The ends of the run, as numbers: the formula above is the code's own.
        #expect(abs(cues[0].volume - 0.22) < 1e-5 && cues[0].delay == 0)
        #expect(abs(cues[11].volume - 0.33) < 1e-5 && abs(cues[11].delay - 0.77) < 1e-9)
    }

    /// The Moon's: a slower, softer run down to a warm low chord, one star left ringing above it.
    @Test func theMoonsFinaleRunsDownToAChordAndAStar() {
        var expected = (0..<12).map { k in
            Cue(voice: .note(.moon, index: 11 - k), volume: (0.24 - 0.005 * Float(k)) * 0.85, delay: 0.1 * Double(k))
        }
        expected += [0, 1, 3, 4].map { Cue(voice: .note(.moon, index: $0), volume: 0.221, delay: 1.35) }
        expected.append(Cue(voice: .twinkle(index: 5), volume: 0.2, delay: 1.7))
        let cues = SoundPlayer.celebrateCues(sky: .moon)
        expect(cues, expected)
        #expect(abs(cues[0].volume - 0.204) < 1e-5 && cues[0].delay == 0)
        #expect(abs(cues[11].volume - 0.15725) < 1e-5 && abs(cues[11].delay - 1.1) < 1e-9)
    }

    /// The player plays a moment's cues in the order asked, moment after moment (here with its
    /// engine off: `played()` is what it would have played).
    @Test func thePlayerPlaysEachMomentsCuesInOrder() {
        let sounds = SoundPlayer(playsAloud: false)
        sounds.prepare(sky: .moon)
        sounds.paint(note(.moon, 1, ends: true), velocity: 0.5)
        sounds.reject()
        sounds.colorComplete(sky: .sun, from: 2)
        sounds.celebrate(sky: .moon)
        let expected = SoundPlayer.paintCues(note(.moon, 1, ends: true), velocity: 0.5) + SoundPlayer.rejectCues
            + SoundPlayer.colorCompleteCues(sky: .sun, from: 2) + SoundPlayer.celebrateCues(sky: .moon)
        #expect(sounds.played() == expected)
        #expect(expected.count == 2 + 1 + 3 + 17)
    }

    /// Each cue's voice is the sound it names: a sky's note is that sky's voice at the note's pitch
    /// on its scale, a twinkle the star an octave above the Moon's note, the thud the thud. (That a
    /// delayed cue sounds at its delay is the audio engine's scheduling, which no test hears.)
    @Test func eachVoiceIsTheSoundItNames() throws {
        let sounds = SoundPlayer(playsAloud: false)
        for index in SoundPlayer.sunScale.indices {
            #expect(sounds.samples(of: .note(.sun, index: index)) == ToneSynth.kalimba(frequency: SoundPlayer.sunScale[index], sampleRate: 44_100),
                    "the Sun's note \(index)")
            #expect(sounds.samples(of: .note(.moon, index: index)) == ToneSynth.celesta(frequency: SoundPlayer.moonScale[index], sampleRate: 44_100),
                    "the Moon's note \(index)")
            #expect(sounds.samples(of: .twinkle(index: index)) == ToneSynth.twinkle(frequency: 2 * SoundPlayer.moonScale[index], sampleRate: 44_100),
                    "the twinkle over the Moon's note \(index)")
        }
        #expect(sounds.samples(of: .thud) == ToneSynth.thud(sampleRate: 44_100))
        // Asking what a voice sounds like plays nothing.
        #expect(sounds.played().isEmpty)
    }

    // MARK: The voices

    /// A voice's sound in a few numbers: its length, its peak, its loudness (RMS) and how often it
    /// crosses zero in its first tenth of a second (its pitch and its partials), within tolerances
    /// a libm's last bits can't reach.
    private func expect(
        _ samples: [Float], count: Int, peak: Float, rms: Float, crossings: Int, sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let loudest = samples.map(abs).max() ?? 0
        let loudness = (samples.reduce(Float(0)) { $0 + $1 * $1 } / Float(max(samples.count, 1))).squareRoot()
        let head = samples.prefix(4410)
        let crossed = zip(head, head.dropFirst()).count { ($0 < 0) != ($1 < 0) }
        #expect(samples.count == count, sourceLocation: sourceLocation)
        #expect(abs(loudest - peak) < 2e-4, "peak \(loudest)", sourceLocation: sourceLocation)
        #expect(abs(loudness - rms) < 2e-5, "rms \(loudness)", sourceLocation: sourceLocation)
        #expect(abs(crossed - crossings) <= 1, "crossings \(crossed)", sourceLocation: sourceLocation)
        #expect(samples.allSatisfy { $0.isFinite && abs($0) <= 1 }, sourceLocation: sourceLocation)
    }

    /// The Sun's kalimba: its lowest, a middle and its highest note.
    @Test func theKalimbaSoundsAsItDid() {
        expect(ToneSynth.kalimba(frequency: 293.66, sampleRate: 44_100), count: 33_075, peak: 0.70666, rms: 0.126049, crossings: 64)
        expect(ToneSynth.kalimba(frequency: 587.33, sampleRate: 44_100), count: 33_075, peak: 0.71560, rms: 0.125934, crossings: 125)
        expect(ToneSynth.kalimba(frequency: 1318.51, sampleRate: 44_100), count: 33_075, peak: 0.69615, rms: 0.126019, crossings: 276)
    }

    /// The Moon's bell, each note a few cents off and struck a little harder or softer, the same
    /// at every launch.
    @Test func theCelestaSoundsAsItDid() {
        expect(ToneSynth.celesta(frequency: 246.94, sampleRate: 44_100), count: 70_560, peak: 0.62543, rms: 0.129212, crossings: 50)
        expect(ToneSynth.celesta(frequency: 493.88, sampleRate: 44_100), count: 70_560, peak: 0.60764, rms: 0.129154, crossings: 99)
        expect(ToneSynth.celesta(frequency: 1174.66, sampleRate: 44_100), count: 70_560, peak: 0.62499, rms: 0.129188, crossings: 236)
    }

    /// The star's twinkle (an octave above a Moon note) and the wrong color's thud.
    @Test func theTwinkleAndTheThudSoundAsTheyDid() {
        expect(ToneSynth.twinkle(frequency: 2 * 493.88, sampleRate: 44_100), count: 35_280, peak: 0.52838, rms: 0.122619, crossings: 197)
        expect(ToneSynth.thud(sampleRate: 44_100), count: 7_938, peak: 0.52439, rms: 0.119856, crossings: 26)
    }
}
