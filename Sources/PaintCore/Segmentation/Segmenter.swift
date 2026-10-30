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
/// 5. Regions: merge undersized/thin regions (importance- and texture-scaled; low-contrast
///    crumbs need more area) and the transition strips of blurred edges, smooth outlines,
///    peel hair-thin parts, until every region is tappable and holds a number; then fuse
///    the bands of smooth gradients across weak boundaries and merge similar neighbours
///    inside busy texture.
/// 6. Refit paints to the regions they cover, recolor regions, re-spend the paints that
///    fusing or merging left unused on the worst-fitting regions (the rest are dropped),
///    keep paints distinct and order the palette like a kit.
/// 7. Regions too small for a multi-digit number take a paint with a shorter number or
///    merge (see `RegionSimplifier.enforceLabelRoom`), so every number is legible.
enum Segmenter {
    /// The pipeline with explicit knobs (tests switch stages off through them), also returning
    /// the importance weights it worked with (0...1 per working pixel: the given map
    /// resampled, or the fallback estimate), which line art reuses. The generator
    /// applies `flattenForColoringBook` to the parameters for coloring books.
    static func segment(
        _ image: RGBAImage,
        importance: Grid<Float>?,
        scene: SceneMap? = nil,
        parameters p: SegmentationParameters,
        cancel: CancellationCheck,
        clock: StageClock,
        progress: (Float) -> Void,
        observer: PipelineSnapshot.Observer? = nil
    ) throws -> (segmentation: Segmentation, importance: [Float]) {
        let w = image.width, h = image.height
        guard w > 0, h > 0 else {
            let empty = Segmentation(
                labels: RegionMap(width: w, height: h, repeating: 0), regionColor: [], palette: [],
                colorSpace: image.colorSpace)
            return (empty, [])
        }

        let lab = try clock.measure("segment.oklab") { try WorkingImage.okLab(image, chromaScale: p.chromaScale, cancel: cancel) }
        try cancel.throwIfCancelled()
        let structure = try clock.measure("segment.structure") {
            try StructureMap(lab, radius: p.structureRadius, cancel: cancel)
        }
        try cancel.throwIfCancelled()
        if let observer { try observer(SnapshotPictures.structure(structure)) }
        // The scene method lays the photo out by its scene (`SceneLayers`); the color method
        // reads the importance map as given, or estimates one.
        let layers = p.method == .scene
            ? try clock.measure("segment.scene") { try SceneLayers.make(scene: scene, lab: lab, structure: structure, parameters: p, cancel: cancel) }
            : nil
        let weights = try clock.measure("segment.importance") {
            try layers?.importance ?? ImportanceMap.make(importance, structure: structure, cancel: cancel)
        }
        try cancel.throwIfCancelled()
        progress(0.05)

        let smooth = try clock.measure("segment.smooth") { () throws -> Grid<SIMD4<Float>> in
            let edgeScale = p.textureFlattening > 0
                ? try structure.edgeScales(
                    importance: weights, strength: p.textureFlattening, exponent: p.structureExponent, cancel: cancel)
                : nil
            try cancel.throwIfCancelled()
            if let layers {
                return try DomainTransformFilter.filter(
                    lab, sigmaSpatial: p.smoothSpatial * (layers.hasScene ? p.sceneBackgroundSmoothing : 1), sigmaRange: p.smoothRange,
                    iterations: p.smoothIterations, edgeScale: edgeScale, stiffness: (layers.stretch, 1),
                    barrier: layers.barrier, cancel: cancel)
            }
            return try DomainTransformFilter.filter(
                lab, sigmaSpatial: p.smoothSpatial, sigmaRange: p.smoothRange, iterations: p.smoothIterations,
                edgeScale: edgeScale, stiffness: (weights, p.importanceSharpening), cancel: cancel)
        }
        try cancel.throwIfCancelled()
        if let observer {
            try observer(SnapshotPictures.smoothed(smooth, chromaScale: p.chromaScale, space: image.colorSpace))
        }
        progress(0.25)

        let palette = try clock.measure("segment.palette") {
            try PaletteBuilder.build(colors: smooth, importance: weights, parameters: p, cancel: cancel)
        }
        try cancel.throwIfCancelled()
        progress(0.35)

        var classes = try clock.measure("segment.assign") { () throws -> [UInt32] in
            var labels = try clock.measure("segment.assign.nearest") {
                try LabelRegularizer.assignNearest(smooth, palette: palette, cancel: cancel)
            }
            try cancel.throwIfCancelled()
            try clock.measure("segment.assign.icm") { try LabelRegularizer.regularize(
                &labels, colors: smooth, palette: palette, strength: p.potts, edgeSigma: p.pottsEdgeSigma,
                iterations: p.icmIterations, cancel: cancel) }
            return labels
        }
        try cancel.throwIfCancelled()
        if let observer {
            try observer(SnapshotPictures.palette(
                classes, width: w, height: h, colors: palette, chromaScale: p.chromaScale, space: image.colorSpace))
        }
        progress(0.5)

        // The scene method keeps the two sides of the silhouette apart through region
        // simplification, band fusion and consolidation as if they were painted with two kits of
        // the same paints (`SegmentationParameters.sidePaints`): the subject's classes are offset
        // by the palette's count, `sidePalette` repeats the paints, and merges across the
        // silhouette pay `sceneCrossPenalty`. The sides fold back before the paints are refitted.
        var sidePalette = palette
        var q = p
        if let layers, layers.hasScene {
            let k = UInt32(palette.count)
            for i in classes.indices where layers.isSubject[i] { classes[i] += k }
            sidePalette = palette + palette
            q.sidePaints = palette.count
        }
        var labelling = classes
        let (texture, areaScale) = try clock.measure("segment.texture") { () throws -> ([Float], [Float]) in
            let texture = try TextureMap.boundaryDensity(labelling, width: w, height: h, cancel: cancel)
            var scale = [Float](uninitializedCount: w * h)
            let factor = layers?.areaFactor ?? []
            weights.withUnsafeBufferPointer { ib in
                texture.withUnsafeBufferPointer { tb in
                    scale.withUnsafeMutableBufferPointer { sb in
                        factor.withUnsafeBufferPointer { fb in
                            let i = UncheckedSendable(ib), t = UncheckedSendable(tb), s = UncheckedSendable(sb), f = UncheckedSendable(fb)
                            Parallel.forEachBand(w * h, minimumBandSize: 16_384) { range in
                                for k in range {
                                    s.value[k] = p.areaScale(importance: i.value[k], texture: t.value[k])
                                    if !f.value.isEmpty { s.value[k] *= f.value[k] }
                                }
                            }
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
                palette: sidePalette, parameters: q,
                calm: layers.flatMap { $0.hasScene ? ($0.calm, $0.calmRadius, p.sceneCalmPasses) : nil }, cancel: cancel, clock: clock)
        }
        try cancel.throwIfCancelled()
        let metric = SIMD3<Float>(1, 1 / p.chromaScale, 1 / p.chromaScale)
        let fusion: Float = layers?.hasScene == true ? p.sceneBandFusion : 1
        try clock.measure("segment.bands") {
            try BandMerging.apply(
                classes: &classes, labelling: &labelling, regions: &regions, adjacency: &adjacency, colors: smooth.storage,
                importance: weights, palette: sidePalette, metric: metric,
                tolerance: (p.bandNearTolerance, p.bandNearImportantTolerance, p.bandTolerance * fusion),
                bandWidth: p.bandWidth * (layers?.hasScene == true ? p.sceneBandWidth : 1), contrast: p.bandContrast,
                sidePaints: q.sidePaints, cancel: cancel)
        }
        try cancel.throwIfCancelled()
        clock.measure("segment.consolidate") {
            TextureConsolidation.apply(
                classes: &classes, regions: &regions, adjacency: &adjacency, texture: texture, importance: weights,
                palette: sidePalette, metric: metric, tolerance: p.consolidationTolerance, sidePaints: q.sidePaints)
        }
        try cancel.throwIfCancelled()
        progress(0.85)

        // The sides fold back into the regions (`RegionRuns.side`), so regions of one paint on
        // either side of the silhouette stay two regions through every later fuse and merge.
        if q.sidePaints > 0 {
            let k = UInt32(palette.count)
            regions.side = regions.classOf.map { $0 >= k ? 1 : 0 }
            regions.classOf = regions.classOf.map { $0 % k }
            for i in classes.indices { classes[i] %= k }
            for i in labelling.indices { labelling[i] %= k }
        }
        var finalPalette = try clock.measure("segment.refine") {
            try PaletteRefiner.refine(
                classes: &classes, regions: &regions, adjacency: &adjacency, lab: lab.storage, importance: weights,
                labelling: labelling, palette: palette, minDistance: p.minPaletteDistance,
                chromaScale: p.chromaScale, iterations: p.refineIterations, cancel: cancel)
        }
        try cancel.throwIfCancelled()
        let working = finalPalette.map { $0 * SIMD3(1, p.chromaScale, p.chromaScale) }
        let room = try clock.measure("segment.legible") {
            try RegionSimplifier.enforceLabelRoom(
                classes: &classes, regions: &regions, adjacency: &adjacency, colors: smooth.storage,
                areaScale: areaScale, palette: working, parameters: p, cancel: cancel)
        }
        finalPalette = room.kept.map { finalPalette[$0] }
        try cancel.throwIfCancelled()
        let labels = clock.measure("segment.finalize") { regions.labelMap() }
        progress(1)
        let segmentation = Segmentation(
            labels: labels,
            regionColor: regions.classOf,
            palette: finalPalette.map { PaletteColor(oklab: $0, space: image.colorSpace) },
            colorSpace: image.colorSpace)
        if let observer { try observer(SnapshotPictures.simplified(segmentation)) }
        return (segmentation, weights)
    }
}
