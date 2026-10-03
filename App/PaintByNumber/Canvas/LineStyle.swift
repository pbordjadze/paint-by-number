import Foundation
import PaintCore

/// How strongly each `LineLayer` draws in one frame or image, as factors of the classic line at
/// the same zoom: 1 draws exactly a classic template's line. The canvas, `CanvasSnapshot` (share
/// pictures, time-lapse) and `TemplateRasterizer` (thumbnails, previews, PDF) all draw layered
/// templates through it; classic templates always use `.classic`, so they look as they always did.
nonisolated struct LineStyle: Equatable, Sendable {
    /// Ink opacity per layer (x outline, y detail, z texture, w color), relative to the classic line's.
    var opacity: SIMD4<Float>
    /// Width per layer, relative to the classic line's.
    var width: SIMD4<Float>
    /// Lines within a layer are drawn heavier or lighter by their edge's strength (`DrawableLineArt.weights`).
    var weighted: Bool

    /// Every line alike, as classic templates draw them.
    static let classic = LineStyle(opacity: SIMD4(repeating: 1), width: SIMD4(repeating: 1), weighted: false)

    /// Printed templates (PDF): paper can't zoom, so every layer prints visibly, outlines the
    /// heaviest and color boundaries the lightest; the screen's per-zoom fades don't apply.
    static let print = LineStyle(opacity: SIMD4(1, 0.85, 0.7, 0.55), width: SIMD4(1.5, 1.15, 0.9, 0.8), weighted: false)

    init(opacity: SIMD4<Float>, width: SIMD4<Float>, weighted: Bool) {
        self.opacity = opacity
        self.width = width
        self.weighted = weighted
    }

    /// `appearance` at `zoom` (1 = the painting fitted), for a renderer whose classic line has
    /// `classicStrength` of the full ink. The appearance's opacities are fractions of the full
    /// ink, so they are divided by it: the canvas draws classic lines lighter zoomed out
    /// (`classicStrength(depth:)`), pictures draw them at their style's full ink (1). Its widths
    /// already are factors of the classic width.
    init(_ appearance: LineAppearance, zoom: Float, classicStrength strength: Float = 1) {
        var opacity = SIMD4<Float>(repeating: 1), width = SIMD4<Float>(repeating: 1)
        for layer in LineLayer.allCases {
            let i = Int(layer.rawValue)
            opacity[i] = max(0, appearance[layer].opacity(atZoom: zoom)) / max(strength, 1e-3)
            width[i] = max(0, appearance[layer].width(atZoom: zoom))
        }
        self.init(opacity: opacity, width: width, weighted: appearance.weighted)
    }

    /// Classic line art's opacity as a fraction of the paper's full ink, `depth` zoom doublings
    /// in: lighter zoomed out, where regions are small on screen.
    static func classicStrength(depth: Float) -> Float { min(1, 0.7 + 0.15 * depth) }

    /// Classic line art's width on the canvas (points), `depth` zoom doublings in: finer zoomed out.
    static func classicWidthPoints(depth: Float) -> Float { min(1.0, 0.5 + 0.22 * depth) }
}

/// How a coloring book draws (`TemplateLineArt.Style.coloringBook`), the same in every renderer:
/// every drawn layer alike, in the paper's full ink, heavy at every zoom, never dissolving under
/// the paint; color edges (the paints inside an outline) never drawn, and the selected color's
/// cells never outlined, since the fill's highlight shows them. Only the weight is the painter's
/// (`LineAppearance.coloringBookWeight`).
nonisolated enum ColoringBookLook {
    /// A book line in pictures (thumbnails, share images, print), as a factor on the picture's
    /// classic line: three times as heavy, the canvas's ratio with the painting fitted.
    static let widthFactor: Float = 3

    /// The canvas's book line (points), `depth` zoom doublings in: 1.5 pt fitted (three times
    /// the classic line there), growing with the zoom but far slower than the drawing, so zoomed
    /// in it reads as a pen line, not a band. Times `weight`.
    static func widthPoints(depth: Float, weight: Float) -> Float { (1.5 + 0.7 * max(depth, 0)) * weight }

    /// The ink pictures draw the book with: the canvas sheet's ink, encoded sRGB.
    static let ink = SIMD4<Float>(0.118, 0.102, 0.133, 1)

    /// On paper there is no highlight to show a color's cells, so a printed book draws its color
    /// edges as dotted guides: this fraction of the print style's outline opacity, dots this many
    /// line widths apart.
    static let printedGuideOpacity: Float = 0.7
    static let printedGuideSpacing: CGFloat = 2.5
}

/// A template's line art checked against the template, ready to draw: a layer and width factor
/// per boundary edge, and the interior strokes that fit. Renderers never index with unchecked
/// line data (PaintCore's decoder checks files too; this keeps a malformed template drawable as
/// classic instead of trapping).
nonisolated struct DrawableLineArt: Sendable {
    /// Layer (`LineLayer` raw value) per `Template.edges` entry.
    let edgeLayers: [UInt8]
    /// Width factor per edge from its weight (`weights(layers:strengths:)`).
    let edgeWeights: [Float]
    /// The template's strokes that are well formed, in their order.
    let strokes: [InteriorStroke]
    /// Width factor per entry of `strokes`.
    let strokeWeights: [Float]
    let strokePoints: [SIMD2<Float>]
    /// How the lines are drawn (`TemplateLineArt.style`).
    let style: TemplateLineArt.Style

    /// nil for classic templates, and for line art that doesn't match the template's edges.
    init?(_ t: Template) {
        guard let art = t.lineArt, art.edgeLayers.count == t.edges.count, art.edgeWeights.count == t.edges.count else {
            return nil
        }
        let maxLayer = LineLayer.color.rawValue
        let points = art.strokePoints.count, regions = t.regions.count
        let strokes = art.strokes.filter { s in
            s.pointCount >= 2 && Int(s.pointStart) + Int(s.pointCount) <= points
                && Int(s.region) < regions && s.layer <= maxLayer
        }
        let layers = art.edgeLayers.map { min($0, maxLayer) }
        let factors = Self.weights(
            layers: layers + strokes.map(\.layer), strengths: art.edgeWeights + strokes.map(\.weight))
        edgeLayers = layers
        edgeWeights = Array(factors.prefix(layers.count))
        self.strokes = strokes
        strokeWeights = Array(factors.dropFirst(layers.count))
        strokePoints = art.strokePoints
        style = art.style
    }

    /// Whether a line of `layer` is part of the drawing (a coloring book draws these alike and
    /// nothing else).
    static func isDrawn(_ layer: UInt8) -> Bool { layer != LineLayer.color.rawValue }

    func points(of stroke: InteriorStroke) -> ArraySlice<SIMD2<Float>> {
        strokePoints[Int(stroke.pointStart)..<Int(stroke.pointStart + stroke.pointCount)]
    }

    /// Width factors for weighted line art: a line's strength over its layer's mean strength,
    /// kept within 0.6...1.4, so a layer's typical line keeps the layer's width and its strongest
    /// and weakest lines get heavier and lighter whatever range of strengths the layer covers.
    /// A layer whose strengths are all 0 draws evenly.
    static func weights(layers: [UInt8], strengths: [UInt8]) -> [Float] {
        let slots = Int(LineLayer.color.rawValue) + 1
        func slot(_ layer: UInt8) -> Int { min(Int(layer), slots - 1) }
        var sums = [Double](repeating: 0, count: slots), counts = [Int](repeating: 0, count: slots)
        for (layer, strength) in zip(layers, strengths) {
            sums[slot(layer)] += Double(strength)
            counts[slot(layer)] += 1
        }
        let means = (0..<slots).map { counts[$0] > 0 ? Float(sums[$0] / Double(counts[$0])) : 0 }
        return zip(layers, strengths).map { layer, strength in
            let mean = means[slot(layer)]
            return mean > 0 ? min(max(Float(strength) / mean, 0.6), 1.4) : 1
        }
    }
}

nonisolated extension LineAppearance {
    /// The appearance Settings › Advanced stored (`SettingsKey.lineAppearance`, written with
    /// `Preferences.store`), or the default when there is none or it can't be read. Safe off the
    /// main actor: images of layered paintings are drawn with it in the background.
    static func stored(in defaults: UserDefaults = .standard) -> LineAppearance {
        decoded(defaults.data(forKey: SettingsKey.lineAppearance))
    }

    /// An appearance stored as JSON, or the default.
    static func decoded(_ data: Data?) -> LineAppearance {
        data.flatMap { try? JSONDecoder().decode(LineAppearance.self, from: $0) } ?? .default
    }
}

/// What the outline pass draws for a template: a "line" per boundary edge, then one per interior
/// stroke, each with its two regions and its style, and a segment per step of every line's
/// polyline. A stroke has its region on both sides, which the shader reads as "inside a cell".
/// Classic templates get exactly the segments and regions they always had, every line in layer
/// 0 at weight 1.
nonisolated struct OutlineGeometry {
    /// Boundary points, then stroke points.
    let points: [SIMD2<Float>]
    /// (first point, line) per segment.
    let segments: [SIMD2<UInt32>]
    /// (left, right) region per line; `BoundaryEdge.outside` on the right of a canvas border edge.
    let lineRegions: [SIMD2<UInt32>]
    /// (layer, width factor) per line.
    let lineStyles: [SIMD2<Float>]
    /// True when the template has line art (drawn in layers, or as a coloring book).
    let isLayered: Bool
    /// How the template's line art is drawn; nil for classic templates.
    let lineArtStyle: TemplateLineArt.Style?

    init(_ t: Template) {
        let lines = DrawableLineArt(t)
        let strokes = lines?.strokes ?? []
        var segs: [SIMD2<UInt32>] = []
        segs.reserveCapacity(max(0, t.points.count - t.edges.count) + (lines?.strokePoints.count ?? 0))
        var regions: [SIMD2<UInt32>] = []
        regions.reserveCapacity(t.edges.count + strokes.count)
        var styles: [SIMD2<Float>] = []
        styles.reserveCapacity(t.edges.count + strokes.count)
        for (e, edge) in t.edges.enumerated() {
            regions.append(SIMD2(edge.left, edge.right))
            styles.append(lines.map { SIMD2(Float($0.edgeLayers[e]), $0.edgeWeights[e]) } ?? SIMD2(0, 1))
            guard edge.pointCount >= 2 else { continue }
            for k in 0..<(edge.pointCount - 1) { segs.append(SIMD2(edge.pointStart + k, UInt32(e))) }
        }
        var points = t.points
        if let lines {
            let base = UInt32(t.points.count)
            points.append(contentsOf: lines.strokePoints)
            for (s, stroke) in strokes.enumerated() {
                let line = UInt32(t.edges.count + s)
                regions.append(SIMD2(stroke.region, stroke.region))
                styles.append(SIMD2(Float(stroke.layer), lines.strokeWeights[s]))
                for k in 0..<(stroke.pointCount - 1) { segs.append(SIMD2(base + stroke.pointStart + k, line)) }
            }
        }
        self.points = points
        segments = segs
        lineRegions = regions
        lineStyles = styles
        isLayered = lines != nil
        lineArtStyle = lines?.style
    }
}
