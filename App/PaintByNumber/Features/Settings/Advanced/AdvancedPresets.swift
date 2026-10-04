import PaintCore

/// Quick starting points for Line Appearance: how the four layers' opacity and width change
/// with zoom. Presets leave `weighted`, what stays when painted and the coloring book's weight
/// alone.
nonisolated enum LineAppearancePreset: String, CaseIterable, Identifiable, Sendable {
    /// Fainter layers fade in by opacity, at even weight: the default look.
    case fade
    /// Fainter layers start thin and grow as the painter zooms.
    case grow
    /// Every line alike at every zoom, like a classic template.
    case even

    var id: String { rawValue }

    var layers: [LineAppearance.Layer] {
        switch self {
        case .fade:
            LineLayer.allCases.map { LineAppearance.default[$0] }
        case .grow:
            [
                LineAppearance.Layer(opacity: [0.85, 0.9, 0.95], width: [1, 1.15, 1.3]),
                LineAppearance.Layer(opacity: [0.7, 0.75, 0.8], width: [0.45, 0.75, 1]),
                LineAppearance.Layer(opacity: [0.55, 0.6, 0.7], width: [0.3, 0.55, 0.85]),
                LineAppearance.Layer(opacity: [0.3, 0.35, 0.45], width: [0.25, 0.45, 0.7]),
            ]
        case .even:
            LineLayer.allCases.map { _ in LineAppearance.Layer(opacity: [1, 1, 1], width: [1, 1, 1]) }
        }
    }

    /// `appearance` with this preset's opacities and widths.
    func applied(to appearance: LineAppearance) -> LineAppearance {
        var result = appearance
        for (layer, values) in zip(LineLayer.allCases, layers) {
            result[layer].opacity = values.opacity
            result[layer].width = values.width
        }
        return result
    }

    /// The preset whose opacities and widths `appearance` has, if any.
    static func matching(_ appearance: LineAppearance) -> LineAppearancePreset? {
        allCases.first { preset in
            zip(LineLayer.allCases, preset.layers).allSatisfy {
                appearance[$0].opacity == $1.opacity && appearance[$0].width == $1.width
            }
        }
    }
}

/// Quick starting points for the whole screen (Settings › Advanced › Presets): a line style at
/// its own defaults, the pipeline untuned and the lines drawn as designed. The coloring book is
/// the app's defaults (`LineArtSettings()`), so Coloring Book is Reset All.
nonisolated enum AdvancedPreset: String, CaseIterable, Identifiable, Sendable {
    case coloringBook, layered, classic

    var id: String { rawValue }

    /// The app's defaults.
    static let defaults = AdvancedPreset.coloringBook

    var style: LineArtSettings.Style {
        switch self {
        case .coloringBook: .coloringBook
        case .layered: .layered
        case .classic: .classic
        }
    }

    /// Every group the preset sets.
    var settings: AdvancedReport.Imported {
        AdvancedReport.Imported(lineArt: LineArtSettings(style: style), tuning: PipelineTuning(), lineAppearance: .default)
    }

    /// The preset whose settings these are, as generation uses them (`GenerationKey`: a setting
    /// the style ignores, like a coloring book's texture threshold, doesn't count) and as the
    /// lines are drawn.
    static func matching(lineArt: LineArtSettings, tuning: PipelineTuning, appearance: LineAppearance) -> AdvancedPreset? {
        let key = GenerationKey(lineArt: lineArt, tuning: tuning)
        return allCases.first { preset in
            let s = preset.settings
            guard let art = s.lineArt, let tune = s.tuning else { return false }
            return GenerationKey(lineArt: art, tuning: tune) == key && s.lineAppearance == appearance.normalized
        }
    }
}
