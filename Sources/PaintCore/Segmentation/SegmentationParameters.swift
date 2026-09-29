import Foundation

/// Internal knobs of the segmentation pipeline, derived from the user-facing settings and
/// the canvas size. Spatial quantities scale with the canvas so a template's look depends
/// on `detail`, not on the photo's resolution.
struct SegmentationParameters: Sendable {
    var colorCount: Int
    var seed: UInt64
    /// The pipeline works in OKLab with the chroma axes stretched by this factor, so paints
    /// separate hue/colorfulness (skin vs. warm grey) a little more eagerly than lightness.
    var chromaScale: Float

    /// Domain-transform smoothing: spatial sigma (canvas units), range sigma (OKLab).
    var smoothSpatial: Float
    var smoothRange: Float
    var smoothIterations: Int

    /// Exponent applied to palette histogram bin weights (< 1 lets small, distinct colors
    /// compete with large flat areas).
    var histogramGamma: Float
    /// Independent palette searches; the best one wins.
    var paletteRestarts: Int
    /// Extra palette weight for colors that stand out from their surroundings.
    var paletteSaliency: Float
    /// Palette colors closer than this (OKLab) are merged.
    var minPaletteDistance: Float

    /// Contrast-sensitive Potts prior for pixel labelling (squared OKLab units).
    var potts: Float
    var pottsEdgeSigma: Float
    var icmIterations: Int

    /// Minimum region area (canvas units²) at neutral importance.
    var minArea: Float
    /// Minimum largest-inscribed-disc radius (as measured by `interiorDistance`).
    var minRadius: Float
    /// Every region pixel must lie in a disc (dx² + dy² ≤ this) inside its region.
    var openingRadiusSquared: Int
    /// Strength of importance on the area threshold: area × 2^(strength × (0.5 − importance)).
    var importanceStrength: Float
    /// Domain stretch in important areas (1 + this × importance), i.e. gentler smoothing.
    var importanceSharpening: Float
    /// Minimum-area growth in textured, unimportant areas (see `areaScale`).
    var textureStrength: Float
    /// Merge target preference for long shared borders (OKLab-distance equivalent).
    var mergeShareWeight: Float
    /// Region-level k-means passes when refitting the palette.
    var refineIterations: Int

    init(settings: GenerationSettings, width: Int, height: Int) {
        let s = settings.normalized
        let d = s.detail, sm = s.smoothness
        let area = Float(width * height)
        let side = area.squareRoot()

        colorCount = s.colorCount
        seed = s.seed
        chromaScale = Tune.f("CHROMA", 1.6)

        smoothSpatial = side * Tune.f("SS", 0.008) * lerp(1.4, 0.7, d) * lerp(0.7, 1.3, sm)
        smoothRange = Tune.f("SR", 0.06) * lerp(0.7, 1.4, sm)
        smoothIterations = 3

        histogramGamma = Tune.f("GAMMA", 0.6)
        minPaletteDistance = Tune.f("MINPAL", 0.04)
        paletteSaliency = Tune.f("SAL", 1)
        paletteRestarts = Int(Tune.f("RESTARTS", 3))

        potts = Tune.f("POTTS", 0.0012) * lerp(0.5, 1.6, sm)
        pottsEdgeSigma = Tune.f("PSIG", 0.05)
        icmIterations = Int(Tune.f("ICM", 3))

        // Log-interpolated fraction of the canvas: detail 0 → 1/1500, 1 → 1/20000.
        let fraction = exp(lerp(log(1 / Tune.f("AMIN0", 3000)), log(1 / Tune.f("AMIN1", 60000)), d))
        minArea = max(area * fraction, 12)
        minRadius = lerp(Tune.f("R0", 3.5), Tune.f("R1", 2), min(1, 2 * d))
        openingRadiusSquared = Int(Tune.f("OPEN", d < 0.25 ? 4 : 1))
        importanceStrength = Tune.f("IMPS", 3)
        mergeShareWeight = Tune.f("SHARE", 0.04)
        textureStrength = Tune.f("TEX", 4)
        importanceSharpening = Tune.f("ISHARP", 1)
        refineIterations = Int(Tune.f("REFINE", 3))
    }

    /// Per-pixel multiplier of `minArea`: important areas keep smaller regions; busy
    /// texture (dense label changes, `texture` 0...1) outside important areas needs larger
    /// ones, so knit, foliage or gravel become a few paintable shapes rather than crumbs.
    @inline(__always)
    func areaScale(importance: Float, texture: Float) -> Float {
        exp2(importanceStrength * (0.5 - importance)) * (1 + textureStrength * (1 - importance) * texture)
    }
}

@inline(__always)
func lerp(_ a: Float, _ b: Float, _ t: Float) -> Float { a + (b - a) * t }

/// Development-time overrides (PBN_<NAME> environment variables).
enum Tune {
    static let environment = ProcessInfo.processInfo.environment
    static let debug = environment["PBN_DEBUG"] != nil
    static func f(_ name: String, _ fallback: Float) -> Float {
        environment["PBN_" + name].flatMap(Float.init) ?? fallback
    }
}

func debugLog(_ s: String) {
    FileHandle.standardError.write(Data((s + "\n").utf8))
}
