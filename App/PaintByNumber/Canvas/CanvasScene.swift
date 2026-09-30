import Foundation
import Metal
import PaintCore

/// Immutable GPU resources of one template: fill mesh, outline segments, number glyphs and
/// per-region colors. Built once when a canvas opens (a few flat copies — the template is
/// already laid out for upload) and shared by every frame and offscreen render.
nonisolated final class CanvasScene: @unchecked Sendable {
    let canvasSize: SIMD2<Float>
    let regionCount: Int

    let positions: any MTLBuffer        // float2 per mesh vertex
    let vertexRegions: any MTLBuffer    // uint per mesh vertex
    let indices: any MTLBuffer          // uint32 triangle list
    let indexCount: Int

    let points: any MTLBuffer           // float2 boundary polyline points
    let segments: any MTLBuffer         // uint2 (first point, edge) per segment
    let edgeRegions: any MTLBuffer      // uint2 (left, right) per edge
    let segmentCount: Int

    let glyphs: any MTLBuffer
    let glyphCount: Int
    let digitRects: any MTLBuffer
    let digitUVs: any MTLBuffer

    /// Linear P3 color per region; w = palette index.
    let regionColors: any MTLBuffer
    /// Linear P3 per palette color.
    let paletteLinear: [SIMD3<Float>]

    /// Font size (canvas units) of each region's primary number, 0 without one.
    let labelSizes: [Float]
    /// A small-but-typical number size (10th percentile): the max zoom makes these legible.
    let smallLabelSize: Float

    init?(template t: Template, context: RenderContext) {
        let device = context.device
        canvasSize = SIMD2(Float(t.width), Float(t.height))
        regionCount = t.regions.count

        let palette = t.palette.map { CanvasColor.linearP3($0, space: t.colorSpace) }
        paletteLinear = palette
        let colors = t.regions.map { SIMD4(palette[Int($0.colorIndex)], Float($0.colorIndex)) }

        var segs: [SIMD2<UInt32>] = []
        segs.reserveCapacity(max(0, t.points.count - t.edges.count))
        var neighbours: [SIMD2<UInt32>] = []
        neighbours.reserveCapacity(t.edges.count)
        for (e, edge) in t.edges.enumerated() {
            neighbours.append(SIMD2(edge.left, edge.right))
            guard edge.pointCount >= 2 else { continue }
            for k in 0..<(edge.pointCount - 1) { segs.append(SIMD2(edge.pointStart + k, UInt32(e))) }
        }

        // Numbers: size each run by the shared `LabelSizing` rule (the same as thumbnails, PDFs
        // and SVG), capped so huge regions don't shout, then emit one instance per digit
        // placed with the atlas's real advances.
        let atlas = context.atlas
        let maxSize = 0.045 * Float(min(t.width, t.height))
        var glyphList: [GlyphInstance] = []
        glyphList.reserveCapacity(t.labels.count * 2)
        var sizes = [Float](repeating: 0, count: t.regions.count)
        var primary = [Bool](repeating: false, count: t.regions.count)
        for label in t.labels {
            let region = Int(label.region)
            let number = Int(t.regions[region].colorIndex) + 1
            let digits = String(number).compactMap(\.wholeNumberValue)
            let w = atlas.runWidth(digits)
            let size = LabelSizing.fontSize(radius: label.radius, digits: digits.count, maximum: maxSize)
            if !primary[region] {
                primary[region] = true
                sizes[region] = size
            }
            var pen = -w / 2
            for d in digits {
                glyphList.append(GlyphInstance(center: label.position, size: size, offset: pen, digit: UInt32(d), region: label.region))
                pen += atlas.advances[d]
            }
        }
        labelSizes = sizes
        let sorted = sizes.filter { $0 > 0 }.sorted()
        smallLabelSize = sorted.isEmpty ? 1 : sorted[sorted.count / 10]

        guard let positions = CanvasScene.buffer(t.mesh.vertices, device),
              let vertexRegions = CanvasScene.buffer(t.mesh.vertexRegion, device),
              let indices = CanvasScene.buffer(t.mesh.indices, device),
              let points = CanvasScene.buffer(t.points, device),
              let segments = CanvasScene.buffer(segs, device),
              let edgeRegions = CanvasScene.buffer(neighbours, device),
              let glyphs = CanvasScene.buffer(glyphList, device),
              let digitRects = CanvasScene.buffer(atlas.rects, device),
              let digitUVs = CanvasScene.buffer(atlas.uvs, device),
              let regionColors = CanvasScene.buffer(colors, device)
        else { return nil }
        self.positions = positions
        self.vertexRegions = vertexRegions
        self.indices = indices
        indexCount = t.mesh.indices.count
        self.points = points
        self.segments = segments
        self.edgeRegions = edgeRegions
        segmentCount = segs.count
        self.glyphs = glyphs
        glyphCount = glyphList.count
        self.digitRects = digitRects
        self.digitUVs = digitUVs
        self.regionColors = regionColors
    }

    private static func buffer<T>(_ array: [T], _ device: any MTLDevice) -> (any MTLBuffer)? {
        array.withUnsafeBytes { raw in
            guard let base = raw.baseAddress, raw.count > 0 else {
                return device.makeBuffer(length: 16, options: .storageModeShared)
            }
            return device.makeBuffer(bytes: base, length: raw.count, options: .storageModeShared)
        }
    }
}
