import Foundation
import PaintCore

/// What a preview of Settings › Advanced is generated with: the two groups of settings that
/// change templates, canonical, so that settings giving the same template share a key. Classic
/// line art ignores every other line art setting, so classic keys carry the default ones.
nonisolated struct GenerationKey: Hashable, Sendable {
    let lineArt: LineArtSettings
    let tuning: PipelineTuning

    init(lineArt: LineArtSettings, tuning: PipelineTuning) {
        let art = lineArt.normalized
        self.lineArt = art.style == .classic ? LineArtSettings() : art
        self.tuning = tuning.normalized
    }

    static let defaults = GenerationKey(lineArt: LineArtSettings(), tuning: PipelineTuning())

    /// `base` (the picture's suggested settings) with this key's line art and tuning.
    func settings(on base: GenerationSettings) -> GenerationSettings {
        var settings = base
        settings.lineArt = lineArt
        settings.tuning = tuning
        return settings
    }
}

/// A setting of Settings › Advanced that changes templates. Each one shows its effect: the
/// preview's numbers against the same settings with this one back at its default.
nonisolated enum AdvancedControl: String, CaseIterable, Sendable {
    case style
    case outlineThreshold, detailThreshold, textureThreshold
    case minimumStrokeLength, gapBridging, lineSmoothing
    case samePaint, keepColorEdges, outlineEyes
    case smoothing, textureFlattening, minimumCellSize, subjectEmphasis, accentColors, colorfulness

    static let lineArt: [AdvancedControl] = [
        .style, .outlineThreshold, .detailThreshold, .textureThreshold, .minimumStrokeLength, .gapBridging,
        .lineSmoothing, .samePaint, .keepColorEdges, .outlineEyes,
    ]
    static let thresholds: [AdvancedControl] = [.outlineThreshold, .detailThreshold, .textureThreshold]
    static let pipeline: [AdvancedControl] = [
        .smoothing, .textureFlattening, .minimumCellSize, .subjectEmphasis, .accentColors, .colorfulness,
    ]

    /// Only layered line art reads it.
    var isLayeredOnly: Bool { self != .style && Self.lineArt.contains(self) }

    /// Puts this setting back to its default in `art` and `tuning`.
    func reset(_ art: inout LineArtSettings, _ tuning: inout PipelineTuning) {
        let a = LineArtSettings(), t = PipelineTuning()
        switch self {
        case .style: art.style = a.style
        case .outlineThreshold: art.outlineThreshold = a.outlineThreshold
        case .detailThreshold: art.detailThreshold = a.detailThreshold
        case .textureThreshold: art.textureThreshold = a.textureThreshold
        case .minimumStrokeLength: art.minimumStrokeLength = a.minimumStrokeLength
        case .gapBridging: art.gapBridging = a.gapBridging
        case .lineSmoothing: art.lineSmoothing = a.lineSmoothing
        case .samePaint: art.samePaint = a.samePaint
        case .keepColorEdges: art.keepColorEdges = a.keepColorEdges
        case .outlineEyes: art.outlineEyes = a.outlineEyes
        case .smoothing: tuning.smoothing = t.smoothing
        case .textureFlattening: tuning.textureFlattening = t.textureFlattening
        case .minimumCellSize: tuning.minimumCellSize = t.minimumCellSize
        case .subjectEmphasis: tuning.subjectEmphasis = t.subjectEmphasis
        case .accentColors: tuning.accentColors = t.accentColors
        case .colorfulness: tuning.colorfulness = t.colorfulness
        }
    }

    /// `key` with this setting at its default: what its effect is measured against.
    func reset(_ key: GenerationKey) -> GenerationKey {
        var art = key.lineArt, tuning = key.tuning
        reset(&art, &tuning)
        return GenerationKey(lineArt: art, tuning: tuning)
    }

    /// Whether the setting changes the template `key` describes (a layered-only setting never
    /// does under classic line art).
    func isChanged(in key: GenerationKey) -> Bool { reset(key) != key }

    /// The setting as a number: choices by their position, switches 0 or 1.
    func value(lineArt art: LineArtSettings, tuning: PipelineTuning) -> Double {
        switch self {
        case .style: art.style == .layered ? 1 : 0
        case .outlineThreshold: Double(art.outlineThreshold)
        case .detailThreshold: Double(art.detailThreshold)
        case .textureThreshold: Double(art.textureThreshold)
        case .minimumStrokeLength: Double(art.minimumStrokeLength)
        case .gapBridging: Double(art.gapBridging)
        case .lineSmoothing: Double(art.lineSmoothing)
        case .samePaint: Double(LineArtSettings.SamePaint.allCases.firstIndex(of: art.samePaint) ?? 0)
        case .keepColorEdges: art.keepColorEdges ? 1 : 0
        case .outlineEyes: art.outlineEyes ? 1 : 0
        case .smoothing: Double(tuning.smoothing)
        case .textureFlattening: Double(tuning.textureFlattening)
        case .minimumCellSize: Double(tuning.minimumCellSize)
        case .subjectEmphasis: Double(tuning.subjectEmphasis)
        case .accentColors: Double(tuning.accentColors)
        case .colorfulness: Double(tuning.colorfulness)
        }
    }

    /// The default as a number (see `value(lineArt:tuning:)`).
    var defaultValue: Double { value(lineArt: LineArtSettings(), tuning: PipelineTuning()) }

    /// How a slider shows the setting; nil for choices and switches.
    var slider: SliderSpec? {
        switch self {
        case .outlineThreshold, .detailThreshold, .textureThreshold:
            SliderSpec(range: 0.02...0.98, defaultValue: defaultValue, quantum: 0.01, accessibilityStep: 0.05, format: .percent)
        case .minimumStrokeLength:
            SliderSpec(range: 0...60, defaultValue: defaultValue, quantum: 1, accessibilityStep: 1, format: .pixels)
        case .gapBridging:
            SliderSpec(range: 0...20, defaultValue: defaultValue, quantum: 1, accessibilityStep: 1, format: .pixels)
        case .lineSmoothing:
            SliderSpec(range: 0...1, defaultValue: defaultValue, quantum: 0.01, accessibilityStep: 0.05, format: .percent)
        case .smoothing, .textureFlattening, .minimumCellSize, .subjectEmphasis, .accentColors, .colorfulness:
            SliderSpec(
                range: Double(PipelineTuning.range.lowerBound)...Double(PipelineTuning.range.upperBound),
                defaultValue: defaultValue, logarithmic: true, quantum: 0.01, accessibilityStep: 0.25, format: .multiplier)
        case .style, .samePaint, .keepColorEdges, .outlineEyes:
            nil
        }
    }

    /// The value as the screen shows it: "60%", "8 px", "1.5×", "Layered", "On".
    func valueText(lineArt art: LineArtSettings, tuning: PipelineTuning) -> String {
        switch self {
        case .style: art.style.name
        case .samePaint: art.samePaint.name
        case .keepColorEdges: AdvancedText.onOff(art.keepColorEdges)
        case .outlineEyes: AdvancedText.onOff(art.outlineEyes)
        default: slider?.text(value(lineArt: art, tuning: tuning)) ?? ""
        }
    }
}

/// A slider of Settings › Advanced: its range (linear, or on a log₂ scale for multipliers), the
/// rounding of its values, the step one VoiceOver adjustment moves, and how values read. The
/// track works in positions 0…1; values near the default snap to it.
nonisolated struct SliderSpec: Sendable {
    enum Format: Sendable {
        case percent, pixels, multiplier
    }

    let range: ClosedRange<Double>
    let defaultValue: Double
    var logarithmic = false
    /// Values are rounded to multiples of this.
    let quantum: Double
    /// One VoiceOver adjustment: in value units, or in log₂ units on a logarithmic slider.
    let accessibilityStep: Double
    let format: Format

    /// Within this fraction of the track the default catches the thumb.
    static let detent = 0.02

    private func scaled(_ value: Double) -> Double { logarithmic ? log2(max(value, 1e-6)) : value }
    private func unscaled(_ value: Double) -> Double { logarithmic ? exp2(value) : value }

    func position(of value: Double) -> Double {
        let lo = scaled(range.lowerBound), hi = scaled(range.upperBound)
        guard hi > lo else { return 0 }
        return min(max((scaled(value) - lo) / (hi - lo), 0), 1)
    }

    /// The value at a track position: rounded to `quantum`, the default when it is that close.
    func value(at position: Double) -> Double {
        let p = min(max(position, 0), 1)
        if abs(p - self.position(of: defaultValue)) < Self.detent { return defaultValue }
        let lo = scaled(range.lowerBound), hi = scaled(range.upperBound)
        return clamped((unscaled(lo + (hi - lo) * p) / quantum).rounded() * quantum)
    }

    /// `value` moved by `steps` VoiceOver adjustments, which land on multiples of the step
    /// (on a logarithmic slider, of the step in log₂ units: 1×, 1.19×, 1.41×, 1.68×, 2×), so
    /// rounding never makes them drift.
    func value(_ value: Double, adjustedBy steps: Int) -> Double {
        let index = (scaled(value) / accessibilityStep).rounded() + Double(steps)
        return clamped((unscaled(index * accessibilityStep) / quantum).rounded() * quantum)
    }

    private func clamped(_ value: Double) -> Double { min(max(value, range.lowerBound), range.upperBound) }

    func text(_ value: Double) -> String {
        switch format {
        case .percent: value.formatted(.percent.precision(.fractionLength(0)))
        case .pixels: AdvancedText.pixels(Int(value.rounded()))
        case .multiplier: AdvancedText.multiplier(value)
        }
    }
}

/// A preview's numbers, estimated for the full painting: the draft's counts grown by the ratio
/// Suggested settings use to estimate a full template from a draft (`AutoScore.estimatedSeconds`).
nonisolated struct AdvancedStats: Equatable, Sendable {
    var areas: Int
    var colors: Int
    /// Lines of each `LineLayer` (outline, detail, texture, color); nil for classic templates.
    var lines: [Int]?

    var seconds: TimeInterval { PaintingTime.estimate(regionCount: areas) }

    init(areas: Int, colors: Int, lines: [Int]? = nil) {
        self.areas = areas
        self.colors = colors
        self.lines = lines
    }

    /// `areaScale`: full-painting areas per draft area.
    init(_ template: Template, areaScale: Double) {
        func scaled(_ count: Int) -> Int { max(0, Int((Double(count) * areaScale).rounded())) }
        areas = scaled(template.regions.count)
        colors = template.palette.count
        lines = template.lineArt.map { art in
            var counts = [Int](repeating: 0, count: LineLayer.allCases.count)
            for layer in art.edgeLayers where Int(layer) < counts.count { counts[Int(layer)] += 1 }
            for stroke in art.strokes where Int(stroke.layer) < counts.count { counts[Int(stroke.layer)] += 1 }
            return counts.map(scaled)
        }
    }

    /// Drawn lines (every layer but color edges); nil for classic templates.
    var drawnLines: Int? { lines.map { $0.dropLast().reduce(0, +) } }

    struct Delta: Equatable, Sendable {
        var areas: Int
        var colors: Int
        /// Nil unless both sides are layered.
        var lines: Int?

        var seconds: TimeInterval { PaintingTime.estimate(regionCount: areas) }
        var isZero: Bool { areas == 0 && colors == 0 && (lines ?? 0) == 0 }
    }

    func delta(from other: AdvancedStats) -> Delta {
        var lines: Int?
        if let mine = drawnLines, let theirs = other.drawnLines { lines = mine - theirs }
        return Delta(areas: areas - other.areas, colors: colors - other.colors, lines: lines)
    }
}

/// Quick starting points for Line Appearance: how the four layers' opacity and width change
/// with zoom. Presets leave `weighted` and what stays when painted alone.
nonisolated enum LineAppearancePreset: String, CaseIterable, Identifiable, Sendable {
    /// The owner's pick: fainter layers fade in by opacity, at even weight.
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

/// The text Copy Settings and Share with a Note hand over: what the painter saw (picture,
/// numbers, every setting that differs from its default, their note) and the settings as JSON,
/// which reproduce the preview exactly for a library picture (generation is deterministic).
/// Paste Settings reads the same text back (`settings(in:)`), so settings travel between
/// devices, and a preset is any text written like it (`docs/presets/`).
nonisolated enum AdvancedReport {
    /// The settings a pasted text holds: each group the text has, clamped to its range.
    struct Imported: Equatable, Sendable {
        var lineArt: LineArtSettings?
        var tuning: PipelineTuning?
        var lineAppearance: LineAppearance?

        var isEmpty: Bool { lineArt == nil && tuning == nil && lineAppearance == nil }
    }

    /// The settings in `text`: the JSON object in it that holds any of the three groups, read
    /// the way stored settings are (fields a build doesn't know fall back to their defaults),
    /// clamped. Nil when there is none. Objects are tried from each `{` to the last `}`, so a
    /// note before the JSON may hold braces.
    static func settings(in text: String) -> Imported? {
        guard let close = text.lastIndex(of: "}") else { return nil }
        var start = text.startIndex
        while let open = text[start..<close].firstIndex(of: "{") {
            if let groups = try? JSONDecoder().decode(Groups.self, from: Data(text[open...close].utf8)) {
                let imported = Imported(
                    lineArt: groups.lineArt?.normalized, tuning: groups.tuning?.normalized,
                    lineAppearance: groups.lineAppearance?.normalized)
                return imported.isEmpty ? nil : imported
            }
            start = text.index(after: open)
        }
        return nil
    }

    /// The three groups of the snapshot, each optional and read leniently: a group that is not
    /// an object counts as absent.
    private struct Groups: Decodable {
        var lineArt: LineArtSettings?
        var tuning: PipelineTuning?
        var lineAppearance: LineAppearance?

        private enum CodingKeys: String, CodingKey { case lineArt, tuning, lineAppearance }

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            lineArt = try? c.decodeIfPresent(LineArtSettings.self, forKey: .lineArt)
            tuning = try? c.decodeIfPresent(PipelineTuning.self, forKey: .tuning)
            lineAppearance = try? c.decodeIfPresent(LineAppearance.self, forKey: .lineAppearance)
        }
    }

    struct Snapshot: Codable, Equatable, Sendable {
        struct Numbers: Codable, Equatable, Sendable {
            var areas: Int
            var colors: Int
            var minutes: Int

            init(_ stats: AdvancedStats) {
                areas = stats.areas
                colors = stats.colors
                minutes = Int((stats.seconds / 60).rounded())
            }
        }

        var app: String
        /// The library picture's id, or "photo" for the painter's own.
        var picture: String
        var paintingLength: String
        var lineArt: LineArtSettings
        var tuning: PipelineTuning
        var lineAppearance: LineAppearance
        var preview: Numbers?
        var defaults: Numbers?
    }

    static func json(_ snapshot: Snapshot) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(snapshot) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    /// - Parameters:
    ///   - changes: The settings that differ from their defaults, already worded.
    ///   - summary: The preview's numbers, already worded; nil before there is a preview.
    static func text(snapshot: Snapshot, pictureTitle: String, summary: String?, changes: [String], note: String) -> String {
        let app = snapshot.app
        var lines = [
            String(localized: "advanced.report.title", defaultValue: "Paint by Moonlight \(app): Advanced settings",
                   comment: "First line of the settings text Settings › Advanced copies or shares for feedback; the argument is the app version, e.g. 1.0.42 (42)"),
            String(localized: "advanced.report.picture", defaultValue: "Picture: \(pictureTitle)",
                   comment: "Line of the shared Advanced settings text: the picture the preview showed; the argument is its title"),
        ]
        if let summary {
            lines.append(String(localized: "advanced.report.preview", defaultValue: "Preview: \(summary)",
                                comment: "Line of the shared Advanced settings text: the preview's numbers; the argument is e.g. 24 colors · 1,284 areas · ~1 h, +212 areas from the defaults"))
        }
        if changes.isEmpty {
            lines.append(String(localized: "advanced.report.allDefault", defaultValue: "Every setting is at its default.",
                                comment: "Line of the shared Advanced settings text when nothing was changed"))
        } else {
            let list = changes.formatted(.list(type: .and))
            lines.append(String(localized: "advanced.report.changes", defaultValue: "Changed: \(list)",
                                comment: "Line of the shared Advanced settings text listing the changed settings; the argument is a list such as Line Style Layered and Smallest Area 2×"))
        }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            lines.append("")
            lines.append(trimmed)
        }
        lines.append("")
        lines.append(json(snapshot))
        return lines.joined(separator: "\n")
    }
}
