import Foundation

/// Manual editing of a coloring-book template, for the app's Refine screen: the painter's pen,
/// eraser, line eraser and fill applied to a finished `Template`, and nothing else. No photo, no
/// edge map, no segmentation, no smoothing or fitting is involved: a line is the polyline the
/// painter drew (quantized to `Template.coordinateQuantum`), an erasure cuts the ink at the edge
/// of the eraser's reach, a fill joins cells and picks a paint. Whatever an edit does not touch
/// stays as it was, byte for byte: regions, outlines, fills, numbers, paints. Edits are exact
/// on the quantum grid (`Lattice`), so the same edits give the same template on every device,
/// and a template that validates before an edit validates after it
/// (`Template.validate(minLabelRadius:)`). `docs/coloring-book.md` › The painter's edits says
/// how an edit lands.
///
/// All coordinates are canvas units (origin top-left, +y down), as the template's.
///
/// - **Draw.** The polyline lies on the template as drawn. Each end within `inkWidth` of ink (an
///   edge, a stroke, the canvas frame) is moved onto it, to the nearest vertex within
///   `vertexSnap`, else to the nearest point, which becomes a vertex of that ink; a line whose
///   ends meet closes into a loop. The line is cut wherever it meets the drawing. Where a stretch
///   closes off part of a region with the region's outline (and the strokes it touches), the
///   region is cut exactly along it: each piece keeps the region's paint, has a number of its
///   own, and the new boundary is inked (`LineLayer.outline`, weight 255) with the line's points
///   verbatim. A piece with room for a number only at a detail area's floor becomes a detail
///   area; a piece with less is not cut off. A stretch that closes nothing is an interior stroke,
///   verbatim.
/// - **Erase.** Ink within the radius of the path is cut out exactly at the edge of the reach.
///   Ink between two regions that this breaks lets their paint through: the regions merge (the
///   larger keeps its index and its paint) and the ink left of that boundary stays as strokes.
///   Undrawn (paint) edges are never touched.
/// - **Erase line.** The line under a point is taken out from junction to junction, the regions
///   it kept apart merging as above.
/// - **Fill.** The closed shape under the point, bounded by ink (the tapped region alone if it
///   reaches the canvas frame), becomes one detail area painted with the paint within a
///   just-noticeable difference of the color, else a new paint added last.
public enum TemplateEditor {
    public enum Edit: Sendable, Equatable {
        /// A polyline; `closed` joins the last point back to the first.
        case draw(points: [SIMD2<Float>], closed: Bool = false)
        /// The eraser dragged along a path, reaching `radius` either side.
        case erase(path: [SIMD2<Float>], radius: Float)
        /// The drawn line nearest `point` within `reach`, from junction to junction.
        case eraseLine(at: SIMD2<Float>, reach: Float = TemplateEditor.tapReach)
        /// The shape under `point`, painted `color` (OKLab, as `LineEdit.photoColor` reads it).
        case fill(at: SIMD2<Float>, color: SIMD3<Float>)
    }

    /// Why an edit was declined: the template is returned as it was.
    public struct Declined: Sendable, Equatable, CustomStringConvertible {
        public var reason: String
        public var description: String { reason }
    }

    /// What an edit did.
    public struct Outcome: Sendable, Equatable {
        /// An edit that did nothing.
        public init() {}


        /// Whether the template changed.
        public var changed = false
        /// Set when the edit could not be made; the template is then unchanged.
        public var declined: Declined?
        /// Lines laid (a drawn line cut off the canvas lays one per piece on it).
        public var lines = 0
        /// Ends of drawn lines moved onto ink.
        public var joins = 0
        /// Regions made by cutting regions, regions removed by merging.
        public var regionsSplit = 0
        public var regionsMerged = 0
        /// Detail areas made: cut pieces with room only for a detail number, fills.
        public var detailAreas = 0
        /// Strokes made (a line that closes nothing; the ink of a merged boundary).
        public var strokes = 0
        /// Lines (edges, strokes) the eraser reached, or a tapped line took out.
        public var erased = 0
        public var fills = 0
        public var paintsAdded = 0
        /// Where a cut was not made because the piece had no room for a number: the piece's
        /// centre.
        public var tooSmall: [SIMD2<Float>] = []
        /// Regions of the new template whose outline, paint, numbers or strokes changed.
        public var touchedRegions: [Int] = []
        /// For each region of the old template, the region it is in the new one (a merged
        /// region: the merged one; a cut region: the piece that kept its index).
        public var continued: [Int] = []
    }

    /// What the template cannot be edited for (no line art, a canvas out of range).
    public enum Failure: Error, Equatable {
        case unsupported(String)
    }

    /// The width of ink, canvas units: an end of a drawn line this near ink is on it.
    public static let inkWidth: Float = 3
    /// How near a tap must be to a line to take it out, canvas units.
    public static let tapReach: Float = 8
    /// Points of one edit beyond this are ignored (the app's help has already thinned them).
    public static let maximumPoints = 4000

    static var reach: Int64 { Int64((inkWidth * Float(Lattice.unit)).rounded()) }
    /// An end joining a line moves to a vertex of it within this, lattice steps (half a unit),
    /// rather than make a vertex beside it.
    static var vertexSnap: Int64 { Lattice.unit / 2 }

    /// Applies one edit. A declined edit (`Outcome.declined`) returns the template as given.
    /// With `verify` the result is checked with `Template.validate(minLabelRadius:)` before it is
    /// returned, and an edit that would break it is declined; the checks cost about a pass over
    /// the template.
    public static func apply(
        _ edit: Edit, to template: Template, verify: Bool = true
    ) throws -> (template: Template, outcome: Outcome) {
        // A line that meets others closer than the lattice can tell apart is made again with ends
        // and crossings snapped to vertices farther off, up to a few hundredths of a unit.
        let radii: [Int64] = [1, 3, 9, 27]
        for (k, radius) in radii.enumerated() {
            do {
                return try apply(edit, to: template, verify: verify, snapRadius: radius)
            } catch EditFailure.collision(let why) {
                if k == radii.count - 1 {
                    var outcome = unchanged(template)
                    outcome.declined = Declined(reason: why)
                    return (template, outcome)
                }
            } catch let failure as EditFailure {
                var outcome = unchanged(template)
                switch failure {
                case .unsupported(let why): throw Failure.unsupported(why)
                case .degenerate(let why), .invalid(let why), .collision(let why): outcome.declined = Declined(reason: why)
                }
                return (template, outcome)
            }
        }
        return (template, unchanged(template))
    }

    private static func apply(
        _ edit: Edit, to template: Template, verify: Bool, snapRadius: Int64
    ) throws -> (template: Template, outcome: Outcome) {
        var work = try EditWork(template, snapRadius: snapRadius)
        switch edit {
        case .draw(let points, let closed):
            try work.draw(points, closed: closed)
        case .erase(let path, let radius):
            let lattice = path.prefix(maximumPoints).filter { $0.x.isFinite && $0.y.isFinite }.map(Lattice.clampedPoint)
            try work.erase(path: lattice, radius: Double(radius.isFinite ? min(max(radius, 0), Lattice.inputLimit) : 0))
        case .eraseLine(let point, let reach):
            guard point.x.isFinite, point.y.isFinite else { break }
            try work.eraseLine(
                near: Lattice.clampedPoint(point), reach: Int64((min(max(reach.isFinite ? reach : 0, 0), 1024) * Float(Lattice.unit)).rounded()))
        case .fill(let point, let color):
            guard point.x.isFinite, point.y.isFinite, color.x.isFinite, color.y.isFinite, color.z.isFinite else { break }
            // A color OKLab can hold: lightness 0 to 1, chroma axes within the gamuts' reach.
            let lab = pointwiseMin(pointwiseMax(color, SIMD3(0, -0.5, -0.5)), SIMD3(1, 0.5, 0.5))
            try work.fill(at: Lattice.clampedPoint(point), color: lab)
        }
        let s = work.summary
        guard s.lines > 0 || s.erased > 0 || s.fills > 0 else { return (template, unchanged(template)) }
        let (result, mapping) = try work.finish()
        if verify {
            let report = result.validate(minLabelRadius: LabelSizing.minimumRadius)
            guard report.isValid else {
                let why = "the result is not valid: \(report)"
                throw report.invalidEdges.isEmpty ? EditFailure.invalid(why) : EditFailure.collision(why)
            }
        }
        var outcome = Outcome()
        outcome.changed = true
        outcome.lines = s.lines
        outcome.joins = s.joins
        outcome.regionsSplit = s.regionsSplit
        outcome.regionsMerged = s.regionsMerged
        outcome.detailAreas = s.detailAreas
        outcome.strokes = s.strokes
        outcome.erased = s.erased
        outcome.fills = s.fills
        outcome.paintsAdded = s.paintsAdded
        outcome.tooSmall = s.declined
        outcome.touchedRegions = mapping.touched
        outcome.continued = mapping.continued
        return (result, outcome)
    }

    private static func unchanged(_ template: Template) -> Outcome {
        var outcome = Outcome()
        outcome.continued = Array(0..<template.regions.count)
        return outcome
    }

    /// Applies edits in order; one that is declined leaves the template as it was for the next.
    public static func apply(
        _ edits: [Edit], to template: Template, verify: Bool = true
    ) throws -> (template: Template, outcomes: [Outcome]) {
        var current = template
        var outcomes: [Outcome] = []
        for edit in edits {
            let (next, outcome) = try apply(edit, to: current, verify: verify)
            current = next
            outcomes.append(outcome)
        }
        return (current, outcomes)
    }
}
