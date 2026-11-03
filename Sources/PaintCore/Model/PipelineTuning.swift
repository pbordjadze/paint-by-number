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
    /// Smallest cell kept on the subject's body (fur, hair, clothes: importance between the
    /// background's and a face's), as a factor on what importance makes it there. Higher
    /// gives the subject fewer, larger cells, as a kit paints it, while the face (importance
    /// near 1: eyes, a glint) and the background keep theirs
    /// (`SegmentationParameters.subjectBody`).
    public var subjectCellSize: Float

    public static let range: ClosedRange<Float> = 0.25...4

    public init(
        smoothing: Float = 1, textureFlattening: Float = 1, minimumCellSize: Float = 1,
        subjectEmphasis: Float = 1, accentColors: Float = 1, colorfulness: Float = 1, subjectCellSize: Float = 1
    ) {
        self.smoothing = smoothing
        self.textureFlattening = textureFlattening
        self.minimumCellSize = minimumCellSize
        self.subjectEmphasis = subjectEmphasis
        self.accentColors = accentColors
        self.colorfulness = colorfulness
        self.subjectCellSize = subjectCellSize
    }

    public var isDefault: Bool { self == PipelineTuning() }

    /// Clamped copy.
    public var normalized: PipelineTuning {
        func c(_ x: Float) -> Float { x.isFinite ? min(max(x, Self.range.lowerBound), Self.range.upperBound) : 1 }
        return PipelineTuning(
            smoothing: c(smoothing), textureFlattening: c(textureFlattening), minimumCellSize: c(minimumCellSize),
            subjectEmphasis: c(subjectEmphasis), accentColors: c(accentColors), colorfulness: c(colorfulness),
            subjectCellSize: c(subjectCellSize))
    }

    private enum CodingKeys: String, CodingKey {
        case smoothing, textureFlattening, minimumCellSize, subjectEmphasis, accentColors, colorfulness, subjectCellSize
    }

    /// The original six always; a later factor only when it isn't 1, so settings without it
    /// (every painting's `meta.json` and every `.moonlight` file before it) encode as they did.
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(smoothing, forKey: .smoothing)
        try c.encode(textureFlattening, forKey: .textureFlattening)
        try c.encode(minimumCellSize, forKey: .minimumCellSize)
        try c.encode(subjectEmphasis, forKey: .subjectEmphasis)
        try c.encode(accentColors, forKey: .accentColors)
        try c.encode(colorfulness, forKey: .colorfulness)
        if subjectCellSize != 1 { try c.encode(subjectCellSize, forKey: .subjectCellSize) }
    }

    /// Tolerant, like `LineArtSettings`.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func f(_ key: CodingKeys) -> Float { ((try? c.decodeIfPresent(Float.self, forKey: key)) ?? nil) ?? 1 }
        self.init(
            smoothing: f(.smoothing), textureFlattening: f(.textureFlattening), minimumCellSize: f(.minimumCellSize),
            subjectEmphasis: f(.subjectEmphasis), accentColors: f(.accentColors), colorfulness: f(.colorfulness),
            subjectCellSize: f(.subjectCellSize))
    }
}
