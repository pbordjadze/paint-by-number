import Foundation
import PaintCore

/// UserDefaults keys of user preferences (views bind them with `@AppStorage`).
enum PreferenceKey {
    static let haptics = FeedbackEngine.Keys.haptics
    static let sounds = FeedbackEngine.Keys.sounds
    static let autoAdvance = "autoAdvanceColors"
    static let defaultColorCount = "defaultColorCount"
    static let paperSize = "printPaperSize"
}

/// A snapshot of the user's preferences, with their defaults.
struct Preferences: Equatable {
    var haptics: Bool
    var sounds: Bool
    /// Select the next unfinished color when one is completed.
    var autoAdvance: Bool
    /// Colors a new painting starts with in the create flow.
    var defaultColorCount: Int
    var paper: PDFExporter.Paper

    static let defaultColorCountValue = 24

    init(defaults: UserDefaults = .standard) {
        haptics = defaults.object(forKey: PreferenceKey.haptics) as? Bool ?? true
        sounds = defaults.object(forKey: PreferenceKey.sounds) as? Bool ?? true
        autoAdvance = defaults.object(forKey: PreferenceKey.autoAdvance) as? Bool ?? true
        let colors = defaults.object(forKey: PreferenceKey.defaultColorCount) as? Int ?? Self.defaultColorCountValue
        defaultColorCount = min(max(colors, GenerationSettings.colorCountRange.lowerBound), GenerationSettings.colorCountRange.upperBound)
        paper = defaults.string(forKey: PreferenceKey.paperSize).flatMap(PDFExporter.Paper.init(rawValue:))
            ?? .default(for: Locale.current.region)
    }

    /// Settings a new painting starts from.
    var initialGenerationSettings: GenerationSettings {
        GenerationSettings(colorCount: defaultColorCount)
    }

    func apply(to session: PaintingSession) {
        session.autoAdvance = autoAdvance
    }
}
