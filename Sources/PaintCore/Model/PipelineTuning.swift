/// Expert multipliers on the segmentation's derived knobs (`pbn --tuning`).
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
