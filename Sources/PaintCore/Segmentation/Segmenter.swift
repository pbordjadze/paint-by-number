import Foundation

/// Photo → region label map + palette.
///
/// Pipeline (all color math in OKLab):
/// 1. Composite over white and convert to OKLab; resample the importance map.
/// 2. Edge-preserving smoothing (domain transform) flattens texture into painterly patches.
/// 3. Palette: weighted k-means++ over a compressed color histogram, with near-duplicates
///    merged and the palette refilled with distinct colors.
/// 4. Pixel labelling: nearest paint, regularized by a contrast-sensitive Potts prior.
/// 5. Regions: connected components, then merge undersized/thin regions and peel hair-thin
///    parts until every region is tappable and can hold a number.
/// 6. Refit paints to the pixels they cover, merge near-duplicates, order the palette.
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
        let weights = clock.measure("segment.importance") { ImportanceMap.make(importance, lab: lab) }
        DebugDump.scalar(weights, width: w, height: h, name: "importance")
        try cancel.throwIfCancelled()
        progress(0.05)

        let smooth = try clock.measure("segment.smooth") {
            try DomainTransformFilter.filter(
                lab, guide: lab, sigmaSpatial: p.smoothSpatial, sigmaRange: p.smoothRange,
                iterations: p.smoothIterations, stiffness: weights.map { 1 + p.importanceSharpening * $0 },
                cancel: cancel)
        }
        try cancel.throwIfCancelled()
        progress(0.25)
        DebugDump.lab(smooth, name: "smooth", chromaScale: p.chromaScale)

        let palette = try clock.measure("segment.palette") {
            try PaletteBuilder.build(colors: smooth, importance: weights, parameters: p, cancel: cancel)
        }
        if Tune.debug { debugLog("palette built: \(palette.count)") }
        try cancel.throwIfCancelled()
        progress(0.35)

        var classes = try clock.measure("segment.assign") { () throws -> [UInt32] in
            var labels = LabelRegularizer.assignNearest(smooth, palette: palette)
            try LabelRegularizer.regularize(
                &labels, colors: smooth, palette: palette, strength: p.potts, edgeSigma: p.pottsEdgeSigma,
                iterations: p.icmIterations, cancel: cancel)
            return labels
        }
        try cancel.throwIfCancelled()
        progress(0.5)
        DebugDump.classes(classes, width: w, height: h, palette: palette, name: "assigned", chromaScale: p.chromaScale)

        _ = try clock.measure("segment.regions") {
            try RegionSimplifier.simplify(
                classes: &classes, width: w, height: h, colors: smooth, importance: weights,
                palette: palette, parameters: p, cancel: cancel)
        }
        try cancel.throwIfCancelled()
        progress(0.85)

        let finalPalette = clock.measure("segment.refine") {
            PaletteRefiner.refine(
                classes: &classes, width: w, height: h, lab: lab.storage, importance: weights, palette: palette,
                minDistance: p.minPaletteDistance, chromaScale: p.chromaScale, iterations: p.refineIterations)
        }
        let components = clock.measure("segment.finalize") {
            ConnectedComponents.label(Grid(width: w, height: h, storage: classes))
        }
        progress(1)
        return Segmentation(
            labels: components.labels,
            regionColor: components.classOf,
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
