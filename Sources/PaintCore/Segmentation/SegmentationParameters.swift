import Foundation

/// Internal knobs of the segmentation pipeline, derived from the user-facing settings and
/// the canvas size. Spatial quantities scale with the canvas so a template's look depends
/// on `detail`, not on the photo's resolution.
struct SegmentationParameters: Sendable {
    var colorCount: Int
    var seed: UInt64
    /// The pipeline works in OKLab with the chroma axes stretched by this factor, so paints
    /// separate hue/colorfulness (skin vs. warm grey, a grey-blue iris) a little more
    /// eagerly than lightness.
    var chromaScale: Float

    /// Domain-transform smoothing: spatial sigma (canvas units), range sigma (OKLab).
    var smoothSpatial: Float
    var smoothRange: Float
    var smoothIterations: Int
    /// How much texture (as opposed to structure, see `StructureMap`) is smoothed across.
    var textureFlattening: Float
    var structureRadius: Int
    var structureExponent: Float
    /// Domain stretch in important areas (1 + this × importance), i.e. gentler smoothing.
    var importanceSharpening: Float

    /// Exponent applied to palette histogram bin weights (< 1 lets small, distinct colors
    /// compete with large flat areas).
    var histogramGamma: Float
    /// Independent palette searches; the best one wins.
    var paletteRestarts: Int
    /// Extra palette weight for colors that stand out from their surroundings.
    var paletteSaliency: Float
    /// Paints closer than this (OKLab) are pushed apart or merged.
    var minPaletteDistance: Float
    /// Region-level k-means passes when refitting the palette.
    var refineIterations: Int

    /// Contrast-sensitive Potts prior for pixel labelling (squared OKLab units).
    var potts: Float
    var pottsEdgeSigma: Float
    var icmIterations: Int

    /// Minimum region area (canvas units²) at neutral importance, before `areaScale`.
    var minArea: Float
    /// Minimum largest-inscribed-disc radius (as measured by `interiorDistance`).
    var minRadius: Float
    /// Every region pixel must lie in a disc (dx² + dy² ≤ this) inside its region.
    var openingRadiusSquared: Int
    /// Strength of importance on the area threshold (see `areaScale`).
    var importanceStrength: Float
    /// Minimum-area growth in textured, unimportant areas (see `areaScale`).
    var textureStrength: Float
    /// Merge target preference for long shared borders (OKLab-distance equivalent).
    var mergeShareWeight: Float
    /// Mode-filter smoothing of region outlines (see `BoundarySmoothing`).
    var boundaryRadius: Int
    var boundaryPasses: Int
    var boundaryFidelity: Float
    /// Paint difference (OKLab) up to which neighbours merge in fully textured, unimportant
    /// areas (scaled down by texture density and importance).
    var consolidationTolerance: Float

    init(settings: GenerationSettings, width: Int, height: Int) {
        let s = settings.normalized
        let d = s.detail, sm = s.smoothness
        let area = Float(width * height)
        let side = area.squareRoot()

        colorCount = s.colorCount
        seed = s.seed
        chromaScale = 1.6

        smoothSpatial = side * 0.008 * lerp(1.4, 0.7, d) * lerp(0.7, 1.3, sm)
        smoothRange = 0.06 * lerp(0.7, 1.4, sm)
        smoothIterations = 3
        textureFlattening = lerp(0.6, 1, sm)
        structureRadius = max(1, Int((side * 0.0025).rounded()))
        structureExponent = 3
        importanceSharpening = 1

        histogramGamma = 0.6
        paletteRestarts = 3
        paletteSaliency = 1
        // Large palettes pack paints closer (down to about twice a just-noticeable difference),
        // or a photo's gamut couldn't hold that many distinct paints.
        minPaletteDistance = 0.04 * min(1, (24 / Float(s.colorCount)).squareRoot())
        refineIterations = 3

        potts = 0.0012 * lerp(0.5, 1.6, sm)
        pottsEdgeSigma = 0.05
        icmIterations = 3

        // Log-interpolated fraction of the canvas: detail 0 → 1/3000, 1 → 1/60000.
        minArea = max(area * exp(lerp(log(1 / 3000), log(1 / 60000), d)), 12)
        // interiorDistance is quantized (2.5, 2.74, 3.33, 3.5, …). 2.74 asks for a 5-px spot
        // with some diagonal extent, so the vectorizer's smoothed polygon still holds a
        // radius-2 disc; 3.5 asks for a 7-px spot.
        minRadius = lerp(3.5, 2.7, min(1, 2 * d))
        // Bold templates also require every part to be ~5 px wide; otherwise 3 px (cross).
        openingRadiusSquared = d < 0.25 ? 4 : 1
        importanceStrength = 3
        textureStrength = 4
        mergeShareWeight = 0.04
        boundaryRadius = sm > 0.66 ? 3 : 2
        boundaryPasses = Int((3 * sm).rounded())
        boundaryFidelity = 40
        consolidationTolerance = 0.1 * lerp(1.4, 0.7, d)
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
