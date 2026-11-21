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

    /// The suggested lines for a window `width` × `height` (canvas units) made from `photo`.
    public static func lines(
        photo: RGBAImage, width: Int, height: Int, cancel: CancellationCheck = .none
    ) throws -> [[SIMD2<Float>]] {
        let t = try TemplateGenerator(settings: settings).generate(from: photo, cancel: cancel).template
        let sx = Float(width) / Float(max(t.width, 1)), sy = Float(height) / Float(max(t.height, 1))
        let long = Float(max(width, height))
        var lines: [[SIMD2<Float>]] = []
        for edge in t.edges where edge.right != BoundaryEdge.outside && edge.left != BoundaryEdge.outside {
            let points = t.points(of: edge).map { CGPoint(x: CGFloat($0.x * sx), y: CGFloat($0.y * sy)) }
            let simple = PenPath.simplified(points, tolerance: CGFloat(tolerance * long))
            let length = zip(simple, simple.dropFirst()).reduce(CGFloat(0)) { $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y) }
            guard simple.count >= 2, Float(length) >= shortest * long else { continue }
            let smooth = simple.count > 2 ? PenPath.smoothed(simple, spacing: CGFloat(0.006 * long)) : simple
            lines.append(smooth.map { SIMD2(Float($0.x), Float($0.y)) })
        }
        return lines
    }
}
