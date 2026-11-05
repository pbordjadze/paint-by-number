import Foundation
import PaintCore

/// UserDefaults keys of user preferences (views bind them with `@AppStorage`).
enum SettingsKey {
    static let haptics = "hapticsEnabled"
    static let sounds = "soundsEnabled"
    /// Settings › Music's Sun, Moon or Auto (`SkySetting`): which sounds play, and whether the
    /// fill's sparkles are stars.
    nonisolated static let sky = "sky"
    static let autoAdvance = "autoAdvanceColors"
    /// Zen Mode: fly on to the next area after each fill (the painting screen's More menu).
    static let zenMode = "zenMode"
    static let paperAppearance = "paperAppearance"
    /// The palette's lines (`PaletteRows`) and order (`PaletteOrder`), set from the painting
    /// screen's More › Palette.
    static let paletteRows = "paletteRows"
    static let paletteOrder = "paletteOrder"
    /// How heavy a coloring book's drawing is (`LineWeight`).
    nonisolated static let lineWeight = "lineWeight"
    /// Start Painting first plays the making-of show (`MakingOfView`): the mosaic set step by step,
    /// each technique named (Settings › The Making-of; on by default in Ravenna).
    static let playsMakingOf = "playsMakingOf"
    /// The create flow's preview shows its settings: its Adjust was opened, and stays so
    /// (`TemplatePreviewView.foldsSettings`).
    static let previewShowsSettings = "previewShowsSettings"
    /// Whether the app gives small tips as the painter goes (Settings › Tips). On for everyone
    /// until they switch it off there: unset means on (`TipPreference`).
    nonisolated static let tipsEnabled = "tipsEnabled"
}

/// What each switch of `SettingsKey` is until the painter sets it, written once: the `@AppStorage`
/// declarations and the code reading `UserDefaults` itself start from these. The keys whose
/// values are a type of their own keep their default on it (`SkySetting.default`,
/// `PaperAppearance.default`, `LineWeight.default`, `PaletteRows.default`, `PaletteOrder.default`).
nonisolated enum SettingsDefault {
    static let haptics = true
    static let sounds = true
    static let autoAdvance = true
    static let zenMode = false
    /// Ravenna's seam: Paul's decision (issue #13), the making-of is on by default.
    static let playsMakingOf = true
    static let previewShowsSettings = false
    static let tipsEnabled = true
}

/// The preferences that code outside views reads (the create flow), with their defaults; views
/// bind the other keys with `@AppStorage` (a painting's session takes its settings from
/// `PaintView`, whoever presents it).
struct Preferences {
    /// Start Painting plays the making-of show first.
    var playsMakingOf: Bool

    init(defaults: UserDefaults = .ravenna) {
        // `bool(forKey:)` reads a launch argument's `YES` too.
        playsMakingOf = defaults.object(forKey: SettingsKey.playsMakingOf) == nil
            ? SettingsDefault.playsMakingOf : defaults.bool(forKey: SettingsKey.playsMakingOf)
    }
}
