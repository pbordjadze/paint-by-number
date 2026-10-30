/// User-facing knobs for template generation. Everything else is derived.
public struct GenerationSettings: Sendable, Hashable, Codable {
    /// Number of paint colors (palette size upper bound; near-duplicates are merged).
    public var colorCount: Int
    /// 0 = bold, few large regions … 1 = intricate, many small regions.
    public var detail: Float
    /// 0 = crisp, faithful boundaries … 1 = soft, flowing, painterly boundaries.
    public var smoothness: Float
    /// Seed for any stochastic step, so identical inputs give identical templates.
    public var seed: UInt64
    /// Coloring-book or classic lines, and how drawn lines are found.
    public var lineArt: LineArtSettings
    /// Expert multipliers on the segmentation's derived knobs (default: none).
    public var tuning: PipelineTuning
    /// Set, the template is made from a drawing (`DrawingSettings`: the photo is a line drawing
    /// on paper whose lines bound the areas, and the paints come from a palette set), not from
    /// a photo's colors. Nil, the default and every photo's, leaves the photo path as it is.
    public var drawing: DrawingSettings?

    public init(
        colorCount: Int = 24, detail: Float = 0.5, smoothness: Float = 0.5, seed: UInt64 = 0x5eed,
        lineArt: LineArtSettings = LineArtSettings(), tuning: PipelineTuning = PipelineTuning(),
        drawing: DrawingSettings? = nil
    ) {
        self.colorCount = colorCount
        self.detail = detail
        self.smoothness = smoothness
        self.seed = seed
        self.lineArt = lineArt
        self.tuning = tuning
        self.drawing = drawing
    }

    private enum CodingKeys: String, CodingKey {
        case colorCount, detail, smoothness, seed, lineArt, tuning, drawing
    }

    /// The four original fields are required as before; the later ones default, so settings
    /// saved before they existed (every artwork's `meta.json`) still decode: such an artwork
    /// was made with classic lines, whatever the default is now, so regeneration keeps them.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        colorCount = try c.decode(Int.self, forKey: .colorCount)
        detail = try c.decode(Float.self, forKey: .detail)
        smoothness = try c.decode(Float.self, forKey: .smoothness)
        seed = try c.decode(UInt64.self, forKey: .seed)
        lineArt = ((try? c.decodeIfPresent(LineArtSettings.self, forKey: .lineArt)) ?? nil) ?? LineArtSettings(style: .classic)
        tuning = (try? c.decodeIfPresent(PipelineTuning.self, forKey: .tuning)) ?? PipelineTuning()
        // A drawing's settings a later app wrote in a way this one can't read still mark the
        // painting as one from a drawing, at this app's defaults.
        if c.contains(.drawing) {
            drawing = (try? c.decodeIfPresent(DrawingSettings.self, forKey: .drawing)) ?? DrawingSettings()
        } else {
            drawing = nil
        }
    }

    public static let colorCountRange = 6...150

    /// The closest (OKLab distance) two paints of a template may be: segmentation pushes apart
    /// or merges nearer ones. Public so tools can check the guarantee against the pipeline's
    /// own number. Large palettes pack paints closer, or a photo's gamut couldn't hold that
    /// many distinct paints — down to one just-noticeable difference (`SegmentationParameters.jnd`)
    /// and never below: paints a painter can't tell apart would be one paint with two numbers.
    public var minPaletteDistance: Float {
        max(SegmentationParameters.jnd, 0.04 * min(1, (24 / Float(normalized.colorCount)).squareRoot()))
    }

    /// Clamped copy.
    public var normalized: GenerationSettings {
        var s = self
        s.colorCount = min(max(colorCount, Self.colorCountRange.lowerBound), Self.colorCountRange.upperBound)
        // NaN passes through `min` and `max` and would trap in `workingLongSide`.
        s.detail = detail.isFinite ? min(max(detail, 0), 1) : GenerationSettings().detail
        s.smoothness = smoothness.isFinite ? min(max(smoothness, 0), 1) : GenerationSettings().smoothness
        s.lineArt = lineArt.normalized
        s.tuning = tuning.normalized
        s.drawing = drawing?.normalized
        return s
    }

    /// Long side, in pixels, of the working image the template is segmented at. Also the
    /// canvas size in units.
    public var workingLongSide: Int {
        Int((1100 + 1000 * normalized.detail).rounded())
    }

    /// Working size for a source of the given dimensions (never upscales beyond 1.5×).
    public func workingSize(sourceWidth: Int, sourceHeight: Int) -> (width: Int, height: Int) {
        let long = max(sourceWidth, sourceHeight)
        let target = min(workingLongSide, Int(Double(long) * 1.5))
        let scale = Double(target) / Double(long)
        return (
            max(1, Int((Double(sourceWidth) * scale).rounded())),
            max(1, Int((Double(sourceHeight) * scale).rounded()))
        )
    }
}
