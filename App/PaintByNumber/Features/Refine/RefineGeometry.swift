import CoreGraphics
import Foundation

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

/// The drawn line a tap of the line eraser takes out whole: the line of the drawing under the
/// tap from junction to junction, as the painter sees it. A template's lines break wherever two
/// paints meet along them; they continue through every point where just one other drawn line
/// goes on, and stop where three or more meet, or where a line ends.
nonisolated struct LineChains {
    let lines: [LineArtDrawing.Line]
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
