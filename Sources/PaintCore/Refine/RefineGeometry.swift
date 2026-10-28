#if canImport(CoreGraphics)
import CoreGraphics  // CGRect's geometry on Apple platforms; Foundation has it on Linux.
#endif
import Foundation

/// The pen's line as Refine keeps it: a finger's samples, steadied when the painter asks
/// (`steadied`), smoothed into curves (quadratics through the midpoints between samples, so the
/// corners of a shaky hand round off the way they do on the screen while it draws) and thinned to
/// the points that shape them.
public enum PenPath {
    /// `points` as a tip pulled on a string `string` long draws them (a lazy brush): the tip
    /// stays put while the finger moves within the string and, once it pulls the string taut,
    /// follows straight toward the finger, the string's length behind it, so a wobble smaller
    /// than the string only turns it a little. The line starts at the first sample and ends where
    /// the finger lifted, so one ended on another line still meets it. One pass over the samples:
    /// the screen redraws it from all of them while the finger moves.
    public static func steadied(_ points: [CGPoint], string: CGFloat) -> [CGPoint] {
        guard string > 0, let first = points.first, let last = points.last else { return points }
        var out = [first]
        var tip = first
        for p in points.dropFirst() {
            let dx = p.x - tip.x, dy = p.y - tip.y
            let d = (dx * dx + dy * dy).squareRoot()
            guard d > string else { continue }
            let pull = (d - string) / d
            tip = CGPoint(x: tip.x + dx * pull, y: tip.y + dy * pull)
            out.append(tip)
        }
        if out[out.count - 1] != last { out.append(last) }
        return out
    }

    /// The smoothed path through `points`, sampled every `spacing` (the points' units).
    public static func smoothed(_ points: [CGPoint], spacing: CGFloat) -> [CGPoint] {
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

    /// The points that keep the line within `tolerance` of itself (Ramer–Douglas–Peucker).
    public static func simplified(_ points: [CGPoint], tolerance: CGFloat) -> [CGPoint] {
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

    public static func length(_ points: [CGPoint]) -> CGFloat {
        zip(points, points.dropFirst()).reduce(0) { $0 + distance($1.0, $1.1) }
    }

    public static func midpoint(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2) }

    public static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }

    /// The distance from `p` to the segment `a`–`b`.
    public static func segmentDistance(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let ab = CGPoint(x: b.x - a.x, y: b.y - a.y)
        let length = ab.x * ab.x + ab.y * ab.y
        let t = length > 0 ? min(max(((p.x - a.x) * ab.x + (p.y - a.y) * ab.y) / length, 0), 1) : 0
        return distance(p, CGPoint(x: a.x + ab.x * t, y: a.y + ab.y * t))
    }
}

/// The help the Pen and Shapes give a line's ends, in the template's canvas units: an end whose
/// ink touches a line of the drawing moves onto it (`SnapLines`), so the cell closes as it looks.
public enum PenAssist {
    /// `line`'s ends brought onto `lines` where they come within `reach`, its end onto its own
    /// start where it comes back that near it (a loop, at least three reaches long), so the shape
    /// closes. An end is changed as little as it takes, and never turned back on itself (Paul,
    /// October 18: "it's snapping lines a bit, but not really in a way that makes them better"):
    /// one that crossed a line within `reach` of it ends at the crossing, its tail cut off; one
    /// heading at a line it would meet within `reach` goes straight on to it; otherwise it moves to the nearest point within `reach`, a straight line moving just
    /// that end and any other easing the move in over `easing` reaches of the line (half the
    /// line, if shorter), which the rest keeps. A move toward the nearest point alone, eased over
    /// one reach, bent a line meeting another at a slant into a hook. A line the changes would
    /// fold to under half its length keeps only its start's.
    public static func joined(_ line: [CGPoint], to lines: SnapLines, reach: CGFloat, straight: Bool) -> [CGPoint] {
        guard line.count >= 2, reach > 0 else { return line }
        let length = PenPath.length(line)
        let span = min(easing * reach, length / 2)
        // How much of an end may be cut off or added: never half the line, so an end can't be
        // taken back to a line its start is on.
        let limit = min(reach, length / 2)
        /// `points` with its last point brought onto `lines`, or nil when none is near enough.
        func joinEnd(_ points: [CGPoint]) -> [CGPoint]? {
            if let cut = trimmed(points, at: lines, within: limit) { return cut }
            let end = points[points.count - 1]
            if let hit = ahead(points, of: lines, within: limit), PenPath.distance(end, hit) > 1e-9 {
                return straight ? Array(points.dropLast()) + [hit] : points + [hit]
            }
            guard let target = lines.nearestPoint(to: end, within: reach) else { return nil }
            return move(points, to: target)
        }
        func move(_ points: [CGPoint], to target: CGPoint) -> [CGPoint] {
            guard straight else { return moving(points, atStart: false, to: target, span: span) }
            var points = points
            points[points.count - 1] = target
            return points
        }
        var out = line
        if let start = joinEnd(line.reversed()) { out = start.reversed() }
        let started = out
        let last = line[line.count - 1]
        let ownStart = length >= 3 * reach && PenPath.distance(last, out[0]) <= reach ? out[0] : nil
        if let joined = ownStart.map({ move(out, to: $0) }) ?? joinEnd(out) {
            out = joined
            if PenPath.length(out) < length / 2 { out = started }
        }
        return out
    }

    /// How far, in reaches, the assist eases a moved end in along the line.
    static let easing: CGFloat = 4

    /// `points` cut at its last crossing of `lines` within `limit` of its end (along it), nil
    /// when it crosses none there.
    static func trimmed(_ points: [CGPoint], at lines: SnapLines, within limit: CGFloat) -> [CGPoint]? {
        var along: CGFloat = 0
        for i in stride(from: points.count - 2, through: 0, by: -1) {
            let a = points[i], b = points[i + 1]
            if let t = lines.crossing(from: a, to: b, last: true) {
                let c = CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
                guard along + PenPath.distance(c, b) <= limit else { return nil }
                return Array(points[...i]) + [c]
            }
            along += PenPath.distance(a, b)
            if along > limit { return nil }
        }
        return nil
    }

    /// Where `points`, going straight on from its end (along its last stretch of `limit`), first
    /// meets `lines` within `limit`.
    static func ahead(_ points: [CGPoint], of lines: SnapLines, within limit: CGFloat) -> CGPoint? {
        let end = points[points.count - 1]
        var back = points[points.count - 2], along = PenPath.distance(back, end)
        var i = points.count - 2
        while along < limit, i > 0 {
            i -= 1
            along += PenPath.distance(points[i], points[i + 1])
            back = points[i]
        }
        guard along > 1e-9, limit > 0 else { return nil }
        let unit = CGPoint(x: (end.x - back.x) / along, y: (end.y - back.y) / along)
        let reachTo = CGPoint(x: end.x + unit.x * limit, y: end.y + unit.y * limit)
        guard let t = lines.crossing(from: end, to: reachTo, last: false), t > 0 else { return nil }
        return CGPoint(x: end.x + (reachTo.x - end.x) * t, y: end.y + (reachTo.y - end.y) * t)
    }

    /// `points` with an end (the first, or the last) moved to `target`, the move easing in over
    /// `span` of the line from that end: all of it at the end, none `span` along, where a point
    /// is added if none lies there, so the line before it stays as it was.
    public static func moving(_ points: [CGPoint], atStart: Bool, to target: CGPoint, span: CGFloat) -> [CGPoint] {
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

/// The Shapes tool's figures (`RefineShape`), in any one space: a rectangle across two corners,
/// an oval, a hexagon or a star filling the box they span, a curve bent through a point. A closed
/// figure ends where it starts (`RefineView` sends it as a closed line, its start once).
public enum ShapePath {
    public static func rectangle(from a: CGPoint, to b: CGPoint) -> [CGPoint] {
        [a, CGPoint(x: b.x, y: a.y), b, CGPoint(x: a.x, y: b.y), a]
    }

    /// The oval in the box from `a` to `b`, its points at most `spacing` apart (at least 16).
    public static func oval(from a: CGPoint, to b: CGPoint, spacing: CGFloat) -> [CGPoint] {
        let centre = PenPath.midpoint(a, b), rx = abs(b.x - a.x) / 2, ry = abs(b.y - a.y) / 2
        // No arc of an angle's step is longer than the step on the larger radius.
        let n = max(16, Int((2 * CGFloat.pi * max(rx, ry) / max(spacing, 0.1)).rounded(.up)))
        let points = (0..<n).map { k -> CGPoint in
            let angle = 2 * CGFloat.pi * CGFloat(k) / CGFloat(n)
            return CGPoint(x: centre.x + rx * cos(angle), y: centre.y + ry * sin(angle))
        }
        return points + [points[0]]
    }

    /// A regular hexagon stretched to the box from `a` to `b`, as the oval is a circle stretched
    /// to it: flat on top and bottom, its side corners on the box's sides, starting at the right
    /// one.
    public static func polygon(from a: CGPoint, to b: CGPoint) -> [CGPoint] {
        let corners = (0..<6).map { k -> CGPoint in
            let angle = CGFloat.pi / 3 * CGFloat(k)
            return CGPoint(x: cos(angle), y: sin(angle))
        }
        return fitted(corners, from: a, to: b)
    }

    /// A five-pointed star in the box from `a` to `b`, a point up and its inner corners 0.4 of the
    /// way out (a regular star stretched to the box, as the oval is a circle), starting at the
    /// top point.
    public static func star(from a: CGPoint, to b: CGPoint) -> [CGPoint] {
        let corners = (0..<10).map { k -> CGPoint in
            let angle = -CGFloat.pi / 2 + CGFloat.pi / 5 * CGFloat(k), radius: CGFloat = k % 2 == 0 ? 1 : 0.4
            return CGPoint(x: radius * cos(angle), y: radius * sin(angle))
        }
        return fitted(corners, from: a, to: b)
    }

    /// `points` scaled and moved so that their bounds are the box from `a` to `b`, closed.
    static func fitted(_ points: [CGPoint], from a: CGPoint, to b: CGPoint) -> [CGPoint] {
        let xs = points.map(\.x), ys = points.map(\.y)
        let x0 = xs.min()!, x1 = xs.max()!, y0 = ys.min()!, y1 = ys.max()!
        let lo = CGPoint(x: min(a.x, b.x), y: min(a.y, b.y)), size = CGSize(width: abs(b.x - a.x), height: abs(b.y - a.y))
        let out = points.map { p in
            CGPoint(x: lo.x + (p.x - x0) / (x1 - x0) * size.width, y: lo.y + (p.y - y0) / (y1 - y0) * size.height)
        }
        return out + [out[0]]
    }

    /// The curve from `a` to `b` through `bend` (a quadratic passing through it halfway), its
    /// points at most `spacing` apart.
    public static func curve(from a: CGPoint, to b: CGPoint, through bend: CGPoint, spacing: CGFloat) -> [CGPoint] {
        let control = CGPoint(x: 2 * bend.x - (a.x + b.x) / 2, y: 2 * bend.y - (a.y + b.y) / 2)
        // A quadratic moves at most twice its longer control leg per unit of its parameter.
        let speed = 2 * max(PenPath.distance(a, control), PenPath.distance(control, b))
        let n = max(2, Int((speed / max(spacing, 0.1)).rounded(.up)))
        return (0...n).map { k -> CGPoint in
            let t = CGFloat(k) / CGFloat(n), u = 1 - t
            let wa: CGFloat = u * u, wc: CGFloat = 2 * u * t, wb: CGFloat = t * t
            let x: CGFloat = wa * a.x + wc * control.x + wb * b.x
            let y: CGFloat = wa * a.y + wc * control.y + wb * b.y
            return CGPoint(x: x, y: y)
        }
    }
}

/// The lines on screen a pen's end may meet, in the template's canvas units: the drawing's
/// lines, those drawn since, less what was erased since.
public struct SnapLines: Sendable {
    public struct Line: Sendable {
        public let points: [CGPoint]
        public let bounds: CGRect
    }

    public let lines: [Line]

    public init(_ polylines: [[CGPoint]]) {
        lines = polylines.filter { $0.count >= 2 }.map { points in
            var low = points[0], high = points[0]
            for p in points {
                low = CGPoint(x: min(low.x, p.x), y: min(low.y, p.y))
                high = CGPoint(x: max(high.x, p.x), y: max(high.y, p.y))
            }
            return Line(points: points, bounds: CGRect(x: low.x, y: low.y, width: high.x - low.x, height: high.y - low.y))
        }
    }

    /// `polylines` less their points within reach of an erasure (its path and radius), split
    /// there; near one their segments are measured every unit, so a pass between two of a line's
    /// points cuts it too.
    public static func erasing(_ polylines: [[CGPoint]], by erasures: [(path: [CGPoint], radius: CGFloat)]) -> [[CGPoint]] {
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

    /// Where the segment `a`–`b` crosses a line, as a fraction of the way from `a`: the first
    /// such point, or with `last` the last. Segments that only touch or lie along one another
    /// count where they touch.
    public func crossing(from a: CGPoint, to b: CGPoint, last: Bool) -> CGFloat? {
        let box = CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
        var best: CGFloat?
        let d = CGPoint(x: b.x - a.x, y: b.y - a.y)
        for line in lines where line.bounds.insetBy(dx: -1e-6, dy: -1e-6).intersects(box) {
            for (p, q) in zip(line.points, line.points.dropFirst()) {
                let e = CGPoint(x: q.x - p.x, y: q.y - p.y)
                let denominator = d.x * e.y - d.y * e.x
                guard abs(denominator) > 1e-12 else { continue }
                let w = CGPoint(x: p.x - a.x, y: p.y - a.y)
                let t = (w.x * e.y - w.y * e.x) / denominator, u = (w.x * d.y - w.y * d.x) / denominator
                guard (0...1).contains(t), (0...1).contains(u) else { continue }
                if best == nil || (last ? t > best! : t < best!) { best = t }
            }
        }
        return best
    }

    /// The point on a line nearest `p`, if one lies within `reach`.
    public func nearestPoint(to p: CGPoint, within reach: CGFloat) -> CGPoint? {
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

    /// The point of the segment `a`–`b` nearest `p`.
    public static func closest(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGPoint {
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
public struct LineChains: Sendable {
    /// A line of the drawing and its bounds, padded by a unit so a straight line's box has area.
    public struct Line: Sendable {
        public let points: [CGPoint]
        public let bounds: CGRect

        public init?(_ points: [CGPoint]) {
            guard points.count >= 2 else { return nil }
            var low = points[0], high = points[0]
            for p in points {
                low = CGPoint(x: min(low.x, p.x), y: min(low.y, p.y))
                high = CGPoint(x: max(high.x, p.x), y: max(high.y, p.y))
            }
            self.points = points
            let width: CGFloat = high.x - low.x + 2, height: CGFloat = high.y - low.y + 2
            bounds = CGRect(x: low.x - 1, y: low.y - 1, width: width, height: height)
        }
    }

    public let lines: [Line]
    /// The lines ending at each point (canvas units, to a 64th): line index and whether at its
    /// start.
    private let ends: [Key: [(line: Int, atStart: Bool)]]

    private struct Key: Hashable {
        let x: Int, y: Int
        init(_ p: CGPoint) {
            x = Int((p.x * 64).rounded())
            y = Int((p.y * 64).rounded())
        }
    }

    /// The chains of the drawing's lines (`RefineGestures.drawingLines`), canvas units.
    public init(lines polylines: [[CGPoint]]) {
        let lines = polylines.compactMap(Line.init)
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
    public func chain(near point: CGPoint, tolerance: CGFloat) -> [CGPoint]? {
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
