import Foundation

/// How many colors and areas a template has, worded for the create flow's summary and the
/// printable template's header and color key.
nonisolated enum TemplateCounts {
    static func colors(_ count: Int) -> String {
        String(localized: "template.colors", defaultValue: "\(count) colors", bundle: .era,
               comment: "How many colors a template has; the argument is the count")
    }

    static func areas(_ count: Int) -> String {
        String(localized: "template.areas", defaultValue: "\(count) areas", bundle: .era,
               comment: "How many areas (regions to paint) a template has; the argument is the count")
    }

    /// "21 of 24 colors": a template that kept fewer paints than the Colors slider asked for,
    /// the rest unused, so the slider and the summary under it don't seem to disagree.
    static func colors(_ count: Int, of asked: Int) -> String {
        String(localized: "template.colorsOf", defaultValue: "\(count) of \(asked) colors", bundle: .era,
               comment: "How many colors a template kept of the number the Colors slider asked for, the rest unused; the arguments are the kept count and the asked count, e.g. 21 of 24 colors")
    }

    /// "24 colors · 1,284 areas · ~1.5 h": the create flow's summary (`asked`: the Colors slider's
    /// count, said only when the template kept fewer).
    static func summary(colors: Int, asked: Int? = nil, areas: Int, seconds: TimeInterval) -> String {
        let colorsText = if let asked, asked > colors { Self.colors(colors, of: asked) } else { Self.colors(colors) }
        let areasText = Self.areas(areas)
        let timeText = PaintingTimeText.approximate(seconds)
        return String(localized: "create.stats.summary", defaultValue: "\(colorsText) · \(areasText) · \(timeText)", bundle: .era,
                      comment: "Template summary under the create sliders; the arguments are the colors, areas and estimated painting time, e.g. 24 colors · 1,284 areas · ~1.5 h")
    }
}
