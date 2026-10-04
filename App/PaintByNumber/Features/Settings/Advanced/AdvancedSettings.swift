import Foundation
import PaintCore

/// What a preview of Settings › Advanced is generated with: the two groups of settings that
/// change templates, canonical, so that settings giving the same template share a key. Classic
/// line art ignores every other line art setting, so classic keys carry the classic defaults; a
/// coloring book ignores the texture threshold and has no texture lines to join across.
nonisolated struct GenerationKey: Hashable, Sendable {
    let lineArt: LineArtSettings
    let tuning: PipelineTuning

    init(lineArt: LineArtSettings, tuning: PipelineTuning) {
        var art = lineArt.normalized
        switch art.style {
        case .classic:
            art = LineArtSettings(style: .classic)
        case .coloringBook:
            art.textureThreshold = min(art.detailThreshold, LineArtSettings().textureThreshold)
            if art.samePaint == .joinTexture { art.samePaint = .split }
        case .layered:
            break
        }
        self.lineArt = art
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
    case style, detector
    case outlineThreshold, detailThreshold, textureThreshold
    case minimumStrokeLength, gapBridging, lineSmoothing
    case samePaint, keepColorEdges, outlineEyes, outlineObjects
    case smoothing, textureFlattening, minimumCellSize, subjectEmphasis, accentColors, colorfulness

    static let lineArt: [AdvancedControl] = [
        .style, .detector, .outlineThreshold, .detailThreshold, .textureThreshold, .minimumStrokeLength, .gapBridging,
        .lineSmoothing, .samePaint, .keepColorEdges, .outlineEyes, .outlineObjects,
    ]
    static let thresholds: [AdvancedControl] = [.outlineThreshold, .detailThreshold, .textureThreshold]
    static let pipeline: [AdvancedControl] = [
        .smoothing, .textureFlattening, .minimumCellSize, .subjectEmphasis, .accentColors, .colorfulness,
    ]

    /// Only line art drawn from an edge map (layered, coloring book) reads it.
    var needsEdgeMap: Bool { self != .style && Self.lineArt.contains(self) }

    /// Whether templates of `style` read the setting: classic reads only the style, and a
    /// coloring book draws nothing below detail, so it has no texture threshold.
    func applies(to style: LineArtSettings.Style) -> Bool {
        guard needsEdgeMap else { return true }
        guard style.usesEdgeMap else { return false }
        return !(style == .coloringBook && self == .textureThreshold)
    }

    /// Puts this setting back to its default in `art` and `tuning`: a line art setting to its
    /// style's own default, the style to the default style, carrying each style's defaults
    /// (`LineArtSettings.changing(to:)`).
    func reset(_ art: inout LineArtSettings, _ tuning: inout PipelineTuning) {
        let a = LineArtSettings(style: art.style), t = PipelineTuning()
        switch self {
        case .style: art = art.changing(to: LineArtSettings().style)
        case .detector: art.detector = a.detector
        case .outlineThreshold: art.outlineThreshold = a.outlineThreshold
        case .detailThreshold: art.detailThreshold = a.detailThreshold
        case .textureThreshold: art.textureThreshold = a.textureThreshold
        case .minimumStrokeLength: art.minimumStrokeLength = a.minimumStrokeLength
        case .gapBridging: art.gapBridging = a.gapBridging
        case .lineSmoothing: art.lineSmoothing = a.lineSmoothing
        case .samePaint: art.samePaint = a.samePaint
        case .keepColorEdges: art.keepColorEdges = a.keepColorEdges
        case .outlineEyes: art.outlineEyes = a.outlineEyes
        case .outlineObjects: art.outlineObjects = a.outlineObjects
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
        case .style: Double(LineArtSettings.Style.allCases.firstIndex(of: art.style) ?? 0)
        case .detector: Double(LineArtSettings.Detector.allCases.firstIndex(of: art.detector) ?? 0)
        case .outlineThreshold: Double(art.outlineThreshold)
        case .detailThreshold: Double(art.detailThreshold)
        case .textureThreshold: Double(art.textureThreshold)
        case .minimumStrokeLength: Double(art.minimumStrokeLength)
        case .gapBridging: Double(art.gapBridging)
        case .lineSmoothing: Double(art.lineSmoothing)
        case .samePaint: Double(LineArtSettings.SamePaint.allCases.firstIndex(of: art.samePaint) ?? 0)
        case .keepColorEdges: art.keepColorEdges ? 1 : 0
        case .outlineEyes: art.outlineEyes ? 1 : 0
        case .outlineObjects: art.outlineObjects ? 1 : 0
        case .smoothing: Double(tuning.smoothing)
        case .textureFlattening: Double(tuning.textureFlattening)
        case .minimumCellSize: Double(tuning.minimumCellSize)
        case .subjectEmphasis: Double(tuning.subjectEmphasis)
        case .accentColors: Double(tuning.accentColors)
        case .colorfulness: Double(tuning.colorfulness)
        }
    }

    /// The default as a number (see `value(lineArt:tuning:)`) under `style`, whose own defaults
    /// the line art settings have; the style's default is the default style.
    func defaultValue(for style: LineArtSettings.Style) -> Double {
        value(lineArt: LineArtSettings(style: self == .style ? LineArtSettings().style : style), tuning: PipelineTuning())
    }

    /// How a slider shows the setting under `style` (its default is the style's); nil for
    /// choices and switches.
    func slider(for style: LineArtSettings.Style) -> SliderSpec? {
        let defaultValue = defaultValue(for: style)
        return switch self {
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
        case .style, .detector, .samePaint, .keepColorEdges, .outlineEyes, .outlineObjects:
            nil
        }
    }

    /// The value as the screen shows it: "60%", "8 px", "1.5×", "Layered", "On".
    func valueText(lineArt art: LineArtSettings, tuning: PipelineTuning) -> String {
        switch self {
        case .style: art.style.name
        case .detector: art.detector.name
        case .samePaint: art.samePaint.name(in: art.style)
        case .keepColorEdges: AdvancedText.onOff(art.keepColorEdges)
        case .outlineEyes: AdvancedText.onOff(art.outlineEyes)
        case .outlineObjects: AdvancedText.onOff(art.outlineObjects)
        default: slider(for: art.style)?.text(value(lineArt: art, tuning: tuning)) ?? ""
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
