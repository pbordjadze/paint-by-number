import Foundation

/// Internal knobs of the segmentation pipeline, derived from the user-facing settings and
/// the canvas size. Spatial quantities scale with the canvas so a template's look depends
/// on `detail`, not on the photo's resolution.
struct SegmentationParameters: Sendable {
    /// A just-noticeable color difference in OKLab (see `ColorScience`): the floor of
    /// `minPaletteDistance`.
    static let jnd: Float = 0.02
    /// How far below its raster minimum (`minRadius(digits:)`) a smoothed polygon's label
    /// room may fall before the vectorizer steps that region's edges toward the pixel
    /// outline (see `EdgeSmoother.run`). `LabelSizing.minimumRadius` needs at least 0.8;
    /// 0.9 touches under 0.1 % of regions on photos, with no visible faceting.
    static let vectorRadiusTolerance: Float = 0.9
    /// Furthest a region too thin for its number may be recoloured to a paint with a shorter
    /// number (`RegionSimplifier.enforceLabelRoom`). Measured in the working space (chroma
    /// stretched by `chromaScale`), like the merge costs it competes with, so it allows two
    /// JNDs of lightness but only about 1.25 of hue or colourfulness, the more visible
    /// change. Beyond that the new paint reads as a different colour (dark slats on a blue
    /// shutter turning brown), and merging into a neighbour looks better.
    static let labelRecolorLimit: Float = 2 * jnd
    /// A coloring book's paint is flatter: the areas inside an outline are told apart only by
    /// their numbers, so small color cells cost more than they show. Its smoothing, texture
    /// flattening and smallest area are this many times the classic ones
    /// (`flattenForColoringBook`): fewer cells on the ten pictures the book's defaults were
    /// measured on (`docs/coloring-book.md`, Defaults); the Pipeline factors multiply that.
    static let coloringBookFlattening: Float = 1.5
    /// The palette size past which `BandMerging` fuses less. Its tolerances are fixed OKLab
    /// spreads (two or more just-noticeable differences), while a larger palette's paints sit
    /// closer (`GenerationSettings.minPaletteDistance`: 0.031 at 40 paints, one just-noticeable
    /// difference from 96), so each further paint was fused back into its neighbours' bands and
    /// extra Colors only recolored the same cells. Past the knee the tolerances shrink as
    /// knee / colors, so the extra paints stay areas of their own. 40 is the most paints
    /// Relaxed suggests (`PaintingLength.colorBand`): its suggestions and every setting up to
    /// 40 colors are unchanged; Detailed's (up to 72) are not.
    static let bandFusionKnee: Float = 40

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
    /// Paints closer than this (OKLab) are pushed apart or merged; never below `jnd`.
    var minPaletteDistance: Float
    /// Region-level k-means passes when refitting the palette.
    var refineIterations: Int

    /// Contrast-sensitive Potts prior for pixel labelling (squared OKLab units).
    var potts: Float
    var pottsEdgeSigma: Float
    var icmIterations: Int

    /// Minimum region area (canvas units²) at neutral importance, before `areaScale`.
    var minArea: Float
    /// Minimum largest-inscribed-disc radius (as measured by `interiorDistance`) of a region
    /// with a 1-digit number; see `minRadius(digits:)`.
    var minRadius: Float
    /// Every region pixel must lie in a disc (dx² + dy² ≤ this) inside its region. Unlike
    /// `minRadius(digits:)` this does not grow with the number's digits: it keeps tendrils
    /// wide enough to paint, while the number sits at the region's widest spot, so a wider
    /// opening for long numbers would only erase detail.
    var openingRadiusSquared: Int
    /// Strength of importance on the area threshold (see `areaScale`).
    var importanceStrength: Float
    /// Minimum-area growth in textured, unimportant areas (see `areaScale`).
    var textureStrength: Float
    /// `PipelineTuning.subjectCellSize`: the factor `areaScale` gives the subject's body.
    var subjectCellSize: Float
    /// `PipelineTuning.faceCellSize`, and the eyes it sizes faces by (`faceCells`: centre x, y
    /// and width in canvas units; empty unless the factor is above 1 and eyes were found).
    var faceCellSize: Float
    var faceCells: [SIMD3<Float>] = []
    /// Merge target preference for long shared borders (OKLab-distance equivalent).
    var mergeShareWeight: Float
    /// A small region whose mean colour lies within this distance (working OKLab) of a
    /// neighbouring paint is nearly invisible against it, so it counts only a fraction of
    /// its area, down to `crumbFloor` at no contrast: low-contrast crumbs (the leftovers of
    /// fine feather or fur texture) need several times the area a distinct spot such as an
    /// eye needs to survive.
    var crumbContrast: Float
    var crumbFloor: Float
    /// Transition strips (see `RegionSimplifier.mergeRound`), the blur of an edge labelled
    /// with a third paint: a region is one when its compactness (16 × area / perimeter², 1
    /// for a square) is below `stripCompactness`, its mean width (2 × area / perimeter) below
    /// `stripWidth`, its mean colour lies within `stripMixture` × its distance to the nearer
    /// of its two dominant neighbours' paints of the line between those paints, and the mean
    /// colour step across each of those two borders is below `stripContrast` × the paint
    /// difference (an edge blurred over 4+ pixels; a sharp contour steps by the whole
    /// difference within a pixel or two). Both dominant neighbours must be open areas: one
    /// that shares `stripEnclosure` or more of its whole outline (image edge included) with
    /// the region is wrapped by it, and one smaller than `stripNeighbourArea` × the region's
    /// area is the inside of a rim or a ring nest (a pupil inside its iris, an iris inside
    /// its eye ring); rings are features, not blur.
    var stripCompactness: Float
    var stripWidth: Float
    var stripMixture: Float
    var stripContrast: Float
    var stripEnclosure: Float
    var stripNeighbourArea: Float
    /// Gradient bands (see `BandMerging`): the largest spread (OKLab) of paints fused into
    /// one region across weak boundaries in unimportant areas, for paints too close to tell
    /// apart (anywhere) and for narrow bands, both falling to `bandNearImportantTolerance`
    /// at importance 1; the mean width up to which a region is a narrow band; and the
    /// fraction of the paint difference the colour step across a boundary must stay under
    /// to count as a ramp rather than a contour.
    var bandNearTolerance: Float
    var bandNearImportantTolerance: Float
    var bandTolerance: Float
    var bandWidth: Float
    var bandContrast: Float
    /// Mode-filter smoothing of region outlines (see `BoundarySmoothing`).
    var boundaryRadius: Int
    var boundaryPasses: Int
    var boundaryFidelity: Float
    /// Paint difference (OKLab) up to which neighbours merge in fully textured, unimportant
    /// areas (scaled down by texture density and importance).
    var consolidationTolerance: Float

    /// `GenerationSettings.tuning` multiplies the knobs it names (`PipelineTuning`); a factor
    /// of exactly 1 leaves every value bit for bit as derived. The line style changes nothing
    /// here: a coloring book's flatter paint is `flattenForColoringBook`, which the generator
    /// applies, so analysis (`PhotoAnalyzer`) and classic templates never see it.
    init(settings: GenerationSettings, width: Int, height: Int) {
        let s = settings.normalized
        let d = s.detail, sm = s.smoothness
        let t = s.tuning
        let area = Float(width * height)
        let side = area.squareRoot()

        colorCount = s.colorCount
        seed = s.seed
        chromaScale = 1.6 * t.colorfulness

        smoothSpatial = side * 0.008 * lerp(1.4, 0.7, d) * lerp(0.7, 1.3, sm) * t.smoothing
        smoothRange = 0.06 * lerp(0.7, 1.4, sm)
        smoothIterations = 3
        textureFlattening = lerp(0.6, 1, sm) * t.textureFlattening
        structureRadius = max(1, Int((side * 0.0025).rounded()))
        structureExponent = 3
        importanceSharpening = 1 * t.subjectEmphasis

        histogramGamma = 0.6
        paletteRestarts = 3
        paletteSaliency = 1 * t.accentColors
        minPaletteDistance = s.minPaletteDistance
        refineIterations = 3

        potts = 0.0012 * lerp(0.5, 1.6, sm)
        pottsEdgeSigma = 0.05
        icmIterations = 3

        // Log-interpolated fraction of the canvas: detail 0 → 1/3000, 1 → 1/60000.
        minArea = max(area * exp(lerp(log(1 / 3000), log(1 / 60000), d)), 12) * t.minimumCellSize
        // interiorDistance is quantized (2.5, 2.74, 3.33, 3.5, …). 2.74 asks for a 5-px spot
        // with some diagonal extent, so the vectorizer's polygon still holds a label disc of
        // `LabelSizing.minimumRadius`; 3.5 asks for a 7-px spot.
        minRadius = lerp(3.5, 2.7, min(1, 2 * d))
        // Bold templates also require every part to be ~5 px wide; otherwise 3 px (cross).
        openingRadiusSquared = d < 0.25 ? 4 : 1
        importanceStrength = 3 * t.subjectEmphasis
        textureStrength = 4
        subjectCellSize = t.subjectCellSize
        faceCellSize = t.faceCellSize
        mergeShareWeight = 0.04
        // Full weight from about six just-noticeable differences; at no contrast a crumb needs
        // five times the area (a small eye or highlight against skin stays, feather and fur
        // leftovers go).
        crumbContrast = 0.12
        crumbFloor = 0.2
        // Aspect ratio above ~10 (a rectangle's compactness is 4·L·w/(L + w)²) and a mean
        // width under three minimum radii (about one and a half number-holding discs across);
        // the mean colour may stray from the mixing line by 40% of its distance to the nearer
        // paint (blur mixes are rarely exact), and a border whose pixel step reaches 70% of the
        // paint difference is a contour, not a ramp.
        stripCompactness = 0.35
        stripWidth = 3 * minRadius
        stripMixture = 0.4
        stripContrast = 0.7
        // A pupil cut by the eyelid still shares well over half its outline with the iris.
        // The rings of the Parrots eye at 24 colours (a 68-px pupil inside a 183-px inner
        // iris, a 249-px iris, a 342-px eye ring) are each smaller than the ring around them,
        // while the blurred-edge strips along a beak run between regions many times
        // their size.
        stripEnclosure = 0.6
        stripNeighbourArea = 1
        // Paints about two just-noticeable differences apart (below a large palette's
        // spacing) fuse anywhere in the background, and the rings of a background ramp up to
        // clearly different shades; on the subject only paints about one apart, since its
        // modelling is worth its regions and its colour error is the one people see. Bold
        // templates fuse more gradation than fine ones, so the detail slider keeps its
        // meaning. Bokeh rings are a few percent of the frame wide, a sky band far more.
        let fineShades = min(1, Self.bandFusionKnee / Float(s.colorCount))
        bandNearTolerance = 0.045 * lerp(1.3, 0.8, d) * fineShades
        bandNearImportantTolerance = 0.5 * bandNearTolerance
        bandTolerance = 0.1 * lerp(1.4, 0.7, d) * fineShades
        bandWidth = side * 0.02
        bandContrast = 0.25
        boundaryRadius = sm > 0.66 ? 3 : 2
        boundaryPasses = Int((3 * sm).rounded())
        boundaryFidelity = 40
        consolidationTolerance = 0.1 * lerp(1.4, 0.7, d)
    }

    /// The coloring book's flatter paint (`coloringBookFlattening`). It must not change the
    /// radius knobs: `Vectorizer` and `LayeredLines` rebuild the parameters from the settings,
    /// without this, and read `minRadius(digits:)` for the room every number needs.
    mutating func flattenForColoringBook() {
        smoothSpatial *= Self.coloringBookFlattening
        textureFlattening *= Self.coloringBookFlattening
        minArea *= Self.coloringBookFlattening
    }

    /// Minimum inscribed radius of a region whose number has `digits` digits: scaled like the
    /// digit run's diagonal, so a minimal region's number renders at the same size whatever
    /// its digit count (`LabelSizing`).
    func minRadius(digits: Int) -> Float { minRadius * LabelSizing.roomFactor(digits: digits) }

    /// Raster room (`interiorDistance`) a detail area's number needs: as `minRadius(digits:)`
    /// guarantees `LabelSizing.minimumRadius`, this guarantees `LabelSizing.detailMinimumRadius`
    /// once smoothed (within `vectorRadiusTolerance`) and on the pixel outline around it, which
    /// clears 1.58 for any room above `detailLatticeFloor` and 2.12 above 1.92
    /// (`LabelSizingTests.detailMinimumRadiusIsAchievable`). The same at every detail: 1.6,
    /// 1.7 and 2.36 by digit count, below every `minRadius(digits:)`.
    static func detailMinRadius(digits: Int) -> Float {
        max(LabelSizing.minimumRadius(digits: digits, detail: true) / vectorRadiusTolerance, detailLatticeFloor)
    }

    /// The least raster room of a detail area: past 1.5, where a spot may be a plus of five
    /// pixels, whose outline comes within 0.71 of its centre.
    static let detailLatticeFloor: Float = 1.6

    /// Per-pixel multiplier of `minArea`: important areas keep smaller regions; busy
    /// texture (dense label changes, `texture` 0...1) outside important areas needs larger
    /// ones, so knit, foliage or gravel become a few paintable shapes rather than crumbs.
    /// The subject's body may be loosened where it is busy (`subjectCellSize`: fur, hair,
    /// foliage on it), never its face nor a smooth part of it, so a small face Vision missed
    /// (a rider under a hat) keeps its cells.
    @inline(__always)
    func areaScale(importance: Float, texture: Float) -> Float {
        let scale = exp2(importanceStrength * (0.5 - importance)) * (1 + textureStrength * (1 - importance) * texture)
        guard subjectCellSize != 1 else { return scale }
        return scale * (1 + (subjectCellSize - 1) * Self.subjectBody(importance) * min(1, 2 * max(texture, 0)))
    }

    /// Within `faceReach` eye widths of an eye in `faceCells` and on the face (importance from
    /// `faceImportance`), a floor under `areaScale` there (the segmenter takes the larger): a cell at least (`faceCellSize` − 1) / 64
    /// of the largest such eye's width squared; 0 elsewhere. kodim04's face, its eyes 88 px
    /// wide, was speckled in cells from 40 px² (the critic of kit paint's round 5: "a blotchy
    /// patchwork"); a face of 20-px eyes is barely touched. A low-contrast crumb counts a fifth
    /// of its area (`crumbFloor`), so speckle goes at five times this while a distinct spot (an
    /// iris, a dot of face paint) stays: at / 16, kodim15's painted dots went. Within
    /// `eyeReach` eye widths of an eye there's no floor: at 3, eyes lost their glints.
    @inline(__always)
    func faceCellScale(x: Int, y: Int, importance: Float) -> Float {
        guard importance >= Self.faceImportance, minArea > 0 else { return 0 }
        let p = SIMD2(Float(x) + 0.5, Float(y) + 0.5)
        var width: Float = 0
        for eye in faceCells {
            let d = p - SIMD2(eye.x, eye.y), reach = Self.faceReach * eye.z, d2 = (d * d).sum()
            // The eye itself keeps every cell: its glint, iris and white.
            if d2 < Self.eyeReach * Self.eyeReach * eye.z * eye.z { return 0 }
            if d2 <= reach * reach { width = max(width, eye.z) }
        }
        return (faceCellSize - 1) * width * width / 64 / minArea
    }

    static let faceReach: Float = 3
    static let eyeReach: Float = 0.7
    static let faceImportance: Float = 0.85

    /// The eyes `faceCellScale` reads, from eye polygons normalized to a canvas of this size
    /// (`LineArtInput.eyes`): only when `faceCellSize` is above 1; an eye that isn't finite,
    /// lies far off the canvas or is wider than a quarter of it is skipped.
    mutating func sizeFaces(byEyes eyes: [[SIMD2<Float>]], width: Int, height: Int) {
        guard faceCellSize > 1 else { return }
        let size = SIMD2(Float(width), Float(height))
        faceCells = eyes.compactMap { eye in
            guard !eye.isEmpty, eye.allSatisfy({ $0.x.isFinite && $0.y.isFinite && abs($0.x) < 4 && abs($0.y) < 4 })
            else { return nil }
            let points = eye.map { $0 * size }
            var lo = points[0], hi = points[0], sum = SIMD2<Float>(0, 0)
            for q in points {
                lo = pointwiseMin(lo, q)
                hi = pointwiseMax(hi, q)
                sum += q
            }
            let w = hi.x - lo.x
            guard w > 0, w < Float(max(width, height)) / 4 else { return nil }
            let c = sum / Float(points.count)
            return SIMD3(c.x, c.y, w)
        }
    }

    /// How much of the subject's body a pixel of this importance is, 0...1: none on the
    /// background (the app's map: 0.25, saliency up to 0.6), all on the subject (0.75), none
    /// again on a face's core (its ellipse rises to 1 there; eyes, lips, a glint).
    @inline(__always)
    static func subjectBody(_ importance: Float) -> Float {
        func ramp(_ a: Float, _ b: Float) -> Float {
            let t = min(max((importance - a) / (b - a), 0), 1)
            return t * t * (3 - 2 * t)
        }
        return ramp(0.6, 0.72) * (1 - ramp(0.85, 0.95))
    }
}

@inline(__always)
func lerp(_ a: Float, _ b: Float, _ t: Float) -> Float { a + (b - a) * t }
