import Foundation
import PaintCore

/// How layered line art is drawn at each zoom (Settings › Advanced › Line Appearance). Drawing
/// only: changing it never changes a template, so it applies to every layered painting at
/// once and previews instantly. Classic templates ignore it.
///
/// Each `LineLayer` has an opacity and a width at three zooms, where 1 is the painting fitted
/// to the canvas; values in between interpolate on log₂ of the zoom and hold beyond 1× and 4×.
/// Widths multiply the classic outline width at that zoom, so 1 draws a line exactly as heavy
/// as a classic template's.
nonisolated struct LineAppearance: Codable, Equatable, Sendable {
    struct Layer: Codable, Equatable, Sendable {
        /// Opacity at 1×, 2× and 4×.
        var opacity: [Float]
        /// Width factor at 1×, 2× and 4×.
        var width: [Float]

        init(opacity: [Float], width: [Float]) {
            self.opacity = opacity
            self.width = width
        }

        private enum CodingKeys: String, CodingKey { case opacity, width }

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            opacity = try c.decode([Float].self, forKey: .opacity)
            width = try c.decode([Float].self, forKey: .width)
            guard opacity.count == 3, width.count == 3 else {
                throw DecodingError.dataCorruptedError(forKey: .opacity, in: c, debugDescription: "three zooms")
            }
        }

        func opacity(atZoom zoom: Float) -> Float { LineAppearance.interpolate(opacity, zoom: zoom) }
        func width(atZoom zoom: Float) -> Float { LineAppearance.interpolate(width, zoom: zoom) }
    }

    var outline: Layer
    var detail: Layer
    var texture: Layer
    var color: Layer
    /// Weight lines within a layer by their edge's strength; off draws every line of a layer alike.
    var weighted: Bool

    /// The owner's picks from the layered-lines report: lines fade in by opacity at even weight,
    /// with outlines lighter and thinner than the research's.
    static let `default` = LineAppearance(
        outline: Layer(opacity: [0.85, 0.9, 0.95], width: [1.15, 1.2, 1.25]),
        detail: Layer(opacity: [0.45, 0.8, 0.9], width: [0.9, 1, 1.05]),
        texture: Layer(opacity: [0.2, 0.5, 0.8], width: [0.75, 0.85, 0.95]),
        color: Layer(opacity: [0.12, 0.3, 0.5], width: [0.7, 0.8, 0.9]),
        weighted: false)

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
