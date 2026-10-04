import Foundation

/// The sounds, haptics and flourishes of painting, each on a switch of its own (Settings ›
/// Advanced › Sounds, Haptics and Sparkles & Shine), all on by default. Each is read where it
/// plays, as it plays; the sounds and haptics also need Settings' Sounds and Haptics on.
nonisolated enum PaintingEffect: String, CaseIterable, Sendable {
    /// A note of the painting's tune per fill.
    case paintNotes
    /// The little rising tune when a color is finished.
    case colorJingle
    /// The cascade of notes when the painting is finished.
    case finishFanfare
    /// The muted knock of a wrong-color tap.
    case wrongColorSound
    /// The swell felt as paint lands.
    case fillHaptics
    /// The double tap felt on a wrong-color tap.
    case wrongColorHaptics
    /// The taps felt when a color or the painting is finished.
    case finishHaptics
    /// Two gold sparkles where a single fill lands.
    case fillSparkles
    /// The gloss that sweeps a finished color, or the finished painting.
    case finishShine

    enum Kind: Sendable { case sound, haptic, visual }

    var kind: Kind {
        switch self {
        case .paintNotes, .colorJingle, .finishFanfare, .wrongColorSound: .sound
        case .fillHaptics, .wrongColorHaptics, .finishHaptics: .haptic
        case .fillSparkles, .finishShine: .visual
        }
    }

    /// The UserDefaults key of its switch (a Bool; absent means on).
    var key: String { "paintingEffect." + rawValue }

    func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: key) as? Bool ?? true
    }
}
