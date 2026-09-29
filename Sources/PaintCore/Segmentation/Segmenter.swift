import Foundation

/// Photo → region label map + palette.
///
/// Pipeline (color math in OKLab with slightly stretched chroma):
/// 1. Composite over white; tell structure from texture (relative total variation); take
///    the importance map (Vision) or estimate one (center bias + coherent structure).
/// 2. Structure-aware edge-preserving smoothing (domain transform): texture flattens into
///    painterly patches, contours stay sharp, important areas keep more detail.
/// 3. Palette: importance- and saliency-weighted histogram, k-means++ kept apart by the
///    minimum paint distance, penalized swap search with restarts (small distinct colors
///    such as an iris survive).
/// 4. Pixel labelling: nearest paint, regularized by a contrast-sensitive Potts prior.
/// 5. Regions: merge undersized/thin regions (importance- and texture-scaled), smooth
///    outlines, peel hair-thin parts, until every region is tappable and holds a number;
///    then merge similar neighbours inside busy texture.
/// 6. Refit paints to the regions they cover, recolor regions, keep paints distinct and
///    order the palette like a kit.
public enum Segmenter {
    public static func segment(
        _ image: RGBAImage,
        importance: Grid<Float>?,
        settings: GenerationSettings,
        cancel: CancellationCheck,
        clock: StageClock,
        progress: (Float) -> Void
    ) throws -> Segmentation {
        let w = image.width, h = image.height
        guard w > 0, h > 0 else {
            return Segmentation(
                labels: RegionMap(width: w, height: h, repeating: 0), regionColor: [], palette: [],
                colorSpace: image.colorSpace)
        }
        let p = SegmentationParameters(settings: settings, width: w, height: h)

        let lab = clock.measure("segment.oklab") { WorkingImage.okLab(image, chromaScale: p.chromaScale) }
        try cancel.throwIfCancelled()
        let structure = try clock.measure("segment.structure") {
            try StructureMap(lab, radius: p.structureRadius, cancel: cancel)
        }
        try cancel.throwIfCancelled()
        let weights = clock.measure("segment.importance") { ImportanceMap.make(importance, structure: structure) }
        try cancel.throwIfCancelled()
        progress(0.05)

        let smooth = try clock.measure("segment.smooth") { () throws -> Grid<SIMD4<Float>> in
            let edgeScale = p.textureFlattening > 0
                ? structure.edgeScales(importance: weights, strength: p.textureFlattening, exponent: p.structureExponent)
                : nil
            return try DomainTransformFilter.filter(
                lab, sigmaSpatial: p.smoothSpatial, sigmaRange: p.smoothRange,
                iterations: p.smoothIterations, edgeScale: edgeScale,
                stiffness: Grid(width: w, height: h, storage: weights).map { 1 + p.importanceSharpening * $0 }.storage,
                cancel: cancel)
        }
        try cancel.throwIfCancelled()
        progress(0.25)

        let palette = try clock.measure("segment.palette") {
            try PaletteBuilder.build(colors: smooth, importance: weights, parameters: p, cancel: cancel)
        }
        try cancel.throwIfCancelled()
        progress(0.35)

        var classes = try clock.measure("segment.assign") { () throws -> [UInt32] in
            var labels = clock.measure("segment.assign.nearest") { LabelRegularizer.assignNearest(smooth, palette: palette) }
            try clock.measure("segment.assign.icm") { try LabelRegularizer.regularize(
                &labels, colors: smooth, palette: palette, strength: p.potts, edgeSigma: p.pottsEdgeSigma,
                iterations: p.icmIterations, cancel: cancel) }
            return labels
        }
        try cancel.throwIfCancelled()
        progress(0.5)

        let labelling = classes
        let (texture, areaScale) = clock.measure("segment.texture") { () -> ([Float], [Float]) in
            let texture = TextureMap.boundaryDensity(labelling, width: w, height: h)
            var scale = [Float](repeating: 0, count: w * h)
            weights.withUnsafeBufferPointer { ib in
                texture.withUnsafeBufferPointer { tb in
                    scale.withUnsafeMutableBufferPointer { sb in
                        let i = UncheckedSendable(ib), t = UncheckedSendable(tb), s = UncheckedSendable(sb)
                        Parallel.forEachBand(w * h, minimumBandSize: 16_384) { range in
                            for k in range { s.value[k] = p.areaScale(importance: i.value[k], texture: t.value[k]) }
                        }
                    }
                }
            }
            return (texture, scale)
        }
        try cancel.throwIfCancelled()
        var (regions, adjacency) = try clock.measure("segment.regions") {
            try RegionSimplifier.simplify(
                classes: &classes, width: w, height: h, colors: smooth, areaScale: areaScale,
                palette: palette, parameters: p, cancel: cancel, clock: clock)
        }
        clock.measure("segment.consolidate") {
            _ = TextureConsolidation.apply(
                classes: &classes, regions: &regions, adjacency: &adjacency, texture: texture, importance: weights,
                palette: palette, metric: SIMD3(1, 1 / p.chromaScale, 1 / p.chromaScale),
                tolerance: p.consolidationTolerance)
        }
        try cancel.throwIfCancelled()
        progress(0.85)

        let finalPalette = clock.measure("segment.refine") {
            PaletteRefiner.refine(
                classes: &classes, regions: &regions, adjacency: &adjacency, lab: lab.storage, importance: weights,
                labelling: labelling, palette: palette, minDistance: p.minPaletteDistance,
                chromaScale: p.chromaScale, iterations: p.refineIterations)
        }
        let labels = clock.measure("segment.finalize") { regions.labelMap() }
        progress(1)
        return Segmentation(
            labels: labels,
            regionColor: regions.classOf,
            palette: finalPalette.map { PaletteColor(oklab: $0, space: image.colorSpace) },
            colorSpace: image.colorSpace)
    }
}

/// Small, fast, deterministic PRNG (SplitMix64).
public struct SplitMix64: RandomNumberGenerator, Sendable {
    public var state: UInt64

    public init(seed: UInt64) { state = seed }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform float in [0, 1).
    public mutating func nextFloat() -> Float {
        Float(next() >> 40) * (1.0 / Float(1 << 24))
    }
}
