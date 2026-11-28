import Foundation

/// How an edit is kept in a file (the app's `refinements.json` lists them as `edits`), and the
/// shape `pbn edit` reads for the kinds both know: an object with a `kind` and its `points`, in
/// canvas units, plus what the kind needs.
///
///     {"kind": "draw",      "points": [[x, y], ...], "closed": false,
///                           "paints": [{"at": [x, y], "color": [L, a, b]}, ...], "asDrawn": true}
///     {"kind": "split",     "points": [[x, y], ...], "closed": false, "paints": [...]}
///     {"kind": "cellEdge",  "points": [[x, y], ...], "closed": false}
///     {"kind": "merge",     "points": [[x, y], ...]}
///     {"kind": "brush",     "points": [[x, y], ...], "radius": 6, "color": [L, a, b]}
///     {"kind": "reshape",   "points": [from, to],    "reach": 8, "target": "ink"}
///     {"kind": "moveLabel", "points": [from, to],    "reach": 8}
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
/// without the key. `asDrawn` is written only when true (every line Refine draws from editor 8):
/// a missing one is false, a draw nudged through the junctions it crosses beside, as every draw
/// with paints was before; an older reader skips it and lays the line nudged.
/// An older reader skips `paints` and lays such a draw as before, in the paints it had. `look` and
/// `repaint` (Refine's Looks and Edit Paint) have no points; an older reader leaves them, and a `paintArea`, out
/// of the list, and the painting it saved keeps their colors. A look's name is a
/// `TemplateEditor.Look`; one this build does not know fails the edit as an unknown kind does. A
/// missing `lightness` is none, a missing `family` false. An older reader leaves a `cellEdge` out
/// of the list too, and the cells it divided stay one; a `merge` too, and the cells it joined stay
/// apart, and a `brush`, whose paint the painting then lacks. A brush needs its `radius` and
/// `color`. A `reshape` needs its two points, where the line was grabbed and where it went; an
/// older reader leaves it out, and the line stays where it was; a `moveLabel` too (its two points,
/// the number's place and where it went), and the number stays where it was. A reshape's `target`
/// (a `TemplateEditor.ReshapeTarget` name, `ink` or `edge`) is written only when it grabs one
/// kind of line alone; a missing one is `any`, what every reshape grabbed before, and one this
/// build does not know fails the edit as an unknown look does. A missing `reach` of a
/// `moveLabel` is the editor's own, as a reshape's.
///
/// This is the one decoder of an edit, `pbn edit`'s too. Its edits.json may also name the color
/// of a fill, a paintArea or a brush by its paint's number (`"paint": n`, when it gives no
/// `"color"`), which only a decoder handed the palette reads (`paletteKey`): the app hands none,
/// and a `refinements.json` is read as ever.
extension TemplateEditor.Edit: Codable {
    /// The kinds of edit, by the names a file keeps them under (`"kind"`).
    public enum Kind: String, Sendable, CaseIterable {
        case draw, split, cellEdge, merge, brush, reshape, moveLabel, erase, eraseLine, fill, paintArea, look, repaint
    }

    public var kind: Kind {
        switch self {
        case .draw: .draw
        case .split: .split
        case .cellEdge: .cellEdge
        case .merge: .merge
        case .brush: .brush
        case .reshape: .reshape
        case .moveLabel: .moveLabel
        case .erase: .erase
        case .eraseLine: .eraseLine
        case .fill: .fill
        case .paintArea: .paintArea
        case .look: .look
        case .repaint: .repaint
        }
    }

    /// A decoder's `userInfo` key for the palette (`[PaletteColor]`) whose numbers a file's
    /// `"paint": n` names, 1 the first (`pbn edit`, which reads the palette of the template it
    /// edits).
    public static let paletteKey = CodingUserInfoKey(rawValue: "PaintCore.TemplateEditor.Edit.palette")!

    private enum CodingKeys: String, CodingKey {
        case kind, points, closed, radius, reach, color, paints, asDrawn, look, strength, lightness, from, family, target, paint
    }
    private enum PaintKeys: String, CodingKey { case at, color }

    /// The eraser's radius when a file gives none, canvas units (`pbn edit`'s default).
    static let defaultRadius: Float = 4

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kindName = try c.decode(String.self, forKey: .kind)
        guard let kind = Kind(rawValue: kindName) else {
            throw DecodingError.dataCorruptedError(forKey: .kind, in: c, debugDescription: "unknown kind of edit: \(kindName)")
        }
        let points = try c.decode([SIMD2<Float>].self, forKey: .points)
        func point() throws -> SIMD2<Float> {
            guard let first = points.first else {
                throw DecodingError.dataCorruptedError(forKey: .points, in: c, debugDescription: "a \(kind.rawValue) edit needs a point")
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
        /// The color of a fill, a paintArea or a brush: its `color`, else the paint its `paint`
        /// numbers in the palette the decoder was handed.
        func paint() throws -> SIMD3<Float> {
            guard !c.contains(.color), let palette = decoder.userInfo[Self.paletteKey] as? [PaletteColor],
                  let number = try c.decodeIfPresent(Int.self, forKey: .paint)
            else { return try lab(.color) }
            guard number >= 1, number <= palette.count else {
                throw DecodingError.dataCorruptedError(forKey: .paint, in: c, debugDescription: "there is no paint \(number)")
            }
            return palette[number - 1].oklab
        }
        switch kind {
        case .draw:
            self = .draw(
                points: points, closed: try c.decodeIfPresent(Bool.self, forKey: .closed) ?? false, paints: try decodePaints(),
                asDrawn: try c.decodeIfPresent(Bool.self, forKey: .asDrawn) ?? false)
        case .split:
            self = .split(
                points: points, closed: try c.decodeIfPresent(Bool.self, forKey: .closed) ?? false, paints: try decodePaints() ?? [])
        case .cellEdge:
            self = .cellEdge(points: points, closed: try c.decodeIfPresent(Bool.self, forKey: .closed) ?? false)
        case .merge:
            self = .merge(points: points)
        case .brush:
            self = .brush(path: points, radius: try c.decode(Float.self, forKey: .radius), color: try paint())
        case .reshape:
            guard points.count == 2 else {
                throw DecodingError.dataCorruptedError(forKey: .points, in: c, debugDescription: "a reshape is [from, to]")
            }
            var target = TemplateEditor.ReshapeTarget.any
            if let name = try c.decodeIfPresent(String.self, forKey: .target) {
                guard let known = TemplateEditor.ReshapeTarget(rawValue: name) else {
                    throw DecodingError.dataCorruptedError(forKey: .target, in: c, debugDescription: "unknown reshape target: \(name)")
                }
                target = known
            }
            self = .reshape(
                from: points[0], to: points[1], reach: try c.decodeIfPresent(Float.self, forKey: .reach) ?? TemplateEditor.tapReach,
                target: target)
        case .moveLabel:
            guard points.count == 2 else {
                throw DecodingError.dataCorruptedError(forKey: .points, in: c, debugDescription: "a moveLabel is [from, to]")
            }
            self = .moveLabel(
                from: points[0], to: points[1], reach: try c.decodeIfPresent(Float.self, forKey: .reach) ?? TemplateEditor.tapReach)
        case .erase:
            self = .erase(path: points, radius: try c.decodeIfPresent(Float.self, forKey: .radius) ?? Self.defaultRadius)
        case .eraseLine:
            self = .eraseLine(at: try point(), reach: try c.decodeIfPresent(Float.self, forKey: .reach) ?? TemplateEditor.tapReach)
        case .fill:
            self = .fill(at: try point(), color: try paint())
        case .paintArea:
            self = .paintArea(at: try point(), color: try paint())
        case .look:
            let name = try c.decode(String.self, forKey: .look)
            guard let look = TemplateEditor.Look(rawValue: name) else {
                throw DecodingError.dataCorruptedError(forKey: .look, in: c, debugDescription: "unknown look: \(name)")
            }
            self = .look(
                look, strength: try c.decode(Float.self, forKey: .strength),
                lightness: try c.decodeIfPresent([Float].self, forKey: .lightness) ?? [])
        case .repaint:
            self = .repaint(
                from: try lab(.from), to: try lab(.color), family: try c.decodeIfPresent(Bool.self, forKey: .family) ?? false)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(kind.rawValue, forKey: .kind)
        switch self {
        case .draw(let points, let closed, let paints, let asDrawn):
            try c.encode(points, forKey: .points)
            try c.encode(closed, forKey: .closed)
            if let paints { try encode(paints, in: &c) }
            if asDrawn { try c.encode(true, forKey: .asDrawn) }
        case .split(let points, let closed, let paints):
            try c.encode(points, forKey: .points)
            try c.encode(closed, forKey: .closed)
            try encode(paints, in: &c)
        case .cellEdge(let points, let closed):
            try c.encode(points, forKey: .points)
            try c.encode(closed, forKey: .closed)
        case .merge(let points):
            try c.encode(points, forKey: .points)
        case .brush(let path, let radius, let color):
            try c.encode(path, forKey: .points)
            try c.encode(radius, forKey: .radius)
            try c.encode([color.x, color.y, color.z], forKey: .color)
        case .reshape(let from, let to, let reach, let target):
            try c.encode([from, to], forKey: .points)
            try c.encode(reach, forKey: .reach)
            if target != .any { try c.encode(target.rawValue, forKey: .target) }
        case .moveLabel(let from, let to, let reach):
            try c.encode([from, to], forKey: .points)
            try c.encode(reach, forKey: .reach)
        case .erase(let path, let radius):
            try c.encode(path, forKey: .points)
            try c.encode(radius, forKey: .radius)
        case .eraseLine(let point, let reach):
            try c.encode([point], forKey: .points)
            try c.encode(reach, forKey: .reach)
        case .fill(let point, let color):
            try c.encode([point], forKey: .points)
            try c.encode([color.x, color.y, color.z], forKey: .color)
        case .paintArea(let point, let color):
            try c.encode([point], forKey: .points)
            try c.encode([color.x, color.y, color.z], forKey: .color)
        case .look(let look, let strength, let lightness):
            try c.encode([SIMD2<Float>](), forKey: .points)
            try c.encode(look, forKey: .look)
            try c.encode(strength, forKey: .strength)
            if !lightness.isEmpty { try c.encode(lightness, forKey: .lightness) }
        case .repaint(let from, let to, let family):
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
