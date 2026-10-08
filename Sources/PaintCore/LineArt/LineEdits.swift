import Foundation

/// A change the painter made to the drawing before painting (the app's Refine screen): a line
/// drawn with the pen, the eraser dragged along a path, or a line tapped away.
/// `LineArtInput.edits` lists them in the order they were made; `LayeredLines` applies them
/// where it lays out its own lines (`LineEdits`), so cells, numbers and every check of a
/// template hold for them as for any line.
public struct LineEdit: Sendable, Equatable {
    public enum Kind: UInt8, Sendable {
        /// A line drawn: an outline, as heavy as the rest of the drawing.
        case draw
        /// The lines under the eraser's path taken out.
        case erase
        /// The line running along the path taken out from one end of the path to the other (a
        /// line tapped away, the path its own): what only crosses the path, or goes on past its
        /// ends, stays.
        case eraseLine
    }

    public var kind: Kind
    /// The pen's or the eraser's path, or the erased line's, normalized to the photo (0...1,
    /// origin top-left).
    public var points: [SIMD2<Float>]
    /// How far either side of its path the eraser reaches, a fraction of the photo's long side;
    /// a drawn line has none.
    public var radius: Float

    public init(kind: Kind, points: [SIMD2<Float>], radius: Float = 0) {
        self.kind = kind
        self.points = points
        self.radius = radius
    }
}

/// The painter's edits (`LineArtInput.edits`) applied to the lines `LayeredLines` found, at its
/// layer stage before free ends close:
/// - a drawn line joins as an outline at full strength, so it walls cells off as a subject's
///   silhouette does, cut where it leaves the canvas. Its ends meet the lines they were drawn
///   to: an end that crosses a line within `reach` (and within a quarter of its own length) is
///   trimmed back to it, one that touches a line or the frame is attached, and one that stops
///   short stays free, so `closeFreeEnds` leads it into the line it was heading for, as it
///   does the drawing's own ends;
/// - the eraser takes out every point of a line within its radius, of the app's lines and of
///   the lines drawn before it (a line drawn later over an erased place stays), leaving no
///   piece shorter than `LineLayering.minimumRun`; a line erased whole (`eraseLine`) takes out
///   only the points beside its path that run along it (within `alongAngle`), so the lines it
///   meets keep their junction with each other. Cut ends stay where the eraser left them, and
///   no free end reaches into a place erased after its line was drawn (`blockedBy` over
///   `origin`, which `LayeredLines` hands `closeFreeEnds`).
/// `LayeredLines.annotate` draws the template's edges near an edit (`footprint`) exactly where
/// lines run along them, instead of each edge whole or not at all by the most of it, so a line
/// drawn or erased along part of a boundary between two paints shows as it was drawn.
///
/// Plain arithmetic in edit order: the same edits give the same lines on every device.
enum LineEdits {
    /// How much of a hostile file is read: the app writes far fewer edits and points.
    static let maximumEdits = 2000
    static let maximumPoints = 4000
    /// The eraser's radius (of the long side) is clamped to this.
    static let radiusRange: ClosedRange<Float> = 0.0005...0.25
    /// Bounds on what edits may cost: the drawn lines' total length, in canvas long sides, and
    /// the area the eraser's paths are measured over, in canvases. Far beyond what a painter
    /// draws.
    static let maximumDrawnLength: Float = 400
    static let maximumErasedArea: Float = 64
    /// A line runs along an erased line's path where their directions are within this many
    /// degrees: lines meeting it at a junction, or crossing it, are farther off.
    static let alongAngle: Float = 35

    struct Applied {
        /// The lines, the painter's among them.
        var lines: [DrawnLine]
        /// Per line, the edit that drew it, or -1 for the app's own.
        var origin: [Int32]
        /// Per pixel, the last eraser path that covers it, or -1; nil when no eraser passed.
        var erasedBy: [Int32]?
        /// The lines erased whole: the edit's index, its path in pixel coordinates (as given)
        /// and its reach in pixels.
        var erasedLines: [(index: Int32, path: [SIMD2<Float>], radius: Float)]
        /// Per pixel, the last edit that erased anything within reach of it (an eraser's pass or
        /// an erased line's path), or -1; nil when nothing was erased.
        var blockedBy: [Int32]?
        /// The eraser's passes and the erased lines' paths, in pixel coordinates, with their
        /// reach in pixels.
        var erasures: [(path: [SIMD2<Float>], radius: Float)]
        /// The painter's lines kept, as pieces.
        var drawn: Int
    }

    static func apply(_ edits: [LineEdit], to lines: [DrawnLine], width w: Int, height h: Int, reach: Float) -> Applied {
        let edits = sanitized(edits)
        let long = Float(max(w, h))
        var erased: [Int32] = [], blocked: [Int32] = []
        var erasures: [(path: [SIMD2<Float>], radius: Float)] = []
        var erasedLines: [(index: Int32, path: [SIMD2<Float>], radius: Float)] = []
        var area: Float = 0
        for (k, edit) in edits.enumerated() where edit.kind != .draw {
            let path = edit.kind == .erase ? pixelPath(edit.points, width: w, height: h) : pixelPoints(edit.points, width: w, height: h)
            let radius = edit.radius * long
            area += boxArea(path, margin: radius)
            guard area <= maximumErasedArea * Float(w * h) else { break }
            let isEraser = edit.kind == .erase
            if blocked.isEmpty { blocked = [Int32](repeating: -1, count: w * h) }
            if isEraser && erased.isEmpty { erased = [Int32](repeating: -1, count: w * h) }
            // Later paths cover earlier ones: each pixel ends with the last that reaches it.
            stamp(path, radius: radius, width: w, height: h) { i in
                blocked[i] = Int32(k)
                if isEraser { erased[i] = Int32(k) }
            }
            if !isEraser { erasedLines.append((Int32(k), path, radius)) }
            erasures.append((path, radius))
        }
        let erasedBy = erased.isEmpty ? nil : erased
        var out = lines
        var origin = [Int32](repeating: -1, count: lines.count)
        var length: Float = 0
        drawing: for (k, edit) in edits.enumerated() where edit.kind == .draw {
            for line in drawnLines(edit.points, width: w, height: h) {
                length += line.length
                guard length <= maximumDrawnLength * long else { break drawing }
                out.append(line)
                origin.append(Int32(k))
            }
        }
        cut(&out, origin: &origin, erasedBy: erasedBy, erasedLines: erasedLines, width: w, height: h)
        snapEnds(&out, origin: origin, width: w, height: h, reach: reach)
        return Applied(
            lines: out, origin: origin, erasedBy: erasedBy, erasedLines: erasedLines,
            blockedBy: blocked.isEmpty ? nil : blocked, erasures: erasures, drawn: origin.filter { $0 >= 0 }.count)
    }

    /// The edits a file may hold, cut to size: finite points only, the eraser's radius clamped.
    static func sanitized(_ edits: [LineEdit]) -> [LineEdit] {
        edits.prefix(maximumEdits).compactMap { edit in
            var edit = edit
            edit.points = edit.points.prefix(maximumPoints).filter { $0.x.isFinite && $0.y.isFinite }
            guard !edit.points.isEmpty else { return nil }
            edit.radius = edit.radius.isFinite
                ? min(max(edit.radius, radiusRange.lowerBound), radiusRange.upperBound) : radiusRange.lowerBound
            return edit
        }
    }

    /// Points normalized to the photo in pixel coordinates (pixel centres at integers), those
    /// far off the photo brought within half a photo of it.
    static func pixelPoints(_ points: [SIMD2<Float>], width w: Int, height h: Int) -> [SIMD2<Float>] {
        let scale = SIMD2(Float(w), Float(h))
        return points.map { pointwiseMin(pointwiseMax($0, SIMD2(repeating: -0.5)), SIMD2(repeating: 1.5)) * scale - 0.5 }
    }

    /// A path normalized to the photo in pixel coordinates (`pixelPoints`), about one point
    /// per pixel.
    static func pixelPath(_ points: [SIMD2<Float>], width w: Int, height h: Int) -> [SIMD2<Float>] {
        let pts = pixelPoints(points, width: w, height: h)
        guard let first = pts.first else { return [] }
        var dense = [first]
        for (a, b) in zip(pts, pts.dropFirst()) {
            let steps = Int(simdLength(b - a).rounded(.up))
            guard steps > 0 else { continue }
            for s in 1...steps { dense.append(a + (b - a) * (Float(s) / Float(steps))) }
        }
        return dense
    }

    /// The pieces of a drawn path that lie on the canvas, as outlines at full strength: an end
    /// the painter drew is free, one where the path leaves the canvas lies on the frame.
    static func drawnLines(_ points: [SIMD2<Float>], width w: Int, height h: Int) -> [DrawnLine] {
        let path = pixelPath(points, width: w, height: h)
        guard path.count >= 2 else { return [] }
        let low = SIMD2<Float>(repeating: -0.5), high = SIMD2(Float(w) - 0.5, Float(h) - 0.5)
        let inside = path.map { all($0 .>= low) && all($0 .<= high) }
        let line = DrawnLine(
            points: path, strength: [Float](repeating: 1, count: path.count),
            layer: [UInt8](repeating: LineLayer.outline.rawValue, count: path.count), closed: false, free: (true, true),
            links: [], eye: false)
        let last = SIMD2(Float(w - 1), Float(h - 1))
        return line.pieces(keeping: inside, freeCuts: false).compactMap { piece in
            var piece = piece
            piece.points = piece.points.map { pointwiseMin(pointwiseMax($0, .zero), last) }
            return piece.length >= 1 ? piece : nil
        }
    }

    /// Takes out every point erased after its line was drawn: covered by the eraser
    /// (`erasedBy` over `origin`) or running along a line erased whole (`runsAlong`); then the
    /// pieces left shorter than `LineLayering.minimumRun`.
    static func cut(
        _ lines: inout [DrawnLine], origin: inout [Int32], erasedBy: [Int32]?,
        erasedLines: [(index: Int32, path: [SIMD2<Float>], radius: Float)], width w: Int, height h: Int
    ) {
        guard erasedBy != nil || !erasedLines.isEmpty else { return }
        let reaches = erasedLines.map { erased -> (low: SIMD2<Float>, high: SIMD2<Float>) in
            var low = erased.path[0], high = erased.path[0]
            for p in erased.path {
                low = pointwiseMin(low, p)
                high = pointwiseMax(high, p)
            }
            return (low - erased.radius, high + erased.radius)
        }
        var kept: [DrawnLine] = [], keptOrigin: [Int32] = []
        for (line, o) in zip(lines, origin) {
            var keep = erasedBy.map { erasedBy in
                line.points.map { erasedBy[LineLayering.pixelIndex(of: $0, width: w, height: h)] <= o }
            } ?? [Bool](repeating: true, count: line.points.count)
            for (erased, reach) in zip(erasedLines, reaches) where erased.index > o {
                for i in line.points.indices where keep[i] {
                    let p = line.points[i]
                    guard all(p .>= reach.low), all(p .<= reach.high) else { continue }
                    if runsAlong(line, at: i, path: erased.path, radius: erased.radius) { keep[i] = false }
                }
            }
            if !keep.contains(false) {
                kept.append(line)
                keptOrigin.append(o)
                continue
            }
            for var piece in line.pieces(keeping: keep, freeCuts: false) where piece.length >= LineLayering.minimumRun {
                // A seal into a junction the eraser took goes with it.
                if let erasedBy {
                    piece.links = piece.links.filter { erasedBy[LineLayering.pixelIndex(of: $0.to, width: w, height: h)] <= o }
                }
                kept.append(piece)
                keptOrigin.append(o)
            }
        }
        lines = kept
        origin = keptOrigin
    }

    /// `lines` (the app's, of origin -1) with every erasing cut: for the writing, which joins
    /// after the lines are laid out.
    static func cut(_ lines: [DrawnLine], by applied: Applied, width w: Int, height h: Int) -> [DrawnLine] {
        var lines = lines
        var origin = [Int32](repeating: -1, count: lines.count)
        cut(&lines, origin: &origin, erasedBy: applied.erasedBy, erasedLines: applied.erasedLines, width: w, height: h)
        return lines
    }

    /// Whether point `i` of `line` runs along `path` there: within `radius` of it, beside it
    /// rather than past either of its ends, and in its direction (within `alongAngle`).
    static func runsAlong(_ line: DrawnLine, at i: Int, path: [SIMD2<Float>], radius: Float) -> Bool {
        let n = line.points.count, p = line.points[i]
        let direction = line.points[min(i + 3, n - 1)] - line.points[max(i - 3, 0)]
        let span = simdLength(direction)
        guard path.count >= 2, span > 1e-3 else { return false }
        var nearest = -1, nearestT: Float = 0, nearestD2 = Float.infinity
        for s in 0..<(path.count - 1) {
            let a = path[s], ab = path[s + 1] - a
            let l2 = simdLengthSquared(ab)
            guard l2 > 1e-9 else { continue }
            let t = simdDot(p - a, ab) / l2
            let d2 = simdLengthSquared(p - (a + ab * min(max(t, 0), 1)))
            if d2 < nearestD2 {
                nearest = s
                nearestT = t
                nearestD2 = d2
            }
        }
        guard nearest >= 0, nearestD2 <= radius * radius else { return false }
        if (nearest == 0 && nearestT < 0) || (nearest == path.count - 2 && nearestT > 1) { return false }
        let ab = path[nearest + 1] - path[nearest]
        let cosine = abs(simdDot(direction, ab)) / (span * simdLength(ab))
        return cosine >= cos(alongAngle * .pi / 180)
    }

    // MARK: - Ends

    /// Each free end the painter drew meets what it was drawn to: trimmed back to the first
    /// line it crosses within `reach` of the end (and within a quarter of its line's length),
    /// or attached where it touches a line or the frame. Ends that meet nothing stay free.
    static func snapEnds(_ lines: inout [DrawnLine], origin: [Int32], width w: Int, height h: Int, reach: Float) {
        guard origin.contains(where: { $0 >= 0 }) else { return }
        // The line covering each pixel, and whether another covers it too.
        var covering = [Int32](repeating: -1, count: w * h)
        var covered = [Bool](repeating: false, count: w * h)
        for (id, line) in lines.enumerated() {
            visitPixels(of: line) { x, y in
                guard x >= 0, y >= 0, x < w, y < h else { return }
                let i = y * w + x
                if covering[i] < 0 {
                    covering[i] = Int32(id)
                } else if covering[i] != Int32(id) {
                    covered[i] = true
                }
            }
        }
        let owner = covering, shared = covered
        for k in lines.indices where origin[k] >= 0 && !lines[k].closed {
            for end in 0..<2 where end == 0 ? lines[k].free.0 : lines[k].free.1 {
                let id = Int32(k)
                let contact: (SIMD2<Float>) -> Contact = { p in
                    let px = Int(p.x.rounded()), py = Int(p.y.rounded())
                    if px <= 0 || py <= 0 || px >= w - 1 || py >= h - 1 { return .on }
                    func other(_ i: Int) -> Bool { shared[i] || (owner[i] >= 0 && owner[i] != id) }
                    if other(py * w + px) { return .on }
                    for y in (py - 1)...(py + 1) {
                        for x in (px - 1)...(px + 1) where other(y * w + x) { return .beside }
                    }
                    return .clear
                }
                snap(&lines[k], end: end, reach: reach, contact: contact)
            }
        }
    }

    /// Where a point of a drawn line is against the other lines: on one, beside one (a
    /// neighbouring pixel), or clear of them.
    enum Contact { case clear, beside, on }

    /// Trims `line` back from `end` to the first point within `reach` (and a quarter of the
    /// line) where it meets another line (`contact`; onto the line itself when the touch runs
    /// onto it within a step or two) or crosses itself, and attaches it there.
    static func snap(_ line: inout DrawnLine, end: Int, reach: Float, contact: (SIMD2<Float>) -> Contact) {
        let n = line.points.count
        guard n >= 2 else { return }
        let arc = line.arcLength
        let total = arc[n - 1]
        let limit = min(reach, 0.25 * total)
        let step = end == 0 ? 1 : -1
        // A crossing with the line's own far part (a loop drawn past its start) counts too.
        let apart = max(2 * limit, LineLayering.minimumRun)
        func crossesItself(_ j: Int) -> Bool {
            let p = line.points[j]
            for m in 0..<n where abs(arc[m] - arc[j]) > apart && simdLengthSquared(line.points[m] - p) <= 2.25 { return true }
            return false
        }
        var j = end == 0 ? 0 : n - 1
        while (end == 0 ? arc[j] : total - arc[j]) <= limit {
            let touch = contact(line.points[j])
            if touch != .clear || crossesItself(j) {
                var cut = j
                if touch == .beside {
                    var k = j + step
                    while k >= 0 && k < n && abs(k - j) <= 2 && contact(line.points[k]) != .clear {
                        if contact(line.points[k]) == .on {
                            cut = k
                            break
                        }
                        k += step
                    }
                }
                trim(&line, to: cut, end: end)
                return
            }
            j += step
            guard j >= 0 && j < n else { return }
        }
    }

    /// Drops the points beyond `j` at `end` (0: the start, 1: the end), which no longer is free.
    static func trim(_ line: inout DrawnLine, to j: Int, end: Int) {
        if end == 0 {
            line.points.removeFirst(j)
            line.strength.removeFirst(j)
            line.layer.removeFirst(j)
            line.links = line.links.filter { $0.index >= j }.map { ($0.index - j, $0.to) }
            line.free.0 = false
        } else {
            let drop = line.points.count - 1 - j
            line.points.removeLast(drop)
            line.strength.removeLast(drop)
            line.layer.removeLast(drop)
            line.links = line.links.filter { $0.index <= j }
            line.free.1 = false
        }
    }

    /// The pixels `LineLayering.walls` rasterizes a line into.
    static func visitPixels(of line: DrawnLine, _ body: (Int, Int) -> Void) {
        let p = line.points
        guard let first = p.first else { return }
        if p.count == 1 { body(Int(first.x.rounded()), Int(first.y.rounded())) }
        for k in 0..<(p.count - 1) { LineLayering.segment(p[k], p[k + 1], body) }
        if line.closed && p.count > 2 { LineLayering.segment(p[p.count - 1], p[0], body) }
        for l in line.links { LineLayering.segment(p[l.index], l.to, body) }
    }

    // MARK: - Areas

    /// Where `annotate` follows the lines exactly: within `near` of the eraser's paths' reach and
    /// of the painter's lines (`origin` 0 or more) as they were laid out.
    static func footprint(_ applied: Applied, lines: [DrawnLine], near: Float, width w: Int, height h: Int) -> [Bool] {
        var mask = [Bool](repeating: false, count: w * h)
        for erasure in applied.erasures {
            stamp(erasure.path, radius: erasure.radius + near, width: w, height: h) { mask[$0] = true }
        }
        for (line, o) in zip(lines, applied.origin) where o >= 0 {
            stamp(line.points, radius: near, width: w, height: h) { mask[$0] = true }
        }
        return mask
    }

    /// Calls `body` with each canvas pixel whose centre lies within `radius` of the path (pixel
    /// coordinates; it may run off the canvas), measured from the path's pixels.
    static func stamp(_ path: [SIMD2<Float>], radius: Float, width w: Int, height h: Int, _ body: (Int) -> Void) {
        guard let first = path.first, radius >= 0 else { return }
        var low = first, high = first
        for p in path {
            low = pointwiseMin(low, p)
            high = pointwiseMax(high, p)
        }
        let margin = Int(radius.rounded(.up)) + 1
        let x0 = max(Int(low.x.rounded(.down)) - margin, -margin), x1 = min(Int(high.x.rounded(.up)) + margin, w - 1 + margin)
        let y0 = max(Int(low.y.rounded(.down)) - margin, -margin), y1 = min(Int(high.y.rounded(.up)) + margin, h - 1 + margin)
        // Only the part that reaches the canvas.
        guard x0 <= x1, y0 <= y1, x1 >= 0, y1 >= 0, x0 < w, y0 < h else { return }
        let bw = x1 - x0 + 1, bh = y1 - y0 + 1
        var seed = [UInt8](repeating: 0, count: bw * bh)
        func plot(_ x: Int, _ y: Int) {
            let xx = x - x0, yy = y - y0
            if xx >= 0 && yy >= 0 && xx < bw && yy < bh { seed[yy * bw + xx] = 1 }
        }
        plot(Int(first.x.rounded()), Int(first.y.rounded()))
        for (a, b) in zip(path, path.dropFirst()) { LineLayering.segment(a, b, plot) }
        guard let d2 = try? DistanceTransform.squaredDistances(seed, width: bw, height: bh, cancel: .none) else { return }
        let r2 = Double(radius * radius)
        for y in max(y0, 0)...min(y1, h - 1) {
            for x in max(x0, 0)...min(x1, w - 1) where d2[(y - y0) * bw + (x - x0)] <= r2 { body(y * w + x) }
        }
    }

    /// The area of a path's bounds grown by `margin`, which `stamp` measures over.
    static func boxArea(_ path: [SIMD2<Float>], margin: Float) -> Float {
        guard let first = path.first else { return 0 }
        var low = first, high = first
        for p in path {
            low = pointwiseMin(low, p)
            high = pointwiseMax(high, p)
        }
        let size = high - low + 2 * (margin + 1)
        return size.x * size.y
    }
}
