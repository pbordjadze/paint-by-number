import Foundation

/// The tune painting plays: each fill plays the next note, whatever color was painted, so
/// any painting order sounds like the same gentle melody.
nonisolated struct PaintingMelody {
    /// Indices into `SoundPlayer.scale` (C major pentatonic from C4): six eight-note phrases
    /// that rise, answer and settle back home on C, then start over.
    static let tune: [Int] = [
        2, 3, 4, 3, 2, 1, 0, 1,
        2, 3, 4, 5, 4, 3, 2, 3,
        4, 5, 6, 7, 6, 5, 4, 5,
        6, 7, 8, 7, 6, 5, 4, 3,
        2, 3, 4, 3, 2, 1, 2, 3,
        5, 4, 3, 2, 1, 2, 1, 0,
    ]
    static let phraseLength = 8
    /// After a pause this long the tune picks up at the start of its next phrase, so coming
    /// back to a painting doesn't resume mid-phrase.
    static let breath: Duration = .seconds(5)

    private(set) var position = 0
    /// The most recently played note (the tune's first before any).
    private(set) var latest = Self.tune[0]
    private var lastPlayed: ContinuousClock.Instant?

    /// The note to play for a fill at `now`.
    mutating func next(at now: ContinuousClock.Instant) -> Int {
        if let lastPlayed, now - lastPlayed >= Self.breath, !position.isMultiple(of: Self.phraseLength) {
            position = (position / Self.phraseLength + 1) * Self.phraseLength % Self.tune.count
        }
        lastPlayed = now
        latest = Self.tune[position]
        position = (position + 1) % Self.tune.count
        return latest
    }
}
