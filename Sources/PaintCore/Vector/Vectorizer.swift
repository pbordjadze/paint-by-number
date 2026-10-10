/// Segmentation → vector template: shared smoothed boundaries, per-region rings, a
/// triangulated fill mesh and number placements.
///
/// 1. `BoundaryGraph` traces region boundaries on the pixel-corner lattice into edges
///    between junctions (exact, integer chain codes) and assembles each region's rings.
/// 2. `EdgeSmoother` fits every edge once (`CurveFitter`, potrace-style, then
///    `CurveFairing`), so both neighbouring regions use the very same curve and fills tile
///    the canvas without gaps or overlaps; `GeometryValidator` finds any curve that would
///    cross or touch another edge and it falls back to cruder but provably valid shapes.
///    Each region is labelled at the pole of inaccessibility of its smoothed polygon
///    (`PolyLabel`); where smoothing left a label less room than the raster promised
///    (`LabelRoom`; a detail area's, `Template.detailRegions`, by its own floor), the edges
///    near it fall back the same way until it has enough.
/// 3. Each region's rings are triangulated (`Earcut`, kept conforming along shared
///    boundaries), with extra labels spread over large regions.
public enum Vectorizer {
    /// Precision of the pole of inaccessibility, canvas units. The pole radius sizes the
    /// number and is the region's `inscribedRadius`, which must be 2 or more. For regions
    /// near that floor (raster radius under `smallRegionRadius`) 0.25 would understate it by
    /// up to 12 %, so they are measured finely; that is cheap, their outlines are short.
    static let labelPrecision = 0.25
    static let smallRegionLabelPrecision = 0.005
    static let smallRegionRadius: Float = 3
    /// Precision of the second search for a label short of its room.
    static let finePrecision = 0.01

    public static func vectorize(
        _ segmentation: Segmentation,
        settings: GenerationSettings,
        cancel: CancellationCheck,
        clock: StageClock
    ) throws -> Template {
        try vectorizeWithStats(segmentation, settings: settings, cancel: cancel, clock: clock).template
    }

    /// `vectorize`, also reporting what the vectorizer had to give up. Numbers keep off
    /// `keepOut` where their regions have room elsewhere (`LabelKeepOut`); the regions of
    /// `detailRegions` (ascending) are the template's detail areas, whose numbers need only
    /// `LabelSizing.detailMinimumRadius`.
    public static func vectorizeWithStats(
        _ segmentation: Segmentation,
        settings: GenerationSettings,
        cancel: CancellationCheck,
        clock: StageClock
    ) throws -> (template: Template, stats: VectorStats) {
        try vectorizeWithStats(segmentation, settings: settings, keepOut: LabelKeepOut(rects: []), cancel: cancel, clock: clock)
    }

    static func vectorizeWithStats(
        _ segmentation: Segmentation,
        settings: GenerationSettings,
        keepOut: LabelKeepOut,
        detailRegions: [UInt32] = [],
        cancel: CancellationCheck,
        clock: StageClock
    ) throws -> (template: Template, stats: VectorStats) {
        let map = segmentation.labels
        let w = map.width, h = map.height
        let regionCount = segmentation.regionCount
        guard w > 0, h > 0, regionCount > 0 else {
            let empty = Template(
                width: w, height: h, colorSpace: segmentation.colorSpace, palette: segmentation.palette,
                regions: [], points: [], edges: [], ringEdges: [], rings: [], labels: [], mesh: FillMesh(), regionMap: map)
            return (empty, VectorStats())
        }

        let graph = try clock.measure("vectorize.graph") { try BoundaryGraph.build(labels: map, cancel: cancel) }
        try cancel.throwIfCancelled()
        let topology = clock.measure("vectorize.rings") { graph.assembleRings(labels: map, regionCount: regionCount) }
        try cancel.throwIfCancelled()

        let distance = try clock.measure("vectorize.edt") { try DistanceTransform.interiorDistance(labels: map, cancel: cancel) }
        let raster = clock.measure("vectorize.raster") { RasterStats(labels: map, distance: distance, regionCount: regionCount) }
        try cancel.throwIfCancelled()

        // Label room: the segmentation promised each region a disc of its raster minimum
        // (`SegmentationParameters.minRadius(digits:)`, a detail area's `detailMinRadius`); the
        // smoothed polygon may lose up to the tolerance of it, never more than the pixel
        // outline would.
        let detail = { () -> [Bool] in
            var detail = [Bool](repeating: false, count: regionCount)
            for r in detailRegions where Int(r) < regionCount { detail[Int(r)] = true }
            return detail
        }()
        let room = clock.measure("vectorize.room") { () -> LabelRoom in
            let params = SegmentationParameters(settings: settings, width: w, height: h)
            let bands = Parallel.mapBands(regionCount, minimumBandSize: 256) { range -> [(SIMD2<Double>, Float)] in
                range.map { r in
                    let pixel = Int(raster.bestPixel[r])
                    let digits = LabelSizing.digitCount(colorIndex: segmentation.regionColor[r])
                    let need = detail[r] ? SegmentationParameters.detailMinRadius(digits: digits) : params.minRadius(digits: digits)
                    let required = SegmentationParameters.vectorRadiusTolerance * need
                    let clearance = RasterStats.latticeClearance(map, pixel: pixel, region: UInt32(r), limit: required)
                    return (SIMD2(Double(pixel % w) + 0.5, Double(pixel / w) + 0.5), min(required, clearance))
                }
            }
            let all = Array(bands.joined())
            let small = (0..<regionCount).map { raster.bestDistance[$0] < Vectorizer.smallRegionRadius }
            return LabelRoom(
                topology: topology, seeds: all.map(\.0), minRadius: all.map(\.1), measureFinely: small, detail: detail)
        }
        try cancel.throwIfCancelled()

        let smoothing = try clock.measure("vectorize.smooth") {
            try EdgeSmoother(graph: graph, smoothness: settings.normalized.smoothness).run(labelRoom: room, cancel: cancel)
        }
        var poles = smoothing.poles
        let geometry = smoothing.geometry
        let edges = geometry.boundaryEdges(graph)
        try cancel.throwIfCancelled()

        let shapes = RegionShapes(points: geometry.points, edges: edges, topology: topology)
        if !keepOut.isEmpty {
            clock.measure("vectorize.keepOut") {
                keepOut.move(&poles, shapes: shapes, room: room, regionColor: segmentation.regionColor)
            }
            try cancel.throwIfCancelled()
        }
        var fills = try clock.measure("vectorize.fill") {
            try RegionFills.build(shapes, poles: poles, width: w, height: h, cancel: cancel)
        }
        try cancel.throwIfCancelled()
        clock.measure("vectorize.labels") {
            fills.addExtraLabels(
                shapes, raster: raster, distance: distance, map: map, regionColor: segmentation.regionColor,
                keepOut: keepOut, width: w, height: h)
        }
        try cancel.throwIfCancelled()

        var regions: [Region] = []
        regions.reserveCapacity(regionCount)
        var labels: [Label] = []
        labels.reserveCapacity(regionCount)
        var indexCursor: UInt32 = 0
        for r in 0..<regionCount {
            let labelStart = UInt32(labels.count)
            labels.append(Label(position: fills.pole[r], radius: fills.poleRadius[r], region: UInt32(r)))
            for extra in fills.extraLabels[r] { labels.append(extra) }
            regions.append(Region(
                colorIndex: segmentation.regionColor[r], area: fills.area[r], bounds: fills.bounds[r],
                inscribedRadius: fills.poleRadius[r],
                ringStart: topology.regionRingStart[r], ringCount: topology.regionRingCount[r],
                labelStart: labelStart, labelCount: UInt32(labels.count) - labelStart,
                indexStart: indexCursor, indexCount: fills.indexCount[r]))
            indexCursor += fills.indexCount[r]
        }

        var template = Template(
            width: w, height: h, colorSpace: segmentation.colorSpace, palette: segmentation.palette,
            regions: regions, points: geometry.points, edges: edges,
            ringEdges: topology.ringEdges, rings: topology.rings, labels: labels,
            mesh: FillMesh(vertices: fills.vertices, vertexRegion: fills.vertexRegion, indices: fills.indices),
            regionMap: map)
        template.detailRegions = (0..<regionCount).filter { detail[$0] }.map { UInt32($0) }
        let stats = VectorStats(
            fallbackEdges: smoothing.repairs, labelRoomEdges: smoothing.labelRoomEdges,
            labelRoomRegions: smoothing.labelRoomRegions, labelRoomUnmet: smoothing.labelRoomUnmet)
        return (template, stats)
    }
}

/// What vectorizing a segmentation had to give up (quality metrics; zero for clean input).
public struct VectorStats: Sendable, Equatable {
    /// Edges that fell back from the faired curve to keep the geometry valid.
    public var fallbackEdges = 0
    /// Distinct edges stepped toward the pixel outline so a label keeps its room.
    public var labelRoomEdges = 0
    /// Distinct regions whose label was short of its room at some point.
    public var labelRoomRegions = 0
    /// Regions whose label still lacked its room when smoothing ended (always zero; a
    /// nonzero count points at a broken guarantee in `EdgeSmoother.run`).
    public var labelRoomUnmet = 0

    public init(fallbackEdges: Int = 0, labelRoomEdges: Int = 0, labelRoomRegions: Int = 0, labelRoomUnmet: Int = 0) {
        self.fallbackEdges = fallbackEdges
        self.labelRoomEdges = labelRoomEdges
        self.labelRoomRegions = labelRoomRegions
        self.labelRoomUnmet = labelRoomUnmet
    }
}

/// Per-region raster statistics: pixel area, pixel bounds and the distance-transform
/// maximum (a seed for the pole of inaccessibility).
struct RasterStats {
    var pixelArea: [Int32]
    var pixelBounds: [PixelBounds]
    var bestDistance: [Float]
    var bestPixel: [Int32]

    init(labels: RegionMap, distance: Grid<Float>, regionCount: Int) {
        let w = labels.width, h = labels.height
        struct Band {
            var area: [Int32], bounds: [PixelBounds], best: [Float], bestPixel: [Int32]
        }
        let bands = labels.storage.withUnsafeBufferPointer { lab in
            distance.storage.withUnsafeBufferPointer { dist in
                let l = UncheckedSendable(lab), d = UncheckedSendable(dist)
                return Parallel.mapBands(h, minimumBandSize: 32) { rows -> Band in
                    var b = Band(
                        area: [Int32](repeating: 0, count: regionCount),
                        bounds: [PixelBounds](repeating: .empty, count: regionCount),
                        best: [Float](repeating: -1, count: regionCount),
                        bestPixel: [Int32](repeating: 0, count: regionCount))
                    for y in rows {
                        for x in 0..<w {
                            let i = y * w + x
                            let r = Int(l.value[i])
                            b.area[r] += 1
                            b.bounds[r].include(x: x, y: y)
                            if d.value[i] > b.best[r] { b.best[r] = d.value[i]; b.bestPixel[r] = Int32(i) }
                        }
                    }
                    return b
                }
            }
        }
        pixelArea = [Int32](repeating: 0, count: regionCount)
        pixelBounds = [PixelBounds](repeating: .empty, count: regionCount)
        bestDistance = [Float](repeating: -1, count: regionCount)
        bestPixel = [Int32](repeating: 0, count: regionCount)
        for b in bands {
            for r in 0..<regionCount where b.area[r] > 0 {
                pixelArea[r] += b.area[r]
                pixelBounds[r].formUnion(b.bounds[r])
                if b.best[r] > bestDistance[r] { bestDistance[r] = b.best[r]; bestPixel[r] = b.bestPixel[r] }
            }
        }
    }

    /// Distance from the centre of `pixel` (a pixel of `region`) to the nearest pixel square
    /// outside the region (or outside the canvas), at most `limit`: how far the region's
    /// pixel-exact outline stays from that point. Walks square rings outward, so the cost
    /// grows with the answer, not the region.
    static func latticeClearance(_ labels: RegionMap, pixel: Int, region: UInt32, limit: Float) -> Float {
        let w = labels.width, h = labels.height
        let px = pixel % w, py = pixel / w
        var best = limit
        var k = 1
        // Every square on ring k is at least k − ½ away; the canvas edge ends the walk.
        while Float(k) - 0.5 < best {
            func visit(_ ox: Int, _ oy: Int) {
                let x = px + ox, y = py + oy
                guard x < 0 || y < 0 || x >= w || y >= h || labels.storage[y * w + x] != region else { return }
                let dx = max(Float(abs(ox)) - 0.5, 0), dy = max(Float(abs(oy)) - 0.5, 0)
                best = min(best, (dx * dx + dy * dy).squareRoot())
            }
            for ox in -k...k {
                visit(ox, -k)
                visit(ox, k)
            }
            for oy in (1 - k)..<k {
                visit(-k, oy)
                visit(k, oy)
            }
            k += 1
        }
        return best
    }
}
