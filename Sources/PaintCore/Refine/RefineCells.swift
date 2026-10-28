import Foundation

/// Refine's cells for VoiceOver (the app's elements over the picture while a cell tool is
/// picked, painting-company row 143): where each cell is found, which cells it borders, and the
/// edits a VoiceOver action makes in place of a drag, so Merge and Move Number work without
/// seeing the picture. Every edit here is one the screen's gestures could make; the editor still
/// decides it.
public enum RefineCells {
    /// Where cell `region` of `t` is found and spoken from: its roomiest number (canvas units);
    /// nil for a region with none.
    public static func anchor(of region: Int, in t: Template) -> SIMD2<Float>? {
        guard t.regions.indices.contains(region) else { return nil }
        return t.labels(ofRegion: region).max { ($0.radius, $1.position.x) < ($1.radius, $0.position.x) }?.position
    }

    /// Every cell's anchor (`anchor(of:in:)`), the canvas's middle for a region with no number.
    public static func anchors(in t: Template) -> [SIMD2<Float>] {
        let middle = SIMD2(Float(t.width), Float(t.height)) / 2
        return t.regions.indices.map { anchor(of: $0, in: t) ?? middle }
    }

    /// The cells `region` shares an edge with (the canvas's frame is none), each once, the one
    /// with the longest shared boundary first (ties: lower index).
    public static func neighbours(of region: Int, in t: Template) -> [Int] {
        var shared: [Int: Float] = [:]
        for edge in t.edges where edge.right != BoundaryEdge.outside {
            let l = Int(edge.left), r = Int(edge.right)
            guard l == region || r == region, l != r else { continue }
            shared[l == region ? r : l, default: 0] += length(t.points(of: edge))
        }
        return shared.keys.sorted { (shared[$1]!, $0) < (shared[$0]!, $1) }
    }

    /// A Merge that joins `neighbour` into `region` and nothing else, `region` keeping its paint and
    /// number: a drag from just inside `region` to just inside `neighbour`, across the middle of
    /// the longest stretch of boundary they share, checked with the editor's own probe. Nil where
    /// they share none, or no stretch of it is long enough to cross alone.
    public static func merge(_ region: Int, with neighbour: Int, in t: Template, probe: TemplateEditor.MergeProbe) -> TemplateEditor.Edit? {
        var stretches: [(length: Float, a: SIMD2<Float>, b: SIMD2<Float>)] = []
        for edge in t.edges where edge.right != BoundaryEdge.outside {
            guard Set([Int(edge.left), Int(edge.right)]) == Set([region, neighbour]) else { continue }
            let points = Array(t.points(of: edge))
            for k in points.indices.dropLast() {
                stretches.append((simdLength(points[k + 1] - points[k]), points[k], points[k + 1]))
            }
        }
        stretches.sort { $0.length > $1.length }
        for stretch in stretches.prefix(8) where stretch.length > 0 {
            let middle = (stretch.a + stretch.b) / 2
            let along = (stretch.b - stretch.a) / stretch.length
            let across = SIMD2(-along.y, along.x)
            for offset: Float in [1, 0.5, 0.25] where offset * 4 < stretch.length {
                for side: Float in [1, -1] {
                    let from = middle + across * offset * side, to = middle - across * offset * side
                    guard t.region(at: from) == region, t.region(at: to) == neighbour else { continue }
                    if probe.areas(along: [from, to]) == [region, neighbour] { return .merge(points: [from, to]) }
                }
            }
        }
        return nil
    }

    /// Which way Move Number's VoiceOver actions move a number.
    public enum Direction: CaseIterable, Sendable {
        case up, down, left, right

        var step: SIMD2<Float> {
            switch self {
            case .up: SIMD2(0, -1)
            case .down: SIMD2(0, 1)
            case .left: SIMD2(-1, 0)
            case .right: SIMD2(1, 0)
            }
        }
    }

    /// Move Number for cell `region`'s roomiest number, a step `direction`: half its room (the
    /// free space round it, `Label.radius`), else a quarter, at least a unit, the first the editor
    /// makes. Nil for a cell with no number, or no room either way: Refine says it couldn't move.
    /// Each try lays the edit once, unchecked, on `t` (a VoiceOver action's cost, not a drag's).
    public static func moveNumber(of region: Int, _ direction: Direction, in t: Template) -> TemplateEditor.Edit? {
        guard t.regions.indices.contains(region),
              let label = t.labels(ofRegion: region).max(by: { ($0.radius, $1.position.x) < ($1.radius, $0.position.x) })
        else { return nil }
        for fraction: Float in [0.5, 0.25] {
            let to = label.position + direction.step * max(fraction * label.radius, 1)
            guard to.x >= 0, to.y >= 0, to.x <= Float(t.width), to.y <= Float(t.height), t.region(at: to) == region else { continue }
            let edit = TemplateEditor.Edit.moveLabel(from: label.position, to: to, reach: max(label.radius, TemplateEditor.tapReach))
            guard let (_, outcome) = try? TemplateEditor.apply(edit, to: t, verify: false) else { continue }
            if outcome.declined == nil, outcome.labelsMoved == 1 { return edit }
        }
        return nil
    }

    private static func length(_ points: ArraySlice<SIMD2<Float>>) -> Float {
        zip(points, points.dropFirst()).reduce(0) { $0 + simdLength($1.1 - $1.0) }
    }
}
