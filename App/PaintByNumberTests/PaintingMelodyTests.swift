import Foundation
import Testing
@testable import PaintByNumber

/// Painting plays one tune in order, whatever colors are painted, in the sky of the moment; the
/// sky turns only where a phrase begins.
@MainActor
struct PaintingMelodyTests {
    @Test func tuneFitsEachSkysScaleInWholePhrases() {
        for sky in [Sky.sun, .moon] {
            #expect(PaintingMelody.tune.allSatisfy { SoundPlayer.scale(of: sky).indices.contains($0) })
        }
        #expect(PaintingMelody.tune.count.isMultiple(of: PaintingMelody.phraseLength))
        #expect(PaintingMelody.tune.last == 0, "the tune comes home before it repeats")
    }

    /// The Moon sings the Sun's five notes as their minor, lower: its scale is the Sun's moved
    /// up one place, with the B below the Sun's D first.
    @Test func theMoonsScaleIsTheSunsNotesLower() {
        let sun = SoundPlayer.scale(of: .sun), moon = SoundPlayer.scale(of: .moon)
        #expect(sun.count == moon.count)
        #expect(Array(moon.dropFirst()) == Array(sun.dropLast()))
        #expect(moon[0] < sun[0])
        #expect(zip(sun, sun.dropFirst()).allSatisfy { $0 < $1 })
    }

    @Test func notesFollowTheTuneAndLoop() {
        var melody = PaintingMelody()
        let start = ContinuousClock.now
        let count = PaintingMelody.tune.count
        let played = (0..<(count + 3)).map { melody.next(at: start + .milliseconds(400 * $0), under: .sun).index }
        #expect(Array(played.prefix(count)) == PaintingMelody.tune)
        #expect(Array(played.suffix(3)) == Array(PaintingMelody.tune.prefix(3)))
        #expect(melody.latest == PaintingMelody.tune[2])
    }

    @Test func aPhrasesLastNoteRests() {
        var melody = PaintingMelody()
        let start = ContinuousClock.now
        let notes = (0..<PaintingMelody.tune.count).map { melody.next(at: start + .milliseconds(400 * $0), under: .moon) }
        #expect(notes.indices.filter { notes[$0].endsPhrase }
            == Array(stride(from: PaintingMelody.phraseLength - 1, to: notes.count, by: PaintingMelody.phraseLength)))
    }

    /// A change of sky waits for the next phrase, so it never cuts one.
    @Test func theSkyTurnsOnlyWhereAPhraseBegins() {
        var melody = PaintingMelody()
        let start = ContinuousClock.now
        #expect(melody.sky == nil)
        #expect(melody.next(at: start, under: .sun).sky == .sun)
        for k in 1..<PaintingMelody.phraseLength {
            #expect(melody.next(at: start + .milliseconds(300 * k), under: .moon).sky == .sun, "note \(k)")
        }
        let turned = melody.next(at: start + .milliseconds(300 * PaintingMelody.phraseLength), under: .moon)
        #expect(turned.sky == .moon && turned.index == PaintingMelody.tune[PaintingMelody.phraseLength])
        #expect(melody.sky == .moon)
    }

    @Test func aLongPauseMovesOnToTheNextPhrase() {
        var melody = PaintingMelody()
        let start = ContinuousClock.now
        _ = melody.next(at: start, under: .sun)
        _ = melody.next(at: start + .milliseconds(300), under: .sun)
        let after = melody.next(at: start + .milliseconds(300) + PaintingMelody.breath, under: .moon)
        #expect(after.index == PaintingMelody.tune[PaintingMelody.phraseLength])
        // The pause ended the phrase, so the new sky comes in with the next one.
        #expect(after.sky == .moon)
        #expect(melody.position == PaintingMelody.phraseLength + 1)
    }

    @Test func aPauseAtAPhraseStartKeepsThePlace() {
        var melody = PaintingMelody()
        let start = ContinuousClock.now
        for k in 0..<PaintingMelody.phraseLength { _ = melody.next(at: start + .milliseconds(300 * k), under: .sun) }
        let after = melody.next(at: start + .seconds(60), under: .sun)
        #expect(after.index == PaintingMelody.tune[PaintingMelody.phraseLength])
    }
}
