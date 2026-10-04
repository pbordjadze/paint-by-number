/// Features of a photo (`AutoSettings.analyze`). The candidate rule (`AutoSettings.center`)
/// reads the palette curve, chromatic fraction, chroma spread, structure density, texture
/// fraction, noise, subject coverage, mean importance and face coverage; the rest (the source
/// size, smooth fraction, importance entropy, animal coverage) are diagnostics for `pbn
/// suggest` and the tuning sheets. Every value is quantized (to 3 decimals; the palette curve
/// and noise, whose small differences the rule reads, to 4), so floating-point differences
/// between devices cannot flip a decision.
public struct PhotoAnalysis: Sendable, Codable, Hashable {
    public var sourceWidth, sourceHeight: Int
    /// Weighted mean ΔE a k-paint palette reaches, for k in `paletteCurveKs` (8…64).
    public var paletteCurve: [Float]
    /// Pixels with chroma > 0.04 (less below lightness 0.5).
    public var chromaticFraction: Float
    /// Standard deviation of chroma.
    public var chromaSpread: Float
    /// Busy pixels whose gradient is coherent (contours).
    public var structureDensity: Float
    /// Busy but incoherent pixels.
    public var textureFraction: Float
    /// Pixels inside gentle ramps (sky, skin, bokeh).
    public var smoothFraction: Float
    /// High-frequency energy in flat areas.
    public var noise: Float
    /// Pixels with importance > 0.6.
    public var subjectCoverage: Float
    /// 0 = one hotspot … 1 = flat (the share of the frame the importance covers).
    public var importanceEntropy: Float
    /// Mean importance weight: how much of the frame the map protects.
    public var meanImportance: Float
    /// Area of the hints' faces inside the frame, 0 without hints.
    public var faceCoverage: Float
    /// Area of the hints' animals inside the frame, 0 without hints.
    public var animalCoverage: Float
}

/// One setting tried for a photo.
public struct AutoCandidate: Sendable, Codable {
    public var settings: GenerationSettings
    /// nil until run.
    public var score: AutoScore?

    public init(settings: GenerationSettings, score: AutoScore? = nil) {
        self.settings = settings
        self.score = score
    }
}

/// How one candidate's template measures against its photo (`AutoSettings.score`).
public struct AutoScore: Sendable, Codable, Hashable {
    /// Importance-weighted mean ΔE.
    public var fidelity: Float
    public var fidelityP95: Float
    public var regions: Int
    /// Regions under `AutoSettings.tinyRadius`.
    public var tinyRegions: Int
    /// Regions bounded mostly by weak boundaries (`BandRings`).
    public var bandRings: Int
    public var minLabelRoom: Float
    public var estimatedSeconds: Double
    /// The share of `total` paid for an estimated painting time outside the preference's
    /// `timeBand` (0 inside it), kept so the decision explains itself.
    public var bandPenalty: Float
    /// Lower is better.
    public var total: Float
}

/// The outcome of `AutoSettings.choose`: reproducible from the photo, its importance and
/// hints, the preference, the line art and tuning and the candidate count, so it is never
/// stored.
public struct AutoDecision: Sendable, Codable {
    public var analysis: PhotoAnalysis
    public var preference: PaintingLength
    /// In evaluation order, scores filled in.
    public var candidates: [AutoCandidate]
    /// Index into `candidates`.
    public var winner: Int
    public var settings: GenerationSettings { candidates[winner].settings }
}
