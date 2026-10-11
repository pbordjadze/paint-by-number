import Foundation

public enum PropKind: String, Codable, Sendable, CaseIterable {
    case broom, brush, mortar, jar
    /// Shares of standing height, independent of spec normalization and bounce.
    var length: Double {
        switch self { case .broom: 0.70; case .brush: 0.50; case .mortar: 0.24; case .jar: 0.22 }
    }
    /// Attachment distance from the drawn base, in standing figure heights.
    var gripOffset: Double {
        switch self { case .brush: 0.08; case .broom: 0.18; case .mortar, .jar: 0 }
    }
}

public struct HeldProp: Codable, Sendable {
    public var kind: PropKind, grips: [String: Point], base: Point, axis: Point
    public var tip: Point

    /// Use the same affine base/axis as the renderer, independently of recorded grips.
    func renderedGrips(height: Double, twoHanded: Bool) -> [String: Point] {
        var result = ["right": base + axis * (kind.gripOffset * height)]
        if twoHanded { result["left"] = base + axis * ((kind.gripOffset - 0.12) * height) }
        return result
    }
}

extension InkRenderer {
    /// Local +y runs from the handle/base toward the working end. Affine axes preserve the
    /// projected forearm direction and the exact grip, including at zero view depth.
    func prop(_ kind: PropKind, base: Point, axis: Point, at time: Double, stream: UInt64) -> InkDrawing {
        let length = kind.length * (unit / spec.normalizationScale)
        let normal = axis.unit.normal
        func point(_ x: Double, _ y: Double) -> Point { base + normal * (x * length) + axis * (y * length) }
        var result = InkDrawing(), serial: UInt64 = 0
        func line(_ coordinates: [Point], closed: Bool = false) {
            let points = coordinates.map { point($0.x, $0.y) }
            let boil = UInt64(max(0, floor(time * spec.ink.boilFps)))
            let drawing = outline(points, seed: streamSeed(seed, stream + serial, boil), closed: closed)
            result.shapes.append(drawing.shape); result.minimumWidth = min(result.minimumWidth, drawing.minimumWidth)
            serial += 1
        }
        switch kind {
        case .broom:
            line([Point(0, 0), Point(0, 0.80)])
            line([Point(-0.08, 0.77), Point(0.08, 0.77)])
            for i in -3...3 { line([Point(Double(i) * 0.017, 0.77), Point(Double(i) * 0.05, 1)]) }
        case .brush:
            line([Point(0, 0), Point(0, 0.70)])
            line([Point(-0.045, 0.70), Point(0.045, 0.70), Point(0.045, 0.83), Point(-0.045, 0.83)], closed: true)
            line([Point(-0.045, 0.83), Point(0, 1), Point(0.045, 0.83)], closed: true)
        case .mortar:
            line([Point(-0.5, 0), Point(-0.36, 0.42), Point(0, 0.53), Point(0.36, 0.42), Point(0.5, 0)], closed: true)
            line([Point(-0.50, 0), Point(0.50, 0)])
            line([Point(0.12, 0.18), Point(0.30, -0.52)])
        case .jar:
            line([Point(-0.20, 0), Point(-0.20, 0.20), Point(-0.36, 0.32), Point(-0.36, 0.90),
                  Point(-0.25, 1), Point(0.25, 1), Point(0.36, 0.90), Point(0.36, 0.32), Point(0.20, 0.20), Point(0.20, 0)], closed: true)
            line([Point(-0.25, 0.08), Point(0.25, 0.08)])
        }
        return result
    }

    func heldProp(_ held: HeldProp, at time: Double) -> InkDrawing {
        prop(held.kind, base: held.base, axis: held.axis, at: time, stream: 200)
    }

    /// The stroke uses path vertices, rather than chords across curves. Noise has a fixed
    /// action seed so ink already laid down is stationary throughout later actions.
    func laidInk(_ rig: Rig, at time: Double) -> InkDrawing {
        let quantum = (spec.motion.onTwos ? 2.0 : 1.0) / Double(spec.motion.fps)
        let t = floor(max(0, time) / quantum + 1e-9) * quantum
        var drawing = InkDrawing()
        for (i, action) in rig.actions.enumerated() where action.timing.kind == "ink" && t >= action.timing.start {
            let distance = action.travelled(t - action.timing.start)
            guard distance > 1e-9, let path = action.path else { continue }
            let end = mix(action.from, action.to, distance / action.distance)
            let low = min(action.from, end) * path.length, high = max(action.from, end) * path.length
            var points = [path.sample(action.from).point]
            let vertices = path.points.indices.filter { path.lengths[$0] > low && path.lengths[$0] < high }
            for index in (end < action.from ? Array(vertices.reversed()) : vertices) { points.append(path.points[index]) }
            points.append(path.sample(end).point)
            let stroke = outline(points, seed: streamSeed(seed, 400, UInt64(i)), closed: false)
            drawing.shapes.append(stroke.shape); drawing.minimumWidth = min(drawing.minimumWidth, stroke.minimumWidth)
        }
        return drawing
    }
}
