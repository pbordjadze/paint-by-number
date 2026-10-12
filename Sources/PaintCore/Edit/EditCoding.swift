import Foundation

/// How an edit is kept in a file (the app's `refinements.json` lists them as `edits`), and the
/// shape `pbn edit` reads for the kinds both know: an object with a `kind` and its `points`, in
/// canvas units, plus what the kind needs.
///
///     {"kind": "draw",      "points": [[x, y], ...], "closed": false}
///     {"kind": "erase",     "points": [[x, y], ...], "radius": 4.5}
///     {"kind": "eraseLine", "points": [[x, y]],      "reach": 8}
///     {"kind": "fill",      "points": [[x, y]],      "color": [L, a, b]}
///
/// Versioning is by `kind` and by fields: a reader skips fields it does not know, and a kind it
/// does not know fails that one edit's decoding (a list of edits decodes each on its own and
/// leaves such an edit out). A new field gets a default that is what the kind did before it, so
/// files already written keep their meaning: never rename or repurpose a key or a kind. A missing
/// `closed` is false, a missing `radius` or `reach` the editor's own default (as `pbn edit`'s).
extension TemplateEditor.Edit: Codable {
    private enum CodingKeys: String, CodingKey { case kind, points, closed, radius, reach, color }

    /// The eraser's radius when a file gives none, canvas units (`pbn edit`'s default).
    static let defaultRadius: Float = 4

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(String.self, forKey: .kind)
        let points = try c.decode([SIMD2<Float>].self, forKey: .points)
        func point() throws -> SIMD2<Float> {
            guard let first = points.first else {
                throw DecodingError.dataCorruptedError(forKey: .points, in: c, debugDescription: "a \(kind) edit needs a point")
            }
            return first
        }
        switch kind {
        case "draw":
            self = .draw(points: points, closed: try c.decodeIfPresent(Bool.self, forKey: .closed) ?? false)
        case "erase":
            self = .erase(path: points, radius: try c.decodeIfPresent(Float.self, forKey: .radius) ?? Self.defaultRadius)
        case "eraseLine":
            self = .eraseLine(at: try point(), reach: try c.decodeIfPresent(Float.self, forKey: .reach) ?? TemplateEditor.tapReach)
        case "fill":
            let color = try c.decode([Float].self, forKey: .color)
            guard color.count == 3 else {
                throw DecodingError.dataCorruptedError(forKey: .color, in: c, debugDescription: "a color is [L, a, b]")
            }
            self = .fill(at: try point(), color: SIMD3(color[0], color[1], color[2]))
        default:
            throw DecodingError.dataCorruptedError(forKey: .kind, in: c, debugDescription: "unknown kind of edit: \(kind)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .draw(let points, let closed):
            try c.encode("draw", forKey: .kind)
            try c.encode(points, forKey: .points)
            try c.encode(closed, forKey: .closed)
        case .erase(let path, let radius):
            try c.encode("erase", forKey: .kind)
            try c.encode(path, forKey: .points)
            try c.encode(radius, forKey: .radius)
        case .eraseLine(let point, let reach):
            try c.encode("eraseLine", forKey: .kind)
            try c.encode([point], forKey: .points)
            try c.encode(reach, forKey: .reach)
        case .fill(let point, let color):
            try c.encode("fill", forKey: .kind)
            try c.encode([point], forKey: .points)
            try c.encode([color.x, color.y, color.z], forKey: .color)
        }
    }
}
