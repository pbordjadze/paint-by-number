import Foundation

/// A drawing on paper → a coloring book whose areas the drawn lines bound
/// (`GenerationSettings.drawing`; `TemplateGenerator.generate` comes here).
///
/// 1. `ink`: the picture's ink at the working size (`DrawingScan.ink`: the paper flattened,
///    the lines at full strength, three pixels wide). A solid fill (`DrawingScan.Ink.solids`:
///    a silhouette, a black ground) keeps its edge as the line and loses its inside, so it
///    becomes an area of its own, painted the set's ink (`DrawingPalette.assign`). The lines
///    of small writing (`DrawingScan.textRows`) go through `Writing`, as a photo's text does:
///    traced finely, drawn legibly inside their cells, painted out of the paint, the numbers
///    kept off them.
/// 2. `lineArt`: the ink traced and the paper split along it by the line art's own stages
///    (`LayeredLines.apply` with `Tracing.drawing` and `DrawingSettings.lineArt`): the
///    centerlines, their gaps bridged, every uncrowded line splitting the paper
///    (`DrawingSettings.lineArt`), hatching kept one area with its strokes drawn inside
///    (`CellMap.mergeHatchClusters`), cells too small for a number merged into a neighbour,
///    the line between them drawn inside it. The sheet starts as the paper and its solid
///    fills, paints of their own, the paper's the set's last, so every cell is given room for
///    the longest number it may get.
/// 3. `palette`: the set's paints laid over the cells (`DrawingPalette.assign`).
/// 4. `vectorize` and `lineArt.annotate` as for a photo's book, the vectorizer's curve fit at
///    the settings' smoothness (`DrawingSettings` keeps it low, so the lines stay as drawn).
/// The template is a coloring book like any other: its lines draw in full ink, Refine edits
/// it, and nothing in its format says it came from a drawing (its settings do).
enum DrawingGenerator {
    /// The ink's strength inside the lines of small writing: detail, drawn inside its cell,
    /// below `DrawingSettings.lineArt`'s outline threshold and above its detail's.
    static let writingStrength: Float = 0.4

    static func generate(
        from image: RGBAImage, settings: GenerationSettings, drawing: DrawingSettings, cancel: CancellationCheck,
        progress: (@Sendable (Float) -> Void)?, observer: PipelineSnapshot.Observer?
    ) throws -> TemplateGenerator.Output {
        let clock = StageClock()
        progress?(0)
        let size = settings.workingSize(sourceWidth: image.width, sourceHeight: image.height)
        var working = try clock.measure("resample") {
            try Resample.area(image, width: size.width, height: size.height, cancel: cancel)
        }
        try cancel.throwIfCancelled()
        if let observer { try observer(SnapshotPictures.working(working, cancel: cancel)) }
        progress?(0.05)

        var ink = try clock.measure("ink") {
            try DrawingScan.ink(of: image, width: size.width, height: size.height, cancel: cancel)
        }
        try cancel.throwIfCancelled()
        progress?(0.25)

        // The lines of small writing are traced finely and drawn legibly, off the paint
        // (`Writing`, as a photo's text is): a caption stays a caption, never confetti. What
        // `Writing` leaves of them (a letter it dropped, a row it took for texture) is held at
        // `writingStrength`, drawn as detail inside its cell, never a wall.
        var writing: Writing?
        let rows = DrawingScan.textRows(in: ink.map)
        if !rows.isEmpty {
            let w = size.width, h = size.height
            let held = UInt8((writingStrength * 255).rounded())
            for row in rows {
                let x0 = max(0, Int(row[0].x * Float(w))), x1 = min(w, Int((row[1].x * Float(w)).rounded(.up)))
                let y0 = max(0, Int(row[0].y * Float(h))), y1 = min(h, Int((row[2].y * Float(h)).rounded(.up)))
                guard x1 > x0, y1 > y0 else { continue }
                for y in y0..<y1 {
                    for x in x0..<x1 where ink.map.values[y * w + x] > held { ink.map.values[y * w + x] = held }
                }
            }
        }
        if !rows.isEmpty {
            let params = SegmentationParameters(settings: settings.normalized, width: size.width, height: size.height)
            writing = try clock.measure("writing") {
                try Writing.find(in: &working, areas: rows, minRadius: params.minRadius, cancel: cancel, clock: clock)
            }
            try cancel.throwIfCancelled()
        }
        progress?(0.3)

        // The line art reads the line settings a drawing is traced with; the vectorizer and
        // the cells' room read the painter's detail and smoothness.
        var lineSettings = settings.normalized
        lineSettings.lineArt = DrawingSettings.lineArt
        // The sheet: the paper, with every solid fill a region of a paint of its own, so the
        // cells inside a fill never join the paper's (the paper's paint is the set's last, so a
        // cell's room is for the longest number it may get; the fills' is one past it).
        let set = DrawingPalette.colors(of: drawing.palette)
        let paper = PaletteColor(oklab: ColorScience.encodedToOKLab(SIMD3(1, 1, 1), space: .sRGB), space: .sRGB)
        let sheet = clock.measure("sheet") { () -> Segmentation in
            var classes = Grid<UInt32>(width: size.width, height: size.height, repeating: 0)
            for i in classes.storage.indices where ink.solids[i] { classes.storage[i] = 1 }
            let components = ConnectedComponents.label(classes)
            return Segmentation(
                labels: components.labels,
                regionColor: components.classOf.map { $0 == 1 ? UInt32(set.count) : UInt32(set.count - 1) },
                palette: [PaletteColor](repeating: paper, count: set.count) + [DrawingPalette.ink], colorSpace: .sRGB)
        }
        var plan = try clock.measure("lineArt") {
            try LayeredLines.apply(
                sheet, input: LineArtInput(edges: ink.map), importance: nil, settings: lineSettings, photo: image,
                writing: writing, tracing: .drawing, cancel: cancel, clock: clock)
        }
        try cancel.throwIfCancelled()
        progress?(0.6)

        let laid = clock.measure("palette") {
            DrawingPalette.assign(
                labels: plan.segmentation.labels, areaCount: plan.segmentation.regionCount, set: drawing.palette,
                paints: drawing.normalized.paints, seed: settings.seed,
                inked: plan.segmentation.regionColor.map { plan.segmentation.palette[Int($0)] == DrawingPalette.ink })
        }
        plan.segmentation.regionColor = laid.regionColor
        plan.segmentation.palette = laid.palette
        if let observer { try observer(SnapshotPictures.lineArt(plan)) }
        progress?(0.65)

        let keepOut = LabelKeepOut(rects: writing?.keepOut ?? [], lines: plan.drawnInterior.map(LabelKeepOut.Line.init))
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
