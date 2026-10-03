import Foundation
import PaintCore

/// How layered line art is drawn at each zoom (Settings › Advanced › Line Appearance). Drawing
/// only: changing it never changes a template, so it applies to every layered painting at
/// once and previews instantly. Classic templates ignore it.
///
/// Each `LineLayer` has an opacity and a width at three zooms, where 1 is the painting fitted
/// to the canvas; values in between interpolate on log₂ of the zoom and hold beyond 1× and 4×.
/// Opacities are fractions of the paper's full ink, the darkest a classic line gets (zoomed in;
/// fitted, classic lines draw at 0.7 of it). Widths multiply the classic outline width at that
/// zoom, so 1 draws a line exactly as heavy as a classic template's. A layer also says how much
/// of its lines stays once the areas on both sides are painted (`painted`). Renderers apply it
/// through `LineStyle`; pictures (thumbnails, share images) show the 1× look.
nonisolated struct LineAppearance: Codable, Equatable, Sendable {
    struct Layer: Codable, Equatable, Sendable {
        /// Opacity at 1×, 2× and 4×.
        var opacity: [Float]
        /// Width factor at 1×, 2× and 4×.
        var width: [Float]
        /// How much of the layer's lines stays once the areas on both sides are painted (a
        /// stroke inside a cell: once its cell is), as a fraction of the opacity above: 0
        /// dissolves them, so finished areas read as paint; 1 keeps the drawing over the
        /// painting, as a coloring book does.
        var painted: Float

        init(opacity: [Float], width: [Float], painted: Float = 0) {
            self.opacity = opacity
            self.width = width
            self.painted = painted
        }

        private enum CodingKeys: String, CodingKey { case opacity, width, painted }

        /// `painted` is tolerant: appearances stored before it existed dissolve painted lines.
        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            opacity = try c.decode([Float].self, forKey: .opacity)
            width = try c.decode([Float].self, forKey: .width)
            guard opacity.count == 3, width.count == 3 else {
                throw DecodingError.dataCorruptedError(forKey: .opacity, in: c, debugDescription: "three zooms")
            }
            painted = LineAppearance.clamped((try? c.decodeIfPresent(Float.self, forKey: .painted)) ?? 0, to: 0...1)
        }

        func opacity(atZoom zoom: Float) -> Float { LineAppearance.interpolate(opacity, zoom: zoom) }
        func width(atZoom zoom: Float) -> Float { LineAppearance.interpolate(width, zoom: zoom) }

        /// Clamped copy: opacities and the painted fraction in 0...1, widths in the editor's range.
        var normalized: Layer {
            Layer(
                opacity: opacity.map { LineAppearance.clamped($0, to: 0...1) },
                width: width.map { LineAppearance.clamped($0, to: LineAppearance.widthRange) },
                painted: LineAppearance.clamped(painted, to: 0...1))
        }
    }

    var outline: Layer
    var detail: Layer
    var texture: Layer
    var color: Layer
    /// Weight lines within a layer by their edge's strength; off draws every line of a layer alike.
    var weighted: Bool

    /// The owner's picks from the layered-lines report: lines fade in by opacity at even weight,
    /// with outlines lighter and thinner than the research's (which drew them in solid ink about
    /// 2.8 times as wide as a classic line). Outlines take the full ink a classic line reaches
    /// zoomed in, a third wider, so the drawing reads at 1× where classic lines are lighter;
    /// the other layers are faint at 1× and come in by 4×. Every layer dissolves when painted,
    /// as classic lines do.
    static let `default` = LineAppearance(
        outline: Layer(opacity: [1, 1, 1], width: [1.3, 1.3, 1.35]),
        detail: Layer(opacity: [0.5, 0.8, 0.9], width: [0.95, 1, 1.05]),
        texture: Layer(opacity: [0.25, 0.55, 0.8], width: [0.8, 0.85, 0.95]),
        color: Layer(opacity: [0.15, 0.35, 0.55], width: [0.75, 0.8, 0.9]),
        weighted: false)

    /// The widths the editor offers, as factors of the classic line.
    static let widthRange: ClosedRange<Float> = 0.2...3

    subscript(layer: LineLayer) -> Layer {
        get {
            switch layer {
            case .outline: outline
            case .detail: detail
            case .texture: texture
            case .color: color
            }
        }
        set {
            switch layer {
            case .outline: outline = newValue
            case .detail: detail = newValue
            case .texture: texture = newValue
            case .color: color = newValue
            }
        }
    }

    /// The zooms the three values of every layer belong to.
    static let zooms: [Float] = [1, 2, 4]

    static func interpolate(_ values: [Float], zoom: Float) -> Float {
        guard values.count == 3 else { return values.first ?? 1 }
        let t = min(max(log2(max(zoom, 1e-3)), 0), 2)
        let i = min(Int(t), 1), f = t - Float(i)
        return values[i] + (values[i + 1] - values[i]) * f
    }

    /// `value` within `range`; a value that is no number becomes the range's lower bound.
    static func clamped(_ value: Float, to range: ClosedRange<Float>) -> Float {
        value.isFinite ? min(max(value, range.lowerBound), range.upperBound) : range.lowerBound
    }

    /// Every layer clamped (`Layer.normalized`): what pasted settings are taken as.
    var normalized: LineAppearance {
        LineAppearance(
            outline: outline.normalized, detail: detail.normalized, texture: texture.normalized, color: color.normalized,
            weighted: weighted)
    }

    private enum CodingKeys: String, CodingKey { case outline, detail, texture, color, weighted }

    init(outline: Layer, detail: Layer, texture: Layer, color: Layer, weighted: Bool) {
        self.outline = outline
        self.detail = detail
        self.texture = texture
        self.color = color
        self.weighted = weighted
    }

    /// Tolerant: a missing or malformed layer falls back to its default.
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = LineAppearance.default
        outline = (try? c.decodeIfPresent(Layer.self, forKey: .outline)) ?? d.outline
        detail = (try? c.decodeIfPresent(Layer.self, forKey: .detail)) ?? d.detail
        texture = (try? c.decodeIfPresent(Layer.self, forKey: .texture)) ?? d.texture
        color = (try? c.decodeIfPresent(Layer.self, forKey: .color)) ?? d.color
        weighted = (try? c.decodeIfPresent(Bool.self, forKey: .weighted)) ?? d.weighted
    }
}
