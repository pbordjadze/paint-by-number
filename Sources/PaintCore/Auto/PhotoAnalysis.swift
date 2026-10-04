import Foundation

/// A rectangle in normalized image coordinates (0…1, top-left origin), as Vision reports
/// faces and animals once flipped.
public struct NormalizedRect: Sendable, Codable, Hashable {
    public var x: Float
    public var y: Float
    public var width: Float
    public var height: Float

    public init(x: Float, y: Float, width: Float, height: Float) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    /// Area of the part inside the unit square.
    var clippedArea: Float {
        let w = min(x + width, 1) - max(x, 0), h = min(y + height, 1) - max(y, 0)
        return w > 0 && h > 0 ? w * h : 0
    }
}

/// What the device knows about a photo's subject beyond pixels (Vision on Apple platforms;
/// empty, or hand-written for tooling, elsewhere).
public struct SubjectHints: Sendable, Codable, Hashable {
    /// Normalized rects (0…1, top-left origin) of detected human faces and animals.
    public var faces: [NormalizedRect]
    public var animals: [NormalizedRect]

    public init(faces: [NormalizedRect] = [], animals: [NormalizedRect] = []) {
        self.faces = faces
        self.animals = animals
    }

    /// Missing lists decode as empty: hand-written hints for tooling name only what a photo has.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        faces = try c.decodeIfPresent([NormalizedRect].self, forKey: .faces) ?? []
        animals = try c.decodeIfPresent([NormalizedRect].self, forKey: .animals) ?? []
    }
}

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

/// The one preference Auto needs: how long a painting the user wants (Settings › Painting
/// Length). It sets the bands the suggested settings stay inside and the painting time the
/// scoring aims for.
public enum PaintingLength: String, Sendable, Codable, CaseIterable {
    case quick, relaxed, detailed

    /// Colors a suggestion may use.
    public var colorBand: ClosedRange<Int> {
        switch self {
        case .quick: 6...24
        case .relaxed: 8...40
        case .detailed: 12...72
        }
    }

    /// The detail a suggestion starts from before the photo moves it. Detailed sits at 0.8:
    /// at 0.7 the median large corpus photo's full template (about 950 areas, 48 minutes) sat
    /// at the bottom of its band.
    public var detailCenter: Float {
        switch self {
        case .quick: 0.3
        case .relaxed: 0.5
        case .detailed: 0.8
        }
    }

    /// Detail a suggestion may use: the center ± 0.35 (room for the photo's own adjustments
    /// and the neighbours tried around them).
    public var detailBand: ClosedRange<Float> {
        max(0, detailCenter - 0.35)...min(1, detailCenter + 0.35)
    }

    /// Painting time (seconds, `PaintingTime.estimate`) the scoring aims for; outside it a
    /// candidate pays `AutoScore.bandPenalty`. Calibrated on what the app generates: a
    /// 12 MP photo is kept at 2048 px and segmented at 1100 + 1000 × detail px, where the
    /// corpus's 35 large photos give a median of about 380 areas (19 minutes) at detail 0.3,
    /// 680 (34) at 0.5 and 1350 (67) at 0.9, a busy one two to three times that; a 768-px
    /// sample reaches 300–950 areas at any detail. The bands overlap so that a photo which
    /// cannot fill one still lands near it. Those counts come from `pbn` with the pipeline's
    /// fallback importance map; Vision maps rate background texture lower and give about half
    /// as many areas at like settings, which the detail center and the region model follow
    /// through the map's mean importance (`AutoSettings.detailPerImportance`,
    /// `regionAreaExponent`). Under a Vision stand-in map the median large corpus photo's
    /// suggestion runs 16, 26 and 42 minutes for Quick, Relaxed and Detailed.
    public var timeBand: ClosedRange<Double> {
        switch self {
        case .quick: (8 * 60)...(25 * 60)
        case .relaxed: (20 * 60)...(50 * 60)
        case .detailed: (40 * 60)...(120 * 60)
        }
    }
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
