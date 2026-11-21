#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation

/// The lead a photo suggests for a Stained Glass window (painting-company row 366; Paul's pick,
/// November 20, 2026: a suggested lead the painter can edit). The photo is made into a classic
/// template of few paints, large areas and smooth edges, and every edge between two of its areas
/// becomes a line of lead, simplified and smoothed as a glazier's cut runs; the frame is the
/// window's own. The painter takes lines away (`GlassWindow.Leading.erase`) and draws their own.
public enum GlassLeadSuggestion {
    /// The settings the suggestion is made with: few paints, the least detail, the smoothest
    /// edges, the photo smoothed most and its cells the largest the tuning makes.
    public static let settings = GenerationSettings(
        colorCount: 6, detail: 0, smoothness: 1, lineArt: LineArtSettings(style: .classic),
        tuning: PipelineTuning(smoothing: 4, textureFlattening: 4, minimumCellSize: 4, subjectCellSize: 4))

    /// How far a line may stray from the edge it follows, and how long a line must be to stay
    /// (the edges between two junctions closer than that join their neighbours' lead), as shares
    /// of the window's long side.
    static let tolerance: Float = 0.005
    static let shortest: Float = 0.005
    /// How far a suggested line's end may stop short of the lead and still be joined to it.
    public static let joining: Float = 0.02
    /// The narrowest piece the suggestion keeps, as the radius of the largest disc inside it, a
    /// share of the long side: heavy lead (about 0.018 of it wide) leaves a narrower piece a
    /// slit of glass, and a cluster of them a blot of lead. Narrower ones join the neighbour they
    /// share the most lead with.
    static let narrowest: Float = 0.012

    /// The suggested lines for a window `width` × `height` (canvas units) made from `photo`.
    public static func lines(
        photo: RGBAImage, width: Int, height: Int, cancel: CancellationCheck = .none
    ) throws -> [[SIMD2<Float>]] {
        let t = try TemplateGenerator(settings: settings).generate(from: photo, cancel: cancel).template
        let sx = Float(width) / Float(max(t.width, 1)), sy = Float(height) / Float(max(t.height, 1))
        let long = Float(max(width, height))
        let pieces = Self.pieces(of: t, narrowest: narrowest * long / max(sx, sy))
        var lines: [[SIMD2<Float>]] = []
        for edge in t.edges where edge.right != BoundaryEdge.outside && edge.left != BoundaryEdge.outside
            && pieces[Int(edge.left)] != pieces[Int(edge.right)] {
            let points = t.points(of: edge).map { CGPoint(x: CGFloat($0.x * sx), y: CGFloat($0.y * sy)) }
            let simple = PenPath.simplified(points, tolerance: CGFloat(tolerance * long))
            let length = zip(simple, simple.dropFirst()).reduce(CGFloat(0)) { $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y) }
            guard simple.count >= 2, Float(length) >= shortest * long else { continue }
            let smooth = simple.count > 2 ? PenPath.smoothed(simple, spacing: CGFloat(0.006 * long)) : simple
            lines.append(smooth.map { SIMD2(Float($0.x), Float($0.y)) })
        }
        return lines
    }

    /// The piece each of `t`'s regions falls in once every region narrower than `narrowest`
    /// (template units) has joined, narrowest first, the neighbour it shares the longest
    /// boundary with. A piece is as wide as its widest region.
    static func pieces(of t: Template, narrowest: Float) -> [Int] {
        let n = t.regions.count
        var shared = [[Int: Float]](repeating: [:], count: n)
        for edge in t.edges where edge.right != BoundaryEdge.outside && edge.left != BoundaryEdge.outside {
            let a = Int(edge.left), b = Int(edge.right)
            guard a != b, a < n, b < n else { continue }
            let p = t.points(of: edge)
            let length = zip(p, p.dropFirst()).reduce(Float(0)) { let d = $1.1 - $1.0; return $0 + (d.x * d.x + d.y * d.y).squareRoot() }
            shared[a][b, default: 0] += length
            shared[b][a, default: 0] += length
        }
        var sets = DisjointSet(count: n)
        var width = (0..<n).map { t.inscribedRadius(ofRegion: $0, upTo: narrowest) }
        for r in (0..<n).sorted(by: { (width[$0], $0) < (width[$1], $1) }) {
            let root = sets.find(r)
            guard width[root] < narrowest else { continue }
            // The boundary the whole piece shares with each other piece.
            var along: [Int: Float] = [:]
            for member in 0..<n where sets.find(member) == root {
                for (other, length) in shared[member] {
                    let o = sets.find(other)
                    if o != root { along[o, default: 0] += length }
                }
            }
            guard let into = along.max(by: { ($0.value, -$0.key) < ($1.value, -$1.key) })?.key else { continue }
            sets.parent[root] = into
            width[into] = max(width[into], width[root])
        }
        return (0..<n).map { sets.find($0) }
    }
}
