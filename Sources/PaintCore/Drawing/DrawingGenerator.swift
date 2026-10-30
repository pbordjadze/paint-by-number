import Foundation

/// A drawing on paper → a coloring book whose areas the drawn lines bound
/// (`GenerationSettings.drawing`; `TemplateGenerator.generate` comes here).
///
/// 1. `ink`: the picture's ink at the working size (`DrawingScan.ink`: the paper flattened,
///    the lines at full strength, three pixels wide). A solid fill (`DrawingScan.solids`: a
///    silhouette, a black ground) keeps its edge as the line and loses its inside, so it
///    becomes an area of its own, painted the set's ink (`DrawingPalette.assign`).
/// 2. `lineArt`: the ink traced and the paper split along it by the line art's own stages
///    (`LayeredLines.apply` with `Tracing.drawing` and `DrawingSettings.lineArt`): the
///    centerlines, their gaps bridged, every line splitting the one paint the sheet starts
///    with (`samePaint: .split`), cells too small for a number merged into a neighbour, the
///    line between them drawn inside it. The sheet starts with as many paints as the set has,
///    all paper, so every cell is given room for the longest number it may get.
/// 3. `palette`: the set's paints laid over the cells (`DrawingPalette.assign`).
/// 4. `vectorize` and `lineArt.annotate` as for a photo's book, the vectorizer's curve fit at
///    the settings' smoothness (`DrawingSettings` keeps it low, so the lines stay as drawn).
/// The template is a coloring book like any other: its lines draw in full ink, Refine edits
/// it, and nothing in its format says it came from a drawing (its settings do).
enum DrawingGenerator {
    static func generate(
        from image: RGBAImage, settings: GenerationSettings, drawing: DrawingSettings, cancel: CancellationCheck,
        progress: (@Sendable (Float) -> Void)?, observer: PipelineSnapshot.Observer?
    ) throws -> TemplateGenerator.Output {
        let clock = StageClock()
        progress?(0)
        let size = settings.workingSize(sourceWidth: image.width, sourceHeight: image.height)
        let working = try clock.measure("resample") {
            try Resample.area(image, width: size.width, height: size.height, cancel: cancel)
        }
        try cancel.throwIfCancelled()
        if let observer { try observer(SnapshotPictures.working(working, cancel: cancel)) }
        progress?(0.05)

        var ink = try clock.measure("ink") {
            try DrawingScan.ink(of: image, width: size.width, height: size.height, cancel: cancel)
        }
        try cancel.throwIfCancelled()
        // A solid fill is an area of its own, its edge the line: the ink inside it, past the
        // line's width from its edge, is taken out, so the skeleton traces the edge, not the
        // fill's axis.
        let solids = clock.measure("solids") { DrawingScan.solids(of: ink) }
        let rim = DrawingScan.inkWidth
        if solids.contains(true) {
            let w = size.width, h = size.height
            let edge = DistanceTransform.squaredEDT(width: w, height: h) { !solids[$0] }.storage
            for i in ink.values.indices where solids[i] && edge[i] > Float(rim * rim) { ink.values[i] = 0 }
        }
        try cancel.throwIfCancelled()
        progress?(0.25)

        // The line art reads the line settings a drawing is traced with; the vectorizer and
        // the cells' room read the painter's detail and smoothness.
        var lineSettings = settings.normalized
        lineSettings.lineArt = DrawingSettings.lineArt
        let set = DrawingPalette.colors(of: drawing.palette)
        let paper = PaletteColor(oklab: ColorScience.encodedToOKLab(SIMD3(1, 1, 1), space: .sRGB), space: .sRGB)
        let sheet = Segmentation(
            labels: RegionMap(width: size.width, height: size.height, repeating: 0),
            regionColor: [UInt32(set.count - 1)], palette: [PaletteColor](repeating: paper, count: set.count),
            colorSpace: .sRGB)
        var plan = try clock.measure("lineArt") {
            try LayeredLines.apply(
                sheet, input: LineArtInput(edges: ink), importance: nil, settings: lineSettings, photo: image,
                writing: nil, tracing: .drawing, cancel: cancel, clock: clock)
        }
        try cancel.throwIfCancelled()
        progress?(0.6)

        let laid = clock.measure("palette") {
            DrawingPalette.assign(
                labels: plan.segmentation.labels, areaCount: plan.segmentation.regionCount, set: drawing.palette,
                paints: drawing.normalized.paints, seed: settings.seed, solids: solids)
        }
        plan.segmentation.regionColor = laid.regionColor
        plan.segmentation.palette = laid.palette
        if let observer { try observer(SnapshotPictures.lineArt(plan)) }
        progress?(0.65)

        let keepOut = LabelKeepOut(rects: [], lines: plan.drawnInterior.map(LabelKeepOut.Line.init))
        var vector = try clock.measure("vectorize") {
            try Vectorizer.vectorizeWithStats(
                plan.segmentation, settings: lineSettings, keepOut: keepOut, detailRegions: plan.detailRegions,
                guides: plan.guides, cancel: cancel, clock: clock)
        }
        vector.template.pipelineVersion = TemplateGenerator.pipelineVersion
        try cancel.throwIfCancelled()
        vector.template.lineArt = try clock.measure("lineArt.annotate") {
            try LayeredLines.annotate(vector.template, plan: plan, cancel: cancel)
        }
        if let observer { try observer(SnapshotPictures.vectorized(vector.template)) }
        progress?(1)
        return TemplateGenerator.Output(
            template: vector.template, segmentation: plan.segmentation, vectorStats: vector.stats,
            lineArtStats: plan.stats, timings: clock.timings)
    }
}
