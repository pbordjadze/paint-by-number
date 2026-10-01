import Foundation
import Testing
@testable import PaintByNumber

/// Painting plays one tune in order, whatever colors are painted.
@MainActor
struct PaintingMelodyTests {
    @Test func tuneFitsTheScaleInWholePhrases() {
        #expect(PaintingMelody.tune.allSatisfy { SoundPlayer.scale.indices.contains($0) })
        #expect(PaintingMelody.tune.count.isMultiple(of: PaintingMelody.phraseLength))
        #expect(PaintingMelody.tune.last == 0, "the tune comes home to C before it repeats")
    }

    @Test func notesFollowTheTuneAndLoop() {
        var melody = PaintingMelody()
        let start = ContinuousClock.now
        let count = PaintingMelody.tune.count
        let played = (0..<(count + 3)).map { melody.next(at: start + .milliseconds(400 * $0)) }
        #expect(Array(played.prefix(count)) == PaintingMelody.tune)
        #expect(Array(played.suffix(3)) == Array(PaintingMelody.tune.prefix(3)))
        #expect(melody.latest == PaintingMelody.tune[2])
    }

    @Test func aLongPauseMovesOnToTheNextPhrase() {
        var melody = PaintingMelody()
        let start = ContinuousClock.now
        _ = melody.next(at: start)
        _ = melody.next(at: start + .milliseconds(300))
        let after = melody.next(at: start + .milliseconds(300) + PaintingMelody.breath)
        #expect(after == PaintingMelody.tune[PaintingMelody.phraseLength])
        #expect(melody.position == PaintingMelody.phraseLength + 1)
    }

    @Test func aPauseAtAPhraseStartKeepsThePlace() {
        var melody = PaintingMelody()
        let start = ContinuousClock.now
        for k in 0..<PaintingMelody.phraseLength { _ = melody.next(at: start + .milliseconds(300 * k)) }
        let after = melody.next(at: start + .seconds(60))
        #expect(after == PaintingMelody.tune[PaintingMelody.phraseLength])
    }
}
