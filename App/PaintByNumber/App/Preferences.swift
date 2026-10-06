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
    static let paperSize = "printPaperSize"
    static let timelapsePace = "timelapsePace"
    static let paperAppearance = "paperAppearance"
    static let colorNames = "colorNameStyle"
    /// The palette's lines (`PaletteRows`) and order (`PaletteOrder`).
    static let paletteRows = "paletteRows"
    static let paletteOrder = "paletteOrder"
    /// Settings › Advanced (JSON data): line art and pipeline tuning for new paintings, and
    /// how layered lines are drawn.
    static let lineArt = "advancedLineArt"
    static let pipelineTuning = "advancedPipelineTuning"
    nonisolated static let lineAppearance = "advancedLineAppearance"
    /// The picture Settings › Advanced previews (`AdvancedSettingsModel.Picture.storageValue`).
    static let advancedPreviewPicture = "advancedPreviewPicture"
}

/// The preferences that code outside views reads (the create flow, Settings › Advanced, a
/// painting's session), with their defaults; views bind the other keys with `@AppStorage`.
struct Preferences {
    /// Select the next unfinished color when one is completed.
    var autoAdvance: Bool
    /// How long a painting Suggested settings aim for in the create flow.
    var paintingLength: PaintingLength
    /// Whether paints go by playful nicknames or their plain structured names.
    var colorNames: ColorNameStyle
    /// Line art new paintings are generated with (Settings › Advanced).
    var lineArt: LineArtSettings
    /// Expert pipeline multipliers new paintings are generated with (Settings › Advanced).
    var tuning: PipelineTuning
    /// How layered lines are drawn at each zoom (Settings › Advanced).
    var lineAppearance: LineAppearance

    init(defaults: UserDefaults = .standard) {
        autoAdvance = defaults.object(forKey: SettingsKey.autoAdvance) as? Bool ?? true
        paintingLength = defaults.string(forKey: SettingsKey.paintingLength).flatMap(PaintingLength.init(rawValue:))
            ?? .default
        colorNames = defaults.string(forKey: SettingsKey.colorNames).flatMap(ColorNameStyle.init(rawValue:)) ?? .default
        lineArt = Self.decoded(LineArtSettings.self, defaults, SettingsKey.lineArt) ?? LineArtSettings()
        tuning = Self.decoded(PipelineTuning.self, defaults, SettingsKey.pipelineTuning) ?? PipelineTuning()
        lineAppearance = LineAppearance.stored(in: defaults)
    }

    /// A JSON-encoded setting, or nil when absent or unreadable (the caller's default applies).
    private static func decoded<T: Decodable>(_ type: T.Type, _ defaults: UserDefaults, _ key: String) -> T? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }

    /// Stores a JSON-encoded setting (Settings › Advanced writes its three groups this way).
    static func store<T: Encodable>(_ value: T, forKey key: String, in defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) }
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
