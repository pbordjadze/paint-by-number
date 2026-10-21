import Foundation

/// How an edit is kept in a file (the app's `refinements.json` lists them as `edits`), and the
/// shape `pbn edit` reads for the kinds both know: an object with a `kind` and its `points`, in
/// canvas units, plus what the kind needs.
///
///     {"kind": "draw",      "points": [[x, y], ...], "closed": false,
///                           "paints": [{"at": [x, y], "color": [L, a, b]}, ...]}
///     {"kind": "split",     "points": [[x, y], ...], "closed": false, "paints": [...]}
///     {"kind": "cellEdge",  "points": [[x, y], ...], "closed": false}
///     {"kind": "merge",     "points": [[x, y], ...]}
///     {"kind": "erase",     "points": [[x, y], ...], "radius": 4.5}
///     {"kind": "eraseLine", "points": [[x, y]],      "reach": 8}
///     {"kind": "fill",      "points": [[x, y]],      "color": [L, a, b]}
///     {"kind": "paintArea", "points": [[x, y]],      "color": [L, a, b]}
///     {"kind": "look",      "points": [], "look": "moonlit", "strength": 1, "lightness": [L, ...]}
///     {"kind": "repaint",   "points": [], "from": [L, a, b], "color": [L, a, b], "family": true}
///
/// Versioning is by `kind` and by fields: a reader skips fields it does not know, and a kind it
/// does not know fails that one edit's decoding (a list of edits decodes each on its own and
/// leaves such an edit out). A new field gets a default that is what the kind did before it, so
/// files already written keep their meaning: never rename or repurpose a key or a kind. A missing
/// `closed` is false, a missing `radius` or `reach` the editor's own default (as `pbn edit`'s). A
/// missing `paints` is a draw from before lines took the photo's colors (`TemplateEditor.Edit.draw`,
/// nil): such a draw is written without the key, as it always was. A draw with a list writes it,
/// empty too (`[]`), which reads back as a draw with no paints to give: it lays nudged, unlike one
/// without the key.
/// An older reader skips `paints` and lays such a draw as before, in the paints it had. `look` and
/// `repaint` (Refine's Colors) have no points; an older reader leaves them, and a `paintArea`, out
/// of the list, and the painting it saved keeps their colors. A look's name is a
/// `TemplateEditor.Look`; one this build does not know fails the edit as an unknown kind does. A
/// missing `lightness` is none, a missing `family` false. An older reader leaves a `cellEdge` out
/// of the list too, and the cells it divided stay one; a `merge` too, and the cells it joined stay
/// apart.
extension TemplateEditor.Edit: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind, points, closed, radius, reach, color, paints, look, strength, lightness, from, family
    }
    private enum PaintKeys: String, CodingKey { case at, color }

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
        /// A draw's or a split's paints; nil when the file gives none.
        func decodePaints() throws -> [TemplateEditor.Paint]? {
            guard c.contains(.paints) else { return nil }
            var list = try c.nestedUnkeyedContainer(forKey: .paints)
            var decoded: [TemplateEditor.Paint] = []
            while !list.isAtEnd {
                let p = try list.nestedContainer(keyedBy: PaintKeys.self)
                let at = try p.decode(SIMD2<Float>.self, forKey: .at)
                let color = try p.decode([Float].self, forKey: .color)
                guard color.count == 3 else {
                    throw DecodingError.dataCorruptedError(forKey: .color, in: p, debugDescription: "a color is [L, a, b]")
                }
                decoded.append(TemplateEditor.Paint(at: at, color: SIMD3(color[0], color[1], color[2])))
            }
            return decoded
        }
        func lab(_ key: CodingKeys) throws -> SIMD3<Float> {
            let color = try c.decode([Float].self, forKey: key)
            guard color.count == 3 else {
                throw DecodingError.dataCorruptedError(forKey: key, in: c, debugDescription: "a color is [L, a, b]")
            }
            return SIMD3(color[0], color[1], color[2])
        }
        switch kind {
        case "draw":
            self = .draw(points: points, closed: try c.decodeIfPresent(Bool.self, forKey: .closed) ?? false, paints: try decodePaints())
        case "split":
            self = .split(
                points: points, closed: try c.decodeIfPresent(Bool.self, forKey: .closed) ?? false, paints: try decodePaints() ?? [])
        case "cellEdge":
            self = .cellEdge(points: points, closed: try c.decodeIfPresent(Bool.self, forKey: .closed) ?? false)
        case "merge":
            self = .merge(points: points)
        case "erase":
            self = .erase(path: points, radius: try c.decodeIfPresent(Float.self, forKey: .radius) ?? Self.defaultRadius)
        case "eraseLine":
            self = .eraseLine(at: try point(), reach: try c.decodeIfPresent(Float.self, forKey: .reach) ?? TemplateEditor.tapReach)
        case "fill":
            self = .fill(at: try point(), color: try lab(.color))
        case "paintArea":
            self = .paintArea(at: try point(), color: try lab(.color))
        case "look":
            let name = try c.decode(String.self, forKey: .look)
            guard let look = TemplateEditor.Look(rawValue: name) else {
                throw DecodingError.dataCorruptedError(forKey: .look, in: c, debugDescription: "unknown look: \(name)")
            }
            self = .look(
                look, strength: try c.decode(Float.self, forKey: .strength),
                lightness: try c.decodeIfPresent([Float].self, forKey: .lightness) ?? [])
        case "repaint":
            self = .repaint(
                from: try lab(.from), to: try lab(.color), family: try c.decodeIfPresent(Bool.self, forKey: .family) ?? false)
        default:
            throw DecodingError.dataCorruptedError(forKey: .kind, in: c, debugDescription: "unknown kind of edit: \(kind)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .draw(let points, let closed, let paints):
            try c.encode("draw", forKey: .kind)
            try c.encode(points, forKey: .points)
            try c.encode(closed, forKey: .closed)
            if let paints { try encode(paints, in: &c) }
        case .split(let points, let closed, let paints):
            try c.encode("split", forKey: .kind)
            try c.encode(points, forKey: .points)
            try c.encode(closed, forKey: .closed)
            try encode(paints, in: &c)
        case .cellEdge(let points, let closed):
            try c.encode("cellEdge", forKey: .kind)
            try c.encode(points, forKey: .points)
            try c.encode(closed, forKey: .closed)
        case .merge(let points):
            try c.encode("merge", forKey: .kind)
            try c.encode(points, forKey: .points)
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
        case .paintArea(let point, let color):
            try c.encode("paintArea", forKey: .kind)
            try c.encode([point], forKey: .points)
            try c.encode([color.x, color.y, color.z], forKey: .color)
        case .look(let look, let strength, let lightness):
            try c.encode("look", forKey: .kind)
            try c.encode([SIMD2<Float>](), forKey: .points)
            try c.encode(look, forKey: .look)
            try c.encode(strength, forKey: .strength)
            if !lightness.isEmpty { try c.encode(lightness, forKey: .lightness) }
        case .repaint(let from, let to, let family):
            try c.encode("repaint", forKey: .kind)
            try c.encode([SIMD2<Float>](), forKey: .points)
            try c.encode([from.x, from.y, from.z], forKey: .from)
            try c.encode([to.x, to.y, to.z], forKey: .color)
            try c.encode(family, forKey: .family)
        }
    }

    private func encode(_ paints: [TemplateEditor.Paint], in c: inout KeyedEncodingContainer<CodingKeys>) throws {
        var list = c.nestedUnkeyedContainer(forKey: .paints)
        for paint in paints {
            var p = list.nestedContainer(keyedBy: PaintKeys.self)
            try p.encode(paint.at, forKey: .at)
            try p.encode([paint.color.x, paint.color.y, paint.color.z], forKey: .color)
        }
    }
}
