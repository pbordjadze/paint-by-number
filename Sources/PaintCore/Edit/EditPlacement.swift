import Foundation

/// Edits carried onto a base made again (the app's re-makes: a slider moved, the text corrected,
/// a draft resumed): the painter's edits are where and what they were on the base they were
/// made on, and a new base can be another size (Detail sets the canvas) or, when the number of
/// paints changed, have other paints. `scaled(x:y:)` puts an edit where it was on a canvas of
/// another size; `repainting(_:)` sends a repaint of a paint that is gone to the paint that took
/// its place (`nearestPaints(from:to:)`). Neither is the editor's business: what a list of edits
/// makes of a given template is unchanged (`TemplateEditor.version`).
extension TemplateEditor.Edit {
    /// The edit on a canvas `x` times as wide and `y` times as tall: every point, and every
    /// reach and radius by the mean of the two (a canvas keeps its shape, so they are nearly one).
    /// Colors are unchanged. A factor that isn't finite and positive leaves the edit as it is.
    public func scaled(x: Float, y: Float) -> TemplateEditor.Edit {
        guard x.isFinite, y.isFinite, x > 0, y > 0, x != 1 || y != 1 else { return self }
        let factor = SIMD2(x, y), mean = (x + y) / 2
        func p(_ point: SIMD2<Float>) -> SIMD2<Float> { point * factor }
        func ps(_ points: [SIMD2<Float>]) -> [SIMD2<Float>] { points.map(p) }
        func paints(_ given: [TemplateEditor.Paint]) -> [TemplateEditor.Paint] {
            given.map { TemplateEditor.Paint(at: p($0.at), color: $0.color) }
        }
        switch self {
        case .draw(let points, let closed, let given):
            return .draw(points: ps(points), closed: closed, paints: given.map(paints))
        case .split(let points, let closed, let given):
            return .split(points: ps(points), closed: closed, paints: paints(given))
        case .cellEdge(let points, let closed):
            return .cellEdge(points: ps(points), closed: closed)
        case .merge(let points):
            return .merge(points: ps(points))
        case .brush(let path, let radius, let color):
            return .brush(path: ps(path), radius: radius * mean, color: color)
        case .reshape(let from, let to, let reach, let target):
            return .reshape(from: p(from), to: p(to), reach: reach * mean, target: target)
        case .moveLabel(let from, let to, let reach):
            return .moveLabel(from: p(from), to: p(to), reach: reach * mean)
        case .erase(let path, let radius):
            return .erase(path: ps(path), radius: radius * mean)
        case .eraseLine(let point, let reach):
            return .eraseLine(at: p(point), reach: reach * mean)
        case .fill(let point, let color):
            return .fill(at: p(point), color: color)
        case .paintArea(let point, let color):
            return .paintArea(at: p(point), color: color)
        case .look, .repaint:
            return self
        }
    }

    /// A repaint whose paint `colors` has another color for (OKLab, as a palette's paints) made of
    /// that paint instead; any other edit, and a repaint of a color not in `colors`, as it is.
    /// Looks are functions of a color and need no help.
    public func repainting(_ colors: [SIMD3<Float>: SIMD3<Float>]) -> TemplateEditor.Edit {
        guard case .repaint(let from, let to, let family) = self, let paint = colors[from], paint != from else { return self }
        return .repaint(from: paint, to: to, family: family)
    }

    /// Whether `repainting(_:)` changes it.
    public func isRepainted(by colors: [SIMD3<Float>: SIMD3<Float>]) -> Bool {
        guard case .repaint(let from, _, _) = self, let paint = colors[from] else { return false }
        return paint != from
    }
}

extension TemplateEditor {
    /// For each paint of `old` (OKLab), the paint of `new` nearest it (`ColorScience.distance`,
    /// the first of equals): where a repaint made on `old` goes on `new`, when the painter changed
    /// how many paints there are and the paints were chosen anew. Empty when `new` is.
    public static func nearestPaints(from old: [PaletteColor], to new: [PaletteColor]) -> [SIMD3<Float>: SIMD3<Float>] {
        guard !new.isEmpty else { return [:] }
        var map: [SIMD3<Float>: SIMD3<Float>] = [:]
        for paint in old where map[paint.oklab] == nil {
            var best = new[0].oklab, nearest = Float.infinity
            for candidate in new {
                let d = ColorScience.distance(paint.oklab, candidate.oklab)
                if d < nearest {
                    nearest = d
                    best = candidate.oklab
                }
            }
            map[paint.oklab] = best
        }
        return map
    }
}
