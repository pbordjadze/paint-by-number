import CoreGraphics
import Foundation
import PaintCore

/// The pen's line as Refine keeps it: a finger's samples smoothed into curves (quadratics
/// through the midpoints between samples, so the corners of a shaky hand round off the way they
/// do on the screen while it draws) and thinned to the points that shape them.
nonisolated enum PenPath {
    /// The smoothed path through `points`, sampled every `spacing` (the points' units).
    static func smoothed(_ points: [CGPoint], spacing: CGFloat) -> [CGPoint] {
        guard points.count > 2, spacing > 0 else { return points }
        var out = [points[0]]
        var start = points[0]
        for k in 1..<(points.count - 1) {
            let control = points[k]
            let end = k == points.count - 2 ? points[k + 1] : midpoint(points[k], points[k + 1])
            let length = distance(start, control) + distance(control, end)
            let steps = max(1, Int((length / spacing).rounded(.up)))
            for s in 1...steps {
                let t = CGFloat(s) / CGFloat(steps), u = 1 - t
                out.append(CGPoint(
                    x: u * u * start.x + 2 * u * t * control.x + t * t * end.x,
                    y: u * u * start.y + 2 * u * t * control.y + t * t * end.y))
            }
            start = end
        }
        return out
    }

    /// The path drawn on screen for `points`, the same curves `smoothed` samples.
    static func path(_ points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        guard let first = points.first else { return path }
        path.move(to: first)
        guard points.count > 2 else {
            path.addLine(to: points.last ?? first)
            return path
        }
        for k in 1..<(points.count - 1) {
            let end = k == points.count - 2 ? points[k + 1] : midpoint(points[k], points[k + 1])
            path.addQuadCurve(to: end, control: points[k])
        }
        return path
    }

    /// The points that keep the line within `tolerance` of itself (Ramer–Douglas–Peucker).
    static func simplified(_ points: [CGPoint], tolerance: CGFloat) -> [CGPoint] {
        guard points.count > 2 else { return points }
        var keep = [Bool](repeating: false, count: points.count)
        keep[0] = true
        keep[points.count - 1] = true
        var stack = [(0, points.count - 1)]
        while let (i, j) = stack.popLast() {
            guard j > i + 1 else { continue }
            var farthest = i, most: CGFloat = 0
            for k in (i + 1)..<j {
                let d = segmentDistance(points[k], points[i], points[j])
                if d > most {
                    most = d
                    farthest = k
                }
            }
            if most > tolerance {
                keep[farthest] = true
                stack.append((i, farthest))
                stack.append((farthest, j))
            }
        }
        return points.indices.filter { keep[$0] }.map { points[$0] }
    }

    static func length(_ points: [CGPoint]) -> CGFloat {
        zip(points, points.dropFirst()).reduce(0) { $0 + distance($1.0, $1.1) }
    }

    static func midpoint(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2) }

    static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }

    /// The distance from `p` to the segment `a`–`b`.
    static func segmentDistance(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let ab = CGPoint(x: b.x - a.x, y: b.y - a.y)
        let length = ab.x * ab.x + ab.y * ab.y
        let t = length > 0 ? min(max(((p.x - a.x) * ab.x + (p.y - a.y) * ab.y) / length, 0), 1) : 0
        return distance(p, CGPoint(x: a.x + ab.x * t, y: a.y + ab.y * t))
    }
}

/// The help the pens give a line once it's smoothed (`PenPath`), in one space (the template's
/// canvas units): the Smart Pen straightens a line that runs nearly straight, and both pens move
/// an end onto a line it comes near (`SnapLines`), the Smart Pen from much farther.
nonisolated enum PenAssist {
    /// A line runs nearly straight when no point strays from its chord by more than this share
    /// of the chord (or a floor the caller gives for short strokes): an arc bulges by about an
    /// eighth of its turn (in radians) times its chord, so one turning more than 16° isn't.
    static let straightness: CGFloat = 0.035
    /// A line's end at a line's end (a break in it, or where it stops) counts as this much
    /// nearer than a point along a line: a short stroke across a break joins the two ends.
    static let endPreference: CGFloat = 0.5

    /// The farthest any point lies from the segment between the first and the last.
    static func deviation(_ points: [CGPoint]) -> CGFloat {
        guard let a = points.first, let b = points.last else { return 0 }
        return points.reduce(0) { max($0, PenPath.segmentDistance($1, a, b)) }
    }

    /// Whether `points` run nearly straight: no point farther from the chord than `straightness`
    /// of its length (or `floor`, if more), and the line no longer than the chord by more than
    /// twice that, so a stroke that doubles back along itself isn't.
    static func isNearlyStraight(_ points: [CGPoint], floor: CGFloat) -> Bool {
        guard let a = points.first, let b = points.last else { return false }
        let chord = PenPath.distance(a, b)
        guard chord > 0 else { return false }
        let tolerance = max(straightness * chord, floor)
        return deviation(points) <= tolerance && PenPath.length(points) <= chord + 2 * tolerance
    }

    /// `line`'s ends moved onto `lines` where they come within `reach`: onto a line's end when
    /// `preferringEnds` (`SnapLines.join`; the line's own start too, for an end that closes a
    /// loop), else onto the nearest point. A straight line moves its two ends; otherwise each
    /// move eases in over `reach` of the line (half the line, if shorter), which the rest keeps.
    /// Returns the line and the points its ends joined. A line the moves would fold to under
    /// half its length keeps only its start's.
    static func joined(
        _ line: [CGPoint], to lines: SnapLines, reach: CGFloat, preferringEnds: Bool, straight: Bool
    ) -> (line: [CGPoint], joins: [CGPoint]) {
        guard line.count >= 2, reach > 0 else { return (line, []) }
        let length = PenPath.length(line)
        let span = min(reach, length / 2)
        func target(for p: CGPoint, ends: [CGPoint]) -> CGPoint? {
            preferringEnds ? lines.join(for: p, within: reach, ends: ends) : lines.nearestPoint(to: p, within: reach)
        }
        func move(_ points: [CGPoint], atStart: Bool, to target: CGPoint) -> [CGPoint] {
            guard straight else { return moving(points, atStart: atStart, to: target, span: span) }
            var points = points
            points[atStart ? 0 : points.count - 1] = target
            return points
        }
        var out = line
        var joins: [CGPoint] = []
        if let start = target(for: line[0], ends: []) {
            out = move(out, atStart: true, to: start)
            joins.append(start)
        }
        let started = out
        // The line may close on its own start, if it's long enough to make a loop.
        let own = length >= 3 * reach ? [out[0]] : []
        if let end = target(for: line[line.count - 1], ends: own) {
            out = move(out, atStart: false, to: end)
            if PenPath.length(out) >= length / 2 {
                joins.append(end)
            } else {
                out = started
            }
        }
        return (out, joins)
    }

    /// `points` with an end (the first, or the last) moved to `target`, the move easing in over
    /// `span` of the line from that end: all of it at the end, none `span` along, where a point
    /// is added if none lies there, so the line before it stays as it was.
    static func moving(_ points: [CGPoint], atStart: Bool, to target: CGPoint, span: CGFloat) -> [CGPoint] {
        guard points.count >= 2 else { return points }
        let p = atStart ? Array(points.reversed()) : points
        let n = p.count
        let offset = CGPoint(x: target.x - p[n - 1].x, y: target.y - p[n - 1].y)
        // Each point's distance along the line from the end.
        var along = [CGFloat](repeating: 0, count: n)
        for i in stride(from: n - 2, through: 0, by: -1) { along[i] = along[i + 1] + PenPath.distance(p[i], p[i + 1]) }
        func shifted(_ q: CGPoint, _ d: CGFloat) -> CGPoint {
            let w = span > 0 ? max(0, 1 - d / span) : (d == 0 ? 1 : 0)
            return CGPoint(x: q.x + offset.x * w, y: q.y + offset.y * w)
        }
        var out: [CGPoint] = []
        for i in 0..<n {
            if i > 0, along[i - 1] > span, along[i] < span {
                let t = (along[i - 1] - span) / (along[i - 1] - along[i])
                out.append(CGPoint(x: p[i - 1].x + (p[i].x - p[i - 1].x) * t, y: p[i - 1].y + (p[i].y - p[i - 1].y) * t))
            }
            out.append(shifted(p[i], along[i]))
        }
        return atStart ? out.reversed() : out
    }
}

/// The lines on screen a pen's end may meet, in the template's canvas units: the drawing's
/// lines, those drawn since, less what was erased since; with the ends where a line stops
/// rather than goes on into another (a break in a line, or a line ending in the open).
nonisolated struct SnapLines {
    nonisolated struct Line {
        let points: [CGPoint]
        let bounds: CGRect
    }

    let lines: [Line]
    let ends: [CGPoint]

    init(_ polylines: [[CGPoint]]) {
        var lines: [Line] = []
        var count: [Key: Int] = [:]
        for points in polylines where points.count >= 2 {
            var low = points[0], high = points[0]
            for p in points {
                low = CGPoint(x: min(low.x, p.x), y: min(low.y, p.y))
                high = CGPoint(x: max(high.x, p.x), y: max(high.y, p.y))
            }
            lines.append(Line(points: points, bounds: CGRect(x: low.x, y: low.y, width: high.x - low.x, height: high.y - low.y)))
            count[Key(points[0]), default: 0] += 1
            count[Key(points[points.count - 1]), default: 0] += 1
        }
        self.lines = lines
        ends = lines.flatMap { [$0.points[0], $0.points[$0.points.count - 1]] }.filter { count[Key($0)] == 1 }
    }

    /// A point to a 64th of a unit, so lines that meet share their ends exactly.
    nonisolated private struct Key: Hashable {
        let x: Int, y: Int
        init(_ p: CGPoint) {
            x = Int((p.x * 64).rounded())
            y = Int((p.y * 64).rounded())
        }
    }

    /// `polylines` less their points within reach of an erasure (its path and radius), split
    /// there; near one their segments are measured every unit, so a pass between two of a line's
    /// points cuts it too.
    static func erasing(_ polylines: [[CGPoint]], by erasures: [(path: [CGPoint], radius: CGFloat)]) -> [[CGPoint]] {
        guard !erasures.isEmpty else { return polylines }
        let reaches = erasures.map { erasure -> CGRect in
            let xs = erasure.path.map(\.x), ys = erasure.path.map(\.y)
            return CGRect(
                x: (xs.min() ?? 0) - erasure.radius, y: (ys.min() ?? 0) - erasure.radius,
                width: (xs.max() ?? 0) - (xs.min() ?? 0) + 2 * erasure.radius,
                height: (ys.max() ?? 0) - (ys.min() ?? 0) + 2 * erasure.radius)
        }
        func erased(_ p: CGPoint) -> Bool {
            for (erasure, reach) in zip(erasures, reaches) where reach.contains(p) {
                let path = erasure.path
                if path.count == 1 {
                    if PenPath.distance(p, path[0]) <= erasure.radius { return true }
                    continue
                }
                for (a, b) in zip(path, path.dropFirst()) where PenPath.segmentDistance(p, a, b) <= erasure.radius { return true }
            }
            return false
        }
        var out: [[CGPoint]] = []
        for line in polylines {
            var piece: [CGPoint] = []
            func keep(_ p: CGPoint) {
                if erased(p) {
                    if piece.count >= 2 { out.append(piece) }
                    piece = []
                } else {
                    piece.append(p)
                }
            }
            for (k, p) in line.enumerated() {
                if k > 0 {
                    let a = line[k - 1]
                    let box = CGRect(x: min(a.x, p.x), y: min(a.y, p.y), width: abs(p.x - a.x), height: abs(p.y - a.y))
                        .insetBy(dx: -1, dy: -1)
                    let steps = Int(PenPath.distance(a, p).rounded(.up))
                    // A unit at a time near an erasure; elsewhere the line's own points do.
                    if steps > 1, reaches.contains(where: { $0.intersects(box) }) {
                        for s in 1..<steps {
                            let t = CGFloat(s) / CGFloat(steps)
                            keep(CGPoint(x: a.x + (p.x - a.x) * t, y: a.y + (p.y - a.y) * t))
                        }
                    }
                }
                keep(p)
            }
            if piece.count >= 2 { out.append(piece) }
        }
        return out
    }

    /// The point on a line nearest `p`, if one lies within `reach`.
    func nearestPoint(to p: CGPoint, within reach: CGFloat) -> CGPoint? {
        var best: (point: CGPoint, distance: CGFloat)?
        for line in lines where line.bounds.insetBy(dx: -reach, dy: -reach).contains(p) {
            for (a, b) in zip(line.points, line.points.dropFirst()) {
                let q = Self.closest(p, a, b)
                let d = PenPath.distance(p, q)
                if d <= reach, best == nil || d < best!.distance { best = (q, d) }
            }
        }
        return best?.point
    }

    /// Where an end at `p` joins the lines within `reach`: a line's end (or one of `ends`, the
    /// pen's own) counting as `PenAssist.endPreference` as far as it is, else the nearest point.
    func join(for p: CGPoint, within reach: CGFloat, ends extra: [CGPoint] = []) -> CGPoint? {
        var best: (point: CGPoint, score: CGFloat)?
        for end in ends + extra {
            let d = PenPath.distance(p, end)
            if d <= reach, best == nil || d * PenAssist.endPreference < best!.score { best = (end, d * PenAssist.endPreference) }
        }
        if let q = nearestPoint(to: p, within: reach) {
            let d = PenPath.distance(p, q)
            if best == nil || d < best!.score { best = (q, d) }
        }
        return best?.point
    }

    /// The point of the segment `a`–`b` nearest `p`.
    static func closest(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGPoint {
        let ab = CGPoint(x: b.x - a.x, y: b.y - a.y)
        let length = ab.x * ab.x + ab.y * ab.y
        let t = length > 0 ? min(max(((p.x - a.x) * ab.x + (p.y - a.y) * ab.y) / length, 0), 1) : 0
        return CGPoint(x: a.x + ab.x * t, y: a.y + ab.y * t)
    }
}

/// The drawn line a tap of the line eraser takes out whole: the line of the drawing under the
/// tap from junction to junction, as the painter sees it. A template's lines break wherever two
/// paints meet along them; they continue through every point where just one other drawn line
/// goes on, and stop where three or more meet, or where a line ends.
nonisolated struct LineChains {
    let lines: [LineArtDrawing.Line]
    /// The lines ending at each point (canvas units, to a 64th): line index and whether at its
    /// start.
    private let ends: [Key: [(line: Int, atStart: Bool)]]

    nonisolated private struct Key: Hashable {
        let x: Int, y: Int
        init(_ p: CGPoint) {
            x = Int((p.x * 64).rounded())
            y = Int((p.y * 64).rounded())
        }
    }

    init(_ drawing: LineArtDrawing) { self.init(lines: drawing.lines) }

    init(lines: [LineArtDrawing.Line]) {
        self.lines = lines
        var ends: [Key: [(line: Int, atStart: Bool)]] = [:]
        for (k, line) in lines.enumerated() {
            guard let first = line.points.first, let last = line.points.last else { continue }
            ends[Key(first), default: []].append((k, true))
            ends[Key(last), default: []].append((k, false))
        }
        self.ends = ends
    }

    /// The line nearest `point` within `tolerance` (canvas units) and the chain of lines it
    /// continues into, as one path (a loop's ends where it started).
    func chain(near point: CGPoint, tolerance: CGFloat) -> [CGPoint]? {
        var nearest: (line: Int, distance: CGFloat)?
        for (k, line) in lines.enumerated() where line.bounds.insetBy(dx: -tolerance, dy: -tolerance).contains(point) {
            for (a, b) in zip(line.points, line.points.dropFirst()) {
                let d = PenPath.segmentDistance(point, a, b)
                if d <= tolerance && (nearest == nil || d < nearest!.distance) { nearest = (k, d) }
            }
        }
        guard let start = nearest?.line else { return nil }
        var visited: Set<Int> = [start]
        var points = lines[start].points
        var closed = false
        // Onward from the end, then back from the start, unless the walk came round to it.
        for forward in [true, false] {
            var current = start, atEnd = forward
            while true {
                let line = lines[current]
                guard let joint = atEnd ? line.points.last : line.points.first,
                      let here = ends[Key(joint)], here.count == 2,
                      let next = here.first(where: { !($0.line == current && $0.atStart == !atEnd) })
                else { break }
                if next.line == start {
                    closed = true
                    break
                }
                guard visited.insert(next.line).inserted else { break }
                // The next line's points, leading away from the joint.
                let more = next.atStart ? lines[next.line].points : Array(lines[next.line].points.reversed())
                if forward {
                    points += more.dropFirst()
                } else {
                    points = Array(more.reversed().dropLast()) + points
                }
                current = next.line
                atEnd = next.atStart
            }
            if closed { break }
        }
        return points
    }
}

/// What a tap of the Fill tool does (`RefineView`), on the refinements' lines: a tap in a detail
/// area of the template on screen takes out the fills that made it (those of `made`, the fills
/// that template was made with, whose point lies in it); a tap on the swatch of a fill the
/// template doesn't have yet, within `reach`, takes that one out; anywhere else the tap is a
/// new fill. Points are normalized to the photo, as the template spans it.
nonisolated enum RefineFills {
    static func tapped(
        _ lines: [TemplateRefinements.Line], at point: SIMD2<Float>, made: [TemplateRefinements.Line], template: Template?,
        reach: SIMD2<Float>
    ) -> [TemplateRefinements.Line] {
        let fills = lines.indices.filter { lines[$0].kind == .fill && !lines[$0].points.isEmpty }
        if let template, let area = region(of: point, in: template), template.isDetailRegion(area) {
            let making = Set(fills.filter { made.contains(lines[$0]) && region(of: lines[$0].points[0], in: template) == area })
            if !making.isEmpty { return lines.indices.filter { !making.contains($0) }.map { lines[$0] } }
        }
        if let pending = fills.last(where: { k in
            guard !made.contains(lines[k]) else { return false }
            let d = (lines[k].points[0] - point) / pointwiseMax(reach, SIMD2(repeating: 1e-6))
            return (d * d).sum() <= 1
        }) {
            var kept = lines
            kept.remove(at: pending)
            return kept
        }
        return lines + [TemplateRefinements.Line(kind: .fill, radius: 0, points: [point])]
    }

    /// The template's region under a point normalized to the photo.
    static func region(of point: SIMD2<Float>, in template: Template) -> Int? {
        template.region(at: point * SIMD2(Float(template.width), Float(template.height)))
    }
}
