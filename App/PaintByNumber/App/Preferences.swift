import Foundation
import PaintCore

/// UserDefaults keys of user preferences (views bind them with `@AppStorage`).
enum SettingsKey {
    static let haptics = "hapticsEnabled"
    static let sounds = "soundsEnabled"
    static let autoAdvance = "autoAdvanceColors"
    /// Zen Mode: fly on to the next area after each fill (the painting screen's More menu).
    static let zenMode = "zenMode"
    static let paintingLength = "paintingLength"
    static let paperAppearance = "paperAppearance"
    /// The palette's lines (`PaletteRows`) and order (`PaletteOrder`), set from the painting
    /// screen's More › Palette.
    static let paletteRows = "paletteRows"
    static let paletteOrder = "paletteOrder"
    /// How heavy a coloring book's drawing is (`LineWeight`).
    nonisolated static let lineWeight = "lineWeight"
    /// What the create flow's preview shows beside the photo (`PreviewStyle`).
    nonisolated static let previewStyle = "previewStyle"
}

/// The preferences that code outside views reads (the create flow, a painting's session), with
/// their defaults; views bind the other keys with `@AppStorage`.
struct Preferences {
    /// Select the next unfinished color when one is completed.
    var autoAdvance: Bool
    /// How long a painting Suggested settings aim for in the create flow.
    var paintingLength: PaintingLength
    /// What the create flow's preview shows beside the photo.
    var previewStyle: PreviewStyle

    init(defaults: UserDefaults = .standard) {
        autoAdvance = defaults.object(forKey: SettingsKey.autoAdvance) as? Bool ?? true
        paintingLength = defaults.string(forKey: SettingsKey.paintingLength).flatMap(PaintingLength.init(rawValue:))
            ?? .default
        previewStyle = PreviewStyle.stored(in: defaults)
    }

    func apply(to session: PaintingSession) {
        session.autoAdvance = autoAdvance
    }

    /// Keys of settings the app no longer has: Settings › Advanced's line art, pipeline tuning,
    /// line appearance and preview picture, and its switch for each sound, haptic and flourish;
    /// Settings' paper size for printing and Color Names; the time-lapse's pace. Left in place,
    /// the first two would still shape new paintings, unseen.
    static let retiredKeys = [
        "advancedLineArt", "advancedPipelineTuning", "advancedLineAppearance", "advancedPreviewPicture",
        "printPaperSize", "colorNameStyle", "timelapsePace",
    ] + [
        "paintNotes", "colorJingle", "finishFanfare", "wrongColorSound", "fillHaptics", "wrongColorHaptics",
        "finishHaptics", "fillSparkles", "finishShine",
    ].map { "paintingEffect." + $0 }

    /// Where the retired Custom palette order kept each painting's arrangement, by its nickname
    /// seed.
    static let retiredCustomOrderPrefix = "paletteOrder.custom."

    /// Removes the retired settings (at launch; nothing is left to do once they are gone), first
    /// carrying Advanced's Line Weight over to Settings › Line Weight; the palette order Custom
    /// goes with the arrangements it read.
    static func removeRetiredSettings(in defaults: UserDefaults = .standard) {
        if defaults.object(forKey: SettingsKey.lineWeight) == nil,
           let data = defaults.data(forKey: "advancedLineAppearance"),
           let appearance = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let weight = appearance["coloringBookWeight"] as? Double {
            let carried = LineWeight.nearest(to: Float(weight))
            if carried != .default { defaults.set(carried.rawValue, forKey: SettingsKey.lineWeight) }
        }
        for key in retiredKeys { defaults.removeObject(forKey: key) }
        if defaults.string(forKey: SettingsKey.paletteOrder) == "custom" {
            defaults.removeObject(forKey: SettingsKey.paletteOrder)
        }
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(retiredCustomOrderPrefix) {
            defaults.removeObject(forKey: key)
        }
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
                              comment: "Choice of the Painting Length setting: suggested settings aim for about half an hour of painting")
        case .detailed: String(localized: "paintingLength.detailed", defaultValue: "Detailed",
                               comment: "Choice of the Painting Length setting: suggested settings aim for a long, detailed painting")
        }
    }

    /// The Settings footer under the picker: what the choice typically gives (`timeBand`: Quick
    /// 8–25 min, Relaxed 20–50, Detailed 40–120). Medians of large corpus photos under a Vision
    /// stand-in map: 16, 26 and 42 minutes (`docs/auto-tuning.md`, round two). A photo
    /// too small or too plain to fill Relaxed's or Detailed's band ends below it, at any setting.
    var footer: String {
        switch self {
        case .quick: String(localized: "settings.paintingLength.footer.quick",
                            defaultValue: "Suggested settings aim for about 15 minutes of painting.",
                            comment: "Footer under the Painting Length setting when Quick is chosen")
        case .relaxed: String(localized: "settings.paintingLength.footer.relaxed",
                              defaultValue: "Suggested settings aim for about half an hour of painting. Small or simple photos make shorter paintings.",
                              comment: "Footer under the Painting Length setting when Relaxed is chosen")
        case .detailed: String(localized: "settings.paintingLength.footer.detailed",
                               defaultValue: "Suggested settings aim for 45 minutes or more of painting. Small or simple photos make shorter paintings.",
                               comment: "Footer under the Painting Length setting when Detailed is chosen")
        }
    }
}
