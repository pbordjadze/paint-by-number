import Foundation
import PaintCore

/// A reshape's `"target"`: any line without one; `what` names it in the failure for another name.
func reshapeTarget(_ name: String?, _ what: String) -> TemplateEditor.ReshapeTarget {
    guard let name else { return .any }
    guard let target = TemplateEditor.ReshapeTarget(rawValue: name) else { fail("\(what) \"target\" is any, ink or edge") }
    return target
}

/// `pbn edit`'s edits.json: an array of edits as the app's `refinements.json` keeps them, read by
/// the same decoder (`EditCoding`, whose doc comment lists each kind's fields and what a missing
/// one means), in canvas units. Two things are pbn's own: a fill, a paintArea or a brush may name
/// its color by `"paint"`, the paint's number in the template's palette, in place of `"color"`;
/// and a look without `"lightness"` reads it from the template it is laid on (`runEdit`). An edit
/// of a kind the decoder doesn't know is left out with a warning; one it knows and can't read (a
/// brush without its `"radius"`, a look without its `"strength"`, an edit without `"points"`,
/// which a look and a repaint give empty) fails the run.
func loadTemplateEdits(_ path: String, palette: [PaletteColor]) -> [TemplateEditor.Edit] {
    /// An entry of the file: the edit `EditCoding` reads of it, nil for a kind it doesn't know.
    struct Entry: Decodable {
        enum Keys: String, CodingKey { case kind }
        var kind: String
        var edit: TemplateEditor.Edit?

        init(from decoder: Decoder) throws {
            kind = try decoder.container(keyedBy: Keys.self).decode(String.self, forKey: .kind)
            edit = TemplateEditor.Edit.Kind(rawValue: kind) == nil ? nil : try TemplateEditor.Edit(from: decoder)
        }
    }
    guard let data = FileManager.default.contents(atPath: path) else { fail("cannot read \(path)") }
    let decoder = JSONDecoder()
    decoder.userInfo[TemplateEditor.Edit.paletteKey] = palette
    /// The edit an error is about, counted from 1.
    func which(_ context: DecodingError.Context) -> String {
        context.codingPath.first?.intValue.map { "edit \($0 + 1): " } ?? ""
    }
    let entries: [Entry]
    do {
        entries = try decoder.decode([Entry].self, from: data)
    } catch DecodingError.dataCorrupted(let context) {
        fail("\(path): \(which(context))\(context.debugDescription)")
    } catch DecodingError.keyNotFound(let key, let context) {
        fail("\(path): \(which(context))it has no \"\(key.stringValue)\"")
    } catch { fail("cannot decode \(path): \(error)") }
    let kinds = TemplateEditor.Edit.Kind.allCases.map(\.rawValue)
    return entries.compactMap { entry in
        if entry.edit == nil {
            FileHandle.standardError.write(Data(
                "\(path): skipping an edit of kind \(entry.kind) (\(kinds.dropLast().joined(separator: ", ")) or \(kinds.last ?? ""))\n".utf8))
        }
        return entry.edit
    }
}

/// `pbn edit`'s stats.json.
struct EditReport: Codable {
    struct Step: Codable {
        var kind: String
        var changed: Bool
        var declined: String?
        var lines: Int
        var joins: Int
        var regionsSplit: Int
        var regionsMerged: Int
        var detailAreas: Int
        var strokes: Int
        var erased: Int
        var fills: Int
        var paintsAdded: Int
        var tooSmall: Int
        /// Pieces a draw's paints gave another paint.
        var recolored: Int
        /// Paints a look or a repaint gave another color, and paints it made one with another.
        var paintsChanged: Int
        var paintsMerged: Int
        /// For a draw: the farthest the template's ink strays from the line in the middle of it
        /// (its interior vertices and the steps between them) and from its two end points, canvas
        /// units: an end joins the ink it is near.
        var maxDeviation: Float?
        var maxEndShift: Float?
        /// Regions this edit changed that it was not to (0): see `unexpectedChanges`.
        var unexpectedChanges: Int
        /// Time of the edit itself, with its check of the result.
        var milliseconds: Double
        /// Lines a reshape moved (its chain and the strokes it carried).
        var reshaped = 0
        /// Numbers a moveLabel moved.
        var labelsMoved = 0
    }
    var width: Int
    var height: Int
    var regions: Int
    var edges: Int
    var points: Int
    var triangles: Int
    var strokes: Int
    var palette: Int
    var detailRegions: Int
    var valid: Bool
    var validation: String
    var minLabelRadius: Float
    var labelsBelowLegibleSize: Int
    /// Regions of the template edited that the result holds as they were (outline, fill, numbers,
    /// paint, bit for bit), and the regions it changed or removed.
    var identicalRegions: Int
    var changedRegions: Int
    var steps: [Step]
    /// All the edits together.
    var milliseconds: Double
}

private func dot(_ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float { a.x * b.x + a.y * b.y }
private func norm(_ a: SIMD2<Float>) -> Float { dot(a, a).squareRoot() }

/// How far the ink of a template strays from a drawn line.
enum Deviation {
    /// The farthest the ink of `t` (drawn edges, strokes) is from the points of `line` the painter
    /// drew in the middle: its interior vertices and every step between them, so not the two
    /// steps at its ends, which turn to meet the ink their end joins; and how far its two end
    /// points are from the ink. Ink farther than a cell (16 units) counts as that far; points off
    /// the canvas are left out. Canvas units.
    static func measure(_ line: [SIMD2<Float>], in t: Template) -> (middle: Float, ends: Float) {
        let cell: Float = 16
        let columns = Int(Float(t.width) / cell) + 2, rows = Int(Float(t.height) / cell) + 2
        var segments: [(SIMD2<Float>, SIMD2<Float>)] = []
        var buckets = [[Int32]](repeating: [], count: columns * rows)
        forEachDrawnSegment(of: t) { a, b in
            let k = Int32(segments.count)
            segments.append((a, b))
            let x0 = max(Int(min(a.x, b.x) / cell), 0), x1 = min(Int(max(a.x, b.x) / cell), columns - 1)
            let y0 = max(Int(min(a.y, b.y) / cell), 0), y1 = min(Int(max(a.y, b.y) / cell), rows - 1)
            if x0 <= x1, y0 <= y1 { for y in y0...y1 { for x in x0...x1 { buckets[y * columns + x].append(k) } } }
        }
        func distance(_ p: SIMD2<Float>) -> Float? {
            guard p.x >= 0, p.y >= 0, p.x <= Float(t.width), p.y <= Float(t.height) else { return nil }
            var best = cell
            let cx = Int(p.x / cell), cy = Int(p.y / cell)
            for y in max(cy - 1, 0)...min(cy + 1, rows - 1) {
                for x in max(cx - 1, 0)...min(cx + 1, columns - 1) {
                    for k in buckets[y * columns + x] {
                        let (u, v) = segments[Int(k)]
                        let uv = v - u
                        let l2 = dot(uv, uv)
                        let q = l2 > 0 ? min(max(dot(p - u, uv) / l2, 0), 1) : 0
                        best = min(best, norm(p - (u + uv * q)))
                    }
                }
            }
            return best
        }
        var middle: Float = 0, ends: Float = 0
        for p in [line.first, line.last] { if let p, let d = distance(p) { ends = max(ends, d) } }
        if line.count >= 3 {
            for (k, (a, b)) in zip(line, line.dropFirst()).enumerated() where k >= 1 && k < line.count - 2 {
                let d = b - a
                let steps = max(1, Int((norm(d) * 8).rounded(.up)))
                for s in 0...steps { if let m = distance(a + d * (Float(s) / Float(steps))) { middle = max(middle, m) } }
            }
            for p in line[1..<(line.count - 1)] { if let m = distance(p) { middle = max(middle, m) } }
        }
        return (middle, ends)
    }
}

/// What of a region is its own: paint, outline, triangles, numbers, the strokes in it.
private struct RegionDigest: Equatable {
    var paint: SIMD3<Float>
    var detail: Bool
    var area: Float
    var bounds: PixelBounds
    var inscribedRadius: Float
    var rings: [[SIMD2<Float>]]
    var labels: [Label]
    var triangles: [[SIMD2<Float>]]
    var strokes: [[SIMD2<Float>]]

    init(_ t: Template, _ r: Int) {
        let region = t.regions[r]
        paint = t.palette[Int(region.colorIndex)].oklab
        detail = t.isDetailRegion(r)
        area = region.area
        bounds = region.bounds
        inscribedRadius = region.inscribedRadius
        rings = t.polygons(ofRegion: r)
        labels = t.labels(ofRegion: r).map { Label(position: $0.position, radius: $0.radius, region: 0) }
        triangles = stride(from: Int(region.indexStart), to: Int(region.indexStart + region.indexCount), by: 3).map { k in
            (0..<3).map { t.mesh.vertices[Int(t.mesh.indices[k + $0])] }
        }
        strokes = (t.lineArt?.strokes ?? []).filter { Int($0.region) == r }.map {
            Array(t.lineArt!.strokePoints[Int($0.pointStart)..<Int($0.pointStart + $0.pointCount)])
        }
    }
}

/// How many regions of `old` an edit changed that it should not have: neither among those
/// `outcome` names as touched, nor merged, nor beside one (a neighbour gains an outline vertex
/// where a line meets it, and is triangulated again).
private func unexpectedChanges(_ old: Template, _ new: Template, _ outcome: TemplateEditor.Outcome) -> Int {
    guard outcome.changed else { return 0 }
    var counts = [Int: Int]()
    for n in outcome.continued { counts[n, default: 0] += 1 }
    var near = Set(outcome.continued.indices.filter { outcome.touchedRegions.contains(outcome.continued[$0]) || counts[outcome.continued[$0]]! > 1 })
    for e in old.edges where e.right != BoundaryEdge.outside {
        if near.contains(Int(e.left)) { near.insert(Int(e.right)) }
        if near.contains(Int(e.right)) { near.insert(Int(e.left)) }
    }
    return old.regions.indices.filter { !near.contains($0) && RegionDigest(old, $0) != RegionDigest(new, outcome.continued[$0]) }.count
}

func runEdit(_ options: Options) throws {
    guard options.positional.count == 2, let out = options.out else {
        fail("usage: pbn edit <template.pbnt> <edits.json> --out <dir> [--photo <image>]")
    }
    guard let data = FileManager.default.contents(atPath: options.positional[0]) else { fail("cannot read \(options.positional[0])") }
    let before: Template
    do { before = try Template(encoded: data) } catch { fail("cannot decode \(options.positional[0]): \(error)") }
    let edits = loadTemplateEdits(options.positional[1], palette: before.palette)
    let photo = options.photo.map(loadImage)
    let outDir = URL(fileURLWithPath: out)
    try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

    var elapsed = Duration.zero
    // Laid as the app lays them (`EditTrail`): each edit brings its colors through the looks and
    // repaints made before it.
    var trail = EditTrail(base: before)
    var steps: [EditReport.Step] = []
    var continued = Array(0..<before.regions.count)
    for given in edits {
        let t = trail.template
        let began = ContinuousClock.now
        var edit = photo.map { TemplateEditor.painted(given, on: t, photo: $0) } ?? given
        if case .look(let look, let strength, let lightness) = edit, lightness.isEmpty {
            edit = TemplateEditor.look(look, strength: strength, on: t)
        }
        let laid = trail.lay(edit)
        if let failure = laid.failure { fail("cannot edit: \(failure)") }
        let result = (template: trail.template, outcome: laid.outcome)
        let took = ContinuousClock.now - began
        elapsed += took
        var step = EditReport.Step(
            kind: "", changed: result.outcome.changed, declined: result.outcome.declined?.description, lines: result.outcome.lines,
            joins: result.outcome.joins, regionsSplit: result.outcome.regionsSplit, regionsMerged: result.outcome.regionsMerged,
            detailAreas: result.outcome.detailAreas, strokes: result.outcome.strokes, erased: result.outcome.erased,
            fills: result.outcome.fills, paintsAdded: result.outcome.paintsAdded, tooSmall: result.outcome.tooSmall.count,
            recolored: result.outcome.recolored, paintsChanged: result.outcome.paintsChanged,
            paintsMerged: result.outcome.paintsMerged, unexpectedChanges: unexpectedChanges(t, result.template, result.outcome),
            milliseconds: Double(took.components.seconds) * 1000 + Double(took.components.attoseconds) / 1e15)
        step.kind = edit.kind.rawValue
        if case .draw(let points, let closed, _, _) = edit, result.outcome.changed {
            let line = closed ? points + [points[0]] : points
            let d = Deviation.measure(line.map { SIMD2(($0.x * 256).rounded() / 256, ($0.y * 256).rounded() / 256) }, in: result.template)
            step.maxDeviation = d.middle
            step.maxEndShift = d.ends
        }
        step.reshaped = result.outcome.reshaped
        step.labelsMoved = result.outcome.labelsMoved
        steps.append(step)
        continued = continued.map { $0 < result.outcome.continued.count ? result.outcome.continued[$0] : $0 }
    }
    let t = trail.template
    let milliseconds = Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15

    // Regions the edits left as they were: the same outline, fill, numbers and paint.
    var identical = 0
    var kept = Set<Int>()
    for r in before.regions.indices where !kept.contains(continued[r]) {
        if RegionDigest(before, r) == RegionDigest(t, continued[r]) {
            identical += 1
            kept.insert(continued[r])
        }
    }
    let report = t.validate(minLabelRadius: LabelSizing.minimumRadius)
    var belowLegible = 0
    for label in t.labels {
        let digits = LabelSizing.digitCount(colorIndex: t.regions[Int(label.region)].colorIndex)
        let detail = t.isDetailRegion(Int(label.region))
        if LabelSizing.fittedFontSize(radius: label.radius, digits: digits) < LabelSizing.minimumFontSize(detail: detail) - 1e-4 {
            belowLegible += 1
        }
    }
    let stats = EditReport(
        width: t.width, height: t.height, regions: t.regions.count, edges: t.edges.count, points: t.points.count,
        triangles: t.mesh.indices.count / 3, strokes: t.lineArt?.strokes.count ?? 0, palette: t.palette.count,
        detailRegions: t.detailRegions.count, valid: report.isValid, validation: report.description,
        minLabelRadius: t.labels.map(\.radius).min() ?? 0, labelsBelowLegibleSize: belowLegible, identicalRegions: identical,
        changedRegions: before.regions.count - identical, steps: steps, milliseconds: milliseconds)
    let json = try jsonEncoder().encode(stats)
    try json.write(to: outDir.appendingPathComponent("stats.json"))
    let encoded = t.encoded()
    try encoded.write(to: outDir.appendingPathComponent("template.pbnt"))
    try writePPM(paintedRaster(t), "raster.ppm", in: outDir)
    try writePPM(boundaryRaster(t), "boundaries.ppm", in: outDir)
    try writeSVGs(t, to: outDir)
    print(String(data: json, encoding: .utf8)!)
}
