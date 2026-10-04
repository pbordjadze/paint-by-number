/// How a template's lines are made (Settings › Advanced › Line Art).
///
/// `coloringBook`, the default, splits the paint regions along a drawing found by a learned
/// edge detector (the app's HED model, or an edge map handed to `pbn`) and is a coloring book:
/// the drawing alone is drawn, in full ink at every zoom, the paint boundaries inside an
/// outline are never lines (the areas inside it are told apart by their numbers, and by the
/// highlight of the selected color), the drawing stays over the paint (`TemplateLineArt.Style`)
/// and the paint is flatter (`SegmentationParameters.coloringBookFlattening`). `layered` splits
/// the regions along the same drawing so that every line still bounds a cell, and gives each
/// line a `LineLayer` by the strength of its edge: renderers draw outlines at full strength and
/// let fainter layers come in as the painter zooms. `classic` is the original look: every
/// region boundary is one even line. Everything here is generation input: changing it changes
/// the template. How the layers are drawn is the app's `LineAppearance`.
///
/// Each style has defaults of its own for the thresholds, line lengths and smoothing
/// (`init(style:)`, `changing(to:)`): the coloring book's are the settings the owner's own
/// books were made with, the layered ones the research's.
public struct LineArtSettings: Sendable, Hashable, Codable {
    public enum Style: String, Sendable, Codable, CaseIterable {
        case classic, layered, coloringBook

        /// Whether templates of this style are made from an edge map (and eyes): all but classic.
        public var usesEdgeMap: Bool { self != .classic }

        /// The line art a template of this style carries; nil for classic templates.
        public var templateStyle: TemplateLineArt.Style? {
            switch self {
            case .classic: nil
            case .layered: .layered
            case .coloringBook: .coloringBook
            }
        }
    }

    /// What happens where a drawn line runs between two cells of the same paint.
    public enum SamePaint: String, Sendable, Codable, CaseIterable {
        /// Every line splits: the two sides are separate cells with the same number.
        case split
        /// Cells separated only by texture lines are one cell; the line is still drawn inside it.
        /// A coloring book has no texture lines, so this splits like `split` there.
        case joinTexture
        /// Only outlines split same-paint cells; detail and texture lines are drawn inside cells.
        case joinAllButOutlines
    }

    public var style: Style
    /// Edge strength (0...1 of the detector's output) from which a line is an outline. A line
    /// keeps its layer along a stretch that stays above 60 % of the threshold once it has held
    /// the threshold for a few pixels. Where lines crowd (a shell's pattern, rock strata, a
    /// truss) the threshold rises toward 1, except for long contours, so busy texture stays
    /// detail. HED saturates near 1 on most contours, hence the high default.
    public var outlineThreshold: Float
    /// Edge strength from which a line is detail (stretches above half of it, once reached).
    public var detailThreshold: Float
    /// Edge strength from which a line is drawn at all, as texture (stretches above half of
    /// it, once reached); slightly lower on the subject, higher in the background. A coloring
    /// book draws nothing below `detailThreshold` and ignores it.
    public var textureThreshold: Float
    /// Lines shorter than this (canvas units) are dropped.
    public var minimumStrokeLength: Float
    /// Line ends closer than this (canvas units) are joined, closing small gaps; a free end
    /// also reaches this far (outlines 1.6×, detail 1.2×) for the nearest line, paint
    /// boundary or frame, so an open stroke still closes a cell.
    public var gapBridging: Float
    /// 0 = lines follow the edge map's pixels … 1 = smooth, flowing curves.
    public var lineSmoothing: Float
    public var samePaint: SamePaint
    /// Keep the boundaries where only the paint changes (banded skies, soft shading) as
    /// faint lines. Off merges cells whose paints are close, for calmer plans.
    public var keepColorEdges: Bool
    /// Draw detected eyes as outlines (their contours and irises), whatever their contrast;
    /// lines around an eye draw one layer stronger.
    public var outlineEyes: Bool

    /// A style at its defaults, any field given set instead. The coloring book's thresholds
    /// make each drawn line an outline (busy areas demote to detail, drawn alike in a book),
    /// its longer shortest line and gap closing drop specks and close cells, and its curves
    /// flow (measured in `docs/presets/README.md`). The layered defaults are the research's
    /// HED thresholds (`research/lineart/results_layers.md`), outlines a little higher and
    /// thinned where lines crowd, as the owner found the research's outlines too strong;
    /// texture lines join same-paint cells and color cells stay ("we want more colors").
    /// Classic lines read none of them and carry the layered values.
    public init(
        style: Style = .coloringBook,
        outlineThreshold: Float? = nil, detailThreshold: Float? = nil, textureThreshold: Float? = nil,
        minimumStrokeLength: Float? = nil, gapBridging: Float? = nil, lineSmoothing: Float? = nil,
        samePaint: SamePaint = .joinTexture, keepColorEdges: Bool = true, outlineEyes: Bool = true
    ) {
        let d = Self.numbers(for: style)
        self.style = style
        self.outlineThreshold = outlineThreshold ?? d.outline
        self.detailThreshold = detailThreshold ?? d.detail
        self.textureThreshold = textureThreshold ?? d.texture
        self.minimumStrokeLength = minimumStrokeLength ?? d.minimumStrokeLength
        self.gapBridging = gapBridging ?? d.gapBridging
        self.lineSmoothing = lineSmoothing ?? d.lineSmoothing
        self.samePaint = samePaint
        self.keepColorEdges = keepColorEdges
        self.outlineEyes = outlineEyes
    }

    /// A style's default thresholds, line lengths and smoothing.
    private struct Numbers {
        var outline: Float, detail: Float, texture: Float
        var minimumStrokeLength: Float, gapBridging: Float, lineSmoothing: Float
    }

    private static func numbers(for style: Style) -> Numbers {
        switch style {
        case .coloringBook:
            Numbers(outline: 0.6, detail: 0.6, texture: 0.3, minimumStrokeLength: 36, gapBridging: 16, lineSmoothing: 0.7)
        case .layered, .classic:
            Numbers(outline: 0.85, detail: 0.5, texture: 0.3, minimumStrokeLength: 18, gapBridging: 9, lineSmoothing: 0.5)
        }
    }

    /// These settings with `style`: every number still at this style's default moves to the
    /// new style's, a changed one stays. What choosing a style in Settings › Advanced does.
    public func changing(to style: Style) -> LineArtSettings {
        let old = LineArtSettings(style: self.style), new = LineArtSettings(style: style)
        var s = self
        s.style = style
        if outlineThreshold == old.outlineThreshold { s.outlineThreshold = new.outlineThreshold }
        if detailThreshold == old.detailThreshold { s.detailThreshold = new.detailThreshold }
        if textureThreshold == old.textureThreshold { s.textureThreshold = new.textureThreshold }
        if minimumStrokeLength == old.minimumStrokeLength { s.minimumStrokeLength = new.minimumStrokeLength }
        if gapBridging == old.gapBridging { s.gapBridging = new.gapBridging }
        if lineSmoothing == old.lineSmoothing { s.lineSmoothing = new.lineSmoothing }
        return s
    }

    /// Clamped copy: thresholds in 0...1 and ordered (texture ≤ detail ≤ outline).
    public var normalized: LineArtSettings {
        var s = self
        s.textureThreshold = min(max(textureThreshold, 0), 1)
        s.detailThreshold = min(max(detailThreshold, s.textureThreshold), 1)
        s.outlineThreshold = min(max(outlineThreshold, s.detailThreshold), 1)
        s.minimumStrokeLength = min(max(minimumStrokeLength, 0), 200)
        s.gapBridging = min(max(gapBridging, 0), 40)
        s.lineSmoothing = min(max(lineSmoothing, 0), 1)
        return s
    }

    private enum CodingKeys: String, CodingKey {
        case style, outlineThreshold, detailThreshold, textureThreshold, minimumStrokeLength, gapBridging,
             lineSmoothing, samePaint, keepColorEdges, outlineEyes
    }

    /// Tolerant: missing or unknown values fall back to the defaults (the decoded style's), so
    /// settings written by another build always decode.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        style = ((try? c.decodeIfPresent(Style.self, forKey: .style)) ?? nil) ?? LineArtSettings().style
        let d = LineArtSettings(style: style)
        outlineThreshold = (try? c.decodeIfPresent(Float.self, forKey: .outlineThreshold)) ?? d.outlineThreshold
        detailThreshold = (try? c.decodeIfPresent(Float.self, forKey: .detailThreshold)) ?? d.detailThreshold
        textureThreshold = (try? c.decodeIfPresent(Float.self, forKey: .textureThreshold)) ?? d.textureThreshold
        minimumStrokeLength = (try? c.decodeIfPresent(Float.self, forKey: .minimumStrokeLength)) ?? d.minimumStrokeLength
        gapBridging = (try? c.decodeIfPresent(Float.self, forKey: .gapBridging)) ?? d.gapBridging
        lineSmoothing = (try? c.decodeIfPresent(Float.self, forKey: .lineSmoothing)) ?? d.lineSmoothing
        samePaint = (try? c.decodeIfPresent(SamePaint.self, forKey: .samePaint)) ?? d.samePaint
        keepColorEdges = (try? c.decodeIfPresent(Bool.self, forKey: .keepColorEdges)) ?? d.keepColorEdges
        outlineEyes = (try? c.decodeIfPresent(Bool.self, forKey: .outlineEyes)) ?? d.outlineEyes
    }
}

/// Expert multipliers on the segmentation's derived knobs (Settings › Advanced › Pipeline).
/// Every field is a factor on what `GenerationSettings` derives (1 = unchanged), so the
/// default tuning reproduces the untuned pipeline exactly; `PipelineTuning.range` bounds them.
public struct PipelineTuning: Sendable, Hashable, Codable {
    /// How far the photo is smoothed before colors are picked: higher melts texture into flat areas.
    public var smoothing: Float
    /// How much texture (as opposed to structure) is smoothed across.
    public var textureFlattening: Float
    /// Smallest cell kept, as a factor on the derived minimum area: higher gives fewer, larger cells.
    public var minimumCellSize: Float
    /// How strongly the subject (faces, animals, the salient area) gets more colors and detail.
    public var subjectEmphasis: Float
    /// How eagerly small, distinctive colors win a paint of their own.
    public var accentColors: Float
    /// How much hue and colorfulness count against lightness when telling paints apart.
    public var colorfulness: Float

    public static let range: ClosedRange<Float> = 0.25...4

    public init(
        smoothing: Float = 1, textureFlattening: Float = 1, minimumCellSize: Float = 1,
        subjectEmphasis: Float = 1, accentColors: Float = 1, colorfulness: Float = 1
    ) {
        self.smoothing = smoothing
        self.textureFlattening = textureFlattening
        self.minimumCellSize = minimumCellSize
        self.subjectEmphasis = subjectEmphasis
        self.accentColors = accentColors
        self.colorfulness = colorfulness
    }

    public var isDefault: Bool { self == PipelineTuning() }

    /// Clamped copy.
    public var normalized: PipelineTuning {
        func c(_ x: Float) -> Float { x.isFinite ? min(max(x, Self.range.lowerBound), Self.range.upperBound) : 1 }
        return PipelineTuning(
            smoothing: c(smoothing), textureFlattening: c(textureFlattening), minimumCellSize: c(minimumCellSize),
            subjectEmphasis: c(subjectEmphasis), accentColors: c(accentColors), colorfulness: c(colorfulness))
    }

    private enum CodingKeys: String, CodingKey {
        case smoothing, textureFlattening, minimumCellSize, subjectEmphasis, accentColors, colorfulness
    }

    /// Tolerant, like `LineArtSettings`.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func f(_ key: CodingKeys) -> Float { ((try? c.decodeIfPresent(Float.self, forKey: key)) ?? nil) ?? 1 }
        self.init(
            smoothing: f(.smoothing), textureFlattening: f(.textureFlattening), minimumCellSize: f(.minimumCellSize),
            subjectEmphasis: f(.subjectEmphasis), accentColors: f(.accentColors), colorfulness: f(.colorfulness))
    }
}
