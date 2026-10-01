import Foundation
import PaintCore

/// UserDefaults keys of user preferences (views bind them with `@AppStorage`).
enum SettingsKey {
    static let haptics = FeedbackEngine.Keys.haptics
    static let sounds = FeedbackEngine.Keys.sounds
    static let autoAdvance = "autoAdvanceColors"
    static let paintingLength = "paintingLength"
    static let paperSize = "printPaperSize"
    static let timelapsePace = "timelapsePace"
    static let paperAppearance = "paperAppearance"
    static let colorNames = "colorNameStyle"
}

/// A snapshot of the user's preferences, with their defaults.
struct Preferences: Equatable {
    var haptics: Bool
    var sounds: Bool
    /// Select the next unfinished color when one is completed.
    var autoAdvance: Bool
    /// How long a painting Suggested settings aim for in the create flow.
    var paintingLength: PaintingLength
    var paper: PDFExporter.Paper
    /// The paper the painting canvas shows.
    var paperAppearance: PaperAppearance
    /// Whether paints go by playful nicknames or their plain structured names.
    var colorNames: ColorNameStyle

    init(defaults: UserDefaults = .standard) {
        haptics = defaults.object(forKey: SettingsKey.haptics) as? Bool ?? true
        sounds = defaults.object(forKey: SettingsKey.sounds) as? Bool ?? true
        autoAdvance = defaults.object(forKey: SettingsKey.autoAdvance) as? Bool ?? true
        paintingLength = defaults.string(forKey: SettingsKey.paintingLength).flatMap(PaintingLength.init(rawValue:))
            ?? .default
        paper = defaults.string(forKey: SettingsKey.paperSize).flatMap(PDFExporter.Paper.init(rawValue:))
            ?? .default(for: Locale.current.region)
        paperAppearance = defaults.string(forKey: SettingsKey.paperAppearance).flatMap(PaperAppearance.init(rawValue:))
            ?? .default
        colorNames = defaults.string(forKey: SettingsKey.colorNames).flatMap(ColorNameStyle.init(rawValue:)) ?? .playful
    }

    func apply(to session: PaintingSession) {
        session.autoAdvance = autoAdvance
        session.colorNameStyle = colorNames
    }
}

/// Settings › Painting Length: what Suggested settings aim for.
nonisolated extension PaintingLength {
    static let `default` = PaintingLength.relaxed

    var name: String {
        switch self {
        case .quick: String(localized: "paintingLength.quick", defaultValue: "Quick",
                            comment: "Choice of the Painting Length setting: suggested settings aim for a short painting")
        case .relaxed: String(localized: "paintingLength.relaxed", defaultValue: "Relaxed",
                              comment: "Choice of the Painting Length setting: suggested settings aim for about an hour of painting")
        case .detailed: String(localized: "paintingLength.detailed", defaultValue: "Detailed",
                               comment: "Choice of the Painting Length setting: suggested settings aim for a long, detailed painting")
        }
    }

    /// The Settings footer under the picker: roughly the painting time the choice aims for
    /// (`timeBand`).
    var footer: String {
        switch self {
        case .quick: String(localized: "settings.paintingLength.footer.quick",
                            defaultValue: "Suggested settings aim for about half an hour of painting.",
                            comment: "Footer under the Painting Length setting when Quick is chosen")
        case .relaxed: String(localized: "settings.paintingLength.footer.relaxed",
                              defaultValue: "Suggested settings aim for about an hour of painting.",
                              comment: "Footer under the Painting Length setting when Relaxed is chosen")
        case .detailed: String(localized: "settings.paintingLength.footer.detailed",
                               defaultValue: "Suggested settings aim for a few hours of painting.",
                               comment: "Footer under the Painting Length setting when Detailed is chosen")
        }
    }
}
