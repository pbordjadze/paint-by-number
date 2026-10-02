/// How a template's lines are made (Settings › Advanced › Line Art).
///
/// `classic` is the original look: every region boundary is one even line. `layered` splits
/// the regions along a drawing found by a learned edge detector (the app's HED model, or an
/// edge map handed to `pbn`), so every line still bounds a cell, and gives each line a
/// `LineLayer` by the strength of its edge: renderers draw outlines at full strength and let
/// fainter layers come in as the painter zooms. Everything here is generation input: changing
/// it changes the template. How the layers are drawn is the app's `LineAppearance`.
public struct LineArtSettings: Sendable, Hashable, Codable {
    public enum Style: String, Sendable, Codable, CaseIterable {
        case classic, layered
    }

    /// What happens where a drawn line runs between two cells of the same paint.
    public enum SamePaint: String, Sendable, Codable, CaseIterable {
        /// Every line splits: the two sides are separate cells with the same number.
        case split
        /// Cells separated only by texture lines are one cell; the line is still drawn inside it.
        case joinTexture
        /// Only outlines split same-paint cells; detail and texture lines are drawn inside cells.
        case joinAllButOutlines
    }

    public var style: Style
    /// Edge strength (0...1 of the detector's output) from which a line is an outline.
    public var outlineThreshold: Float
    /// Edge strength from which a line is detail.
    public var detailThreshold: Float
    /// Edge strength from which a line is drawn at all (as texture).
    public var textureThreshold: Float
    /// Lines shorter than this (canvas units) are dropped.
    public var minimumStrokeLength: Float
    /// Line ends closer than this (canvas units) are joined, closing small gaps.
    public var gapBridging: Float
    /// 0 = lines follow the edge map's pixels … 1 = smooth, flowing curves.
    public var lineSmoothing: Float
    public var samePaint: SamePaint
    /// Keep the boundaries where only the paint changes (banded skies, soft shading) as
    /// faint lines. Off merges cells whose paints are close, for calmer plans.
    public var keepColorEdges: Bool
    /// Draw detected eyes as outlines (their contours and irises), whatever their contrast.
    public var outlineEyes: Bool

    public init(
        style: Style = .classic,
        outlineThreshold: Float = 0.8, detailThreshold: Float = 0.5, textureThreshold: Float = 0.3,
        minimumStrokeLength: Float = 18, gapBridging: Float = 9, lineSmoothing: Float = 0.5,
        samePaint: SamePaint = .joinTexture, keepColorEdges: Bool = true, outlineEyes: Bool = true
    ) {
        self.style = style
        self.outlineThreshold = outlineThreshold
        self.detailThreshold = detailThreshold
        self.textureThreshold = textureThreshold
        self.minimumStrokeLength = minimumStrokeLength
        self.gapBridging = gapBridging
        self.lineSmoothing = lineSmoothing
        self.samePaint = samePaint
        self.keepColorEdges = keepColorEdges
        self.outlineEyes = outlineEyes
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

    /// Tolerant: missing or unknown values fall back to the defaults, so settings written by
    /// another build always decode.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = LineArtSettings()
        style = (try? c.decodeIfPresent(Style.self, forKey: .style)) ?? d.style
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
