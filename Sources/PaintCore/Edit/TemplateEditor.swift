import Foundation

/// Manual editing of a coloring-book template, for the app's Refine screen: the `Edit`s below, made
/// by Refine's tools (the Pen and Shapes a draw, Cell Edge a cell edge, Merge a merge, the Paint
/// Brush a brush, Bend Line and Move Edge a reshape, Move Number a moved label, the Eraser an
/// erase, the Line Eraser an erased line, Fill a fill, the Bucket and an area card's Only This Area
/// a painted area, Looks a look, Edit Paint and the area card's paints a repaint; a split is the
/// retired Color Splitter's, which no tool in the app makes now, kept so paintings made with it lay
/// as they did), applied to a finished `Template`, and nothing else. No photo, no edge map, no
/// segmentation, no smoothing or fitting is involved: a line is the polyline the painter drew
/// (quantized to `Template.coordinateQuantum`), an erasure cuts the ink at the edge of the eraser's
/// reach, a fill joins cells and picks a paint. Whatever an edit does not touch stays as it was,
/// byte for byte: regions, outlines, fills, numbers, paints. Edits are exact on the quantum grid
/// (`Lattice`), so the same edits give the same template on every device, and a template that
/// validates before an edit validates after it (`Template.validate(minLabelRadius:)`).
/// `docs/coloring-book.md` › The painter's edits says how an edit lands.
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
///   verbatim. Traced writing (`TemplateLineArt.writingStrokes`) is not the drawing: no end joins
///   it and no stretch closes a shape with it, so a letter never becomes an outline; where the line
///   cuts the region the letters it crosses are cut with it, each piece still writing. A draw
///   with `paints` (every draw the app makes now; one without is a draw from before, laid
///   exactly as it was) also nudges the line, and only the line, where it crosses an
///   edge within `inkWidth` of a junction (an end of an edge): it passes through the junction, so
///   the corner it would have clipped is no sliver too thin for a number, and the shape beside it
///   is cut cleanly. Then each piece it cut takes the photo's color there (`Paint`, read by
///   `painted(_:on:photo:)`): the paint nearest it within the book's own tolerance for one color
///   (`paintTolerance`), else a new paint of that color added last. Where that leaves one paint
///   on both sides of the line and the photo tells the sides apart, the side farther from it
///   takes its photo's color, or a shade of the paint toward it (`EditWork.paint`).
/// - **Split.** The retired Color Splitter's line (no tool in the app makes one now; a split
///   saved before is laid as ever), laid as a draw with paints is, but as an undrawn boundary
///   (`LineLayer.color`): it divides the paint and draws nothing. Its ends meet any edge, the
///   drawing's strokes are no part of it, and a stretch that closes nothing leaves nothing.
///   Each piece takes the photo's color there as a drawn line's pieces do (`paintTolerance`),
///   else a new paint; a split that divides no area, or leaves the same paint on both sides of its boundary,
///   is declined.
/// - **Cell edge.** Refine's Cell Edge: a split that takes no paints, so one cell becomes two of
///   the paint it had, for the painter to paint one of them. A cell edge that divides no area is
///   declined; one that leaves the same paint on both sides is what it is for.
/// - **Merge.** Refine's Merge: a drag across cells joins them into one. The regions under the
///   path, in the order it first enters them, from the one under its first point: each next one
///   joins if it shares an edge with those joined so far, else it is passed over. Every edge
///   between them goes, ink and all, leaving no stroke (the strokes inside them stay); the joined
///   area has the first region's paint and number, and is a detail area only if the first was.
///   A paint left with no area leaves the palette as Only This Area's does. A merge that joins
///   fewer than two areas is declined, one whose drag never leaves the area it began in for
///   `mergeStaysInOneArea` (Refine says it is one area already).
/// - **Paint brush.** Refine's Paint Brush: everything within `radius` of the stroke (a disc for a
///   dab) becomes the paint a fill would take. The footprint's outline is laid as a closed cell
///   edge is, undrawn and clipped to the canvas, a piece with no room for a number not cut off;
///   every area inside it then takes the paint, ink untouched, so the areas either side of a
///   drawn line stay two cells. Areas of that paint meeting across an undrawn boundary, one of
///   them inside or the boundary the outline itself, become one, so a stroke along a cell's edge
///   grows the cell. A paint left with no area leaves the palette. A stroke whose areas all
///   have its paint already changes nothing; one with no area inside it is declined. Its color is one of the
///   template on screen, as Only This Area's is.
/// - **Reshape.** Refine's Bend Line and Move Edge: the line nearest a point (an edge, drawn or
///   undrawn but not the canvas's frame, from junction to junction as the line eraser finds it;
///   or a drawn stroke) is dragged, of the lines its target grabs (`ReshapeTarget`: Bend Line's
///   drawn lines alone, Move Edge's boundaries between cells alone, or any), its point nearest the touch going where the finger lifts and
///   the rest following less the farther along the line, none past three times the drag (at
///   least 24 units) or at its ends, which stay on their junctions (a stroke's free end within
///   that moves whole). Points are added along the stretch that moves, so a big bend is smooth, and
///   strokes ending on the line are carried with it. The line keeps its ink or its lack of it;
///   the regions on its sides keep their paints, their outlines follow it, and their numbers stay
///   while they have room. Declined when the line would cross itself or another, leave the
///   canvas, carry an island or a stroke across, or leave an area too little room for its number.
/// - **Move number.** Refine's Move Number: the number nearest a point, within its radius and the
///   edit's reach (`labelNear`), goes to another inside its own region, where a number of its
///   digits fits (a detail area's by its own floor), off the strokes in the region and clear of
///   its other numbers; its size is the room there (which no spot of the region exceeds).
///   Nothing else changes. An edit that plans the region's numbers again later keeps
///   it there while it keeps most of the room, and may move it otherwise.
/// - **Erase.** Ink within the radius of the path is cut out exactly at the edge of the reach.
///   Ink between two regions that this breaks lets their paint through: the regions merge (the
///   larger keeps its index and its paint) and the ink left of that boundary stays as strokes.
///   Undrawn (paint) edges are never touched.
/// - **Erase line.** The line under a point is taken out from junction to junction, the regions
///   it kept apart merging as above.
/// - **Fill.** The closed shape under the point, bounded by ink (the tapped region alone if it
///   reaches the canvas frame), becomes one detail area painted with the paint within a
///   just-noticeable difference of the color, else a new paint added last.
/// - **Paint one area.** Refine's Only This Area: the region under the point alone, flooding
///   nothing, takes the paint a fill would; no other region's paint changes. It stays a detail
///   area or not as it was, its numbers sized for the new paint's digits (an area without room
///   for them is declined). A paint it leaves with no area goes, the numbers after it closing up
///   as a repaint's merge closes them, and where the area then meets one of its new paint across
///   an undrawn boundary the two become one area. Its color is one of the template on screen
///   (Refine's picker and palette chips read it with every look in it), so looks and repaints
///   laid before it leave it as sent: a paint's own color lands on that paint.
/// - **Look, repaint.** Paints alone change color (Refine's Looks and Edit Paint): a look over all of them, or
///   one paint with or without its family (`recolor(_:by:)`). Paints that land within a
///   just-noticeable difference of each other become one, and areas that then share a paint
///   across an undrawn boundary one area. Edits laid after one bring their colors through it
///   (`apply(_:to:verify:)` for a list, `EditTrail`), so a line drawn under a look takes the look.
public enum TemplateEditor {
    /// What a list of edits makes of a given template, as a number kept with the edits a
    /// painting saves (the app's `TemplateRefinements.editorVersion`). Bump in the same commit as
    /// any change to what a list of edits makes on a given template (`EditGoldenTests` pins it),
    /// so saved edits record which editor laid them. 1 is the editor from October 26, 2026, which
    /// keeps writing out of drawn lines and measures a piece short of its number finely; edits
    /// saved before it record none.
    public static let version = 1

    /// Why a Merge whose drag never left the area it began in is declined.
    public static let mergeStaysInOneArea = "the merge stays in one area"

    public enum Edit: Sendable, Equatable {
        /// A polyline; `closed` joins the last point back to the first. `paints`, the photo's
        /// colors of the pieces it cuts, nil for a draw made before lines took them (no nudge, no
        /// recoloring: such a draw is laid as it always was).
        case draw(points: [SIMD2<Float>], closed: Bool = false, paints: [Paint]? = nil)
        /// The Color Splitter's line: `points` divide the paint along an undrawn boundary, and the
        /// pieces take `paints`.
        case split(points: [SIMD2<Float>], closed: Bool = false, paints: [Paint] = [])
        /// Refine's Cell Edge: `points` divide a cell along an undrawn boundary, both pieces keeping
        /// its paint.
        case cellEdge(points: [SIMD2<Float>], closed: Bool = false)
        /// Refine's Merge: the regions `points` cross, joined into the first.
        case merge(points: [SIMD2<Float>])
        /// Refine's Paint Brush: what lies within `radius` of `path` painted `color` (OKLab, a color
        /// of the template on screen, as `paintArea`'s).
        case brush(path: [SIMD2<Float>], radius: Float, color: SIMD3<Float>)
        /// Refine's Bend Line and Move Edge: the line nearest `from` within `reach` of the kind
        /// `target` grabs, its chain from junction to junction, bent so that its point nearest
        /// `from` goes to `to`.
        case reshape(from: SIMD2<Float>, to: SIMD2<Float>, reach: Float = TemplateEditor.tapReach, target: ReshapeTarget = .any)
        /// Refine's Move Number: the number nearest `from` within its radius and `reach`
        /// (`labelNear`) moved to `to`, inside its region.
        case moveLabel(from: SIMD2<Float>, to: SIMD2<Float>, reach: Float = TemplateEditor.tapReach)
        /// The eraser dragged along a path, reaching `radius` either side.
        case erase(path: [SIMD2<Float>], radius: Float)
        /// The drawn line nearest `point` within `reach`, from junction to junction.
        case eraseLine(at: SIMD2<Float>, reach: Float = TemplateEditor.tapReach)
        /// The shape under `point`, painted `color` (OKLab, as `LineEdit.photoColor` reads it).
        case fill(at: SIMD2<Float>, color: SIMD3<Float>)
        /// The region under `point` alone painted `color` (OKLab, a color of the template on
        /// screen, which looks laid before it don't move).
        case paintArea(at: SIMD2<Float>, color: SIMD3<Float>)
        /// Every paint in `look` at `strength` (0 to 1); `lightness`, the painting's lightness
        /// quantiles when the look was chosen (`TemplateEditor.look(_:strength:on:)`).
        case look(Look, strength: Float, lightness: [Float] = [])
        /// The paint of color `from` made `to` (OKLab); with `family`, the paints of about its
        /// hue (or near it, for a gray) move along with it.
        case repaint(from: SIMD3<Float>, to: SIMD3<Float>, family: Bool)
    }

    /// The lines a reshape (`Edit.reshape`) may grab: Bend Line (an Ink tool) grabs only what is
    /// drawn, Move Edge (a Cells tool) only the boundaries between cells, drawn or not.
    public enum ReshapeTarget: String, Sendable {
        /// Any line: an edge, drawn or undrawn, or a drawn stroke (every reshape before targets).
        case any
        /// Drawn lines only: edges of a drawn layer (`LineLayer.isDrawn`) and drawn strokes.
        case ink
        /// Boundary edges between two regions only, of any layer; never a stroke.
        case edge
    }

    /// The photo's color of a piece a drawn line cuts: `at`, a point inside the piece (its number's
    /// spot when it was read), and `color`, OKLab. A paint whose point is in no piece the line cut
    /// (the line laid on another base) changes nothing.
    public struct Paint: Sendable, Equatable {
        public var at: SIMD2<Float>
        public var color: SIMD3<Float>

        public init(at: SIMD2<Float>, color: SIMD3<Float>) {
            self.at = at
            self.color = color
        }
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
        /// Pieces a line's paints gave another paint, and an area painted alone (`paintArea`).
        public var recolored = 0
        /// Paints a look or a repaint gave another color, and paints that left the palette: made
        /// one with another, or left with no area by an area painted alone.
        public var paintsChanged = 0
        public var paintsMerged = 0
        /// Lines a reshape moved: its chain, and the strokes whose ends it carried.
        public var reshaped = 0
        /// Numbers Move Number moved.
        public var labelsMoved = 0
        /// Where a cut was not made because the piece had no room for a number: the piece's
        /// centre.
        public var tooSmall: [SIMD2<Float>] = []
        /// Regions of the new template a drawn line cut a region into (each piece, the one that
        /// kept the region's index too).
        public var pieces: [Int] = []
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
    /// Points of one edit beyond this are ignored (the app's help has already thinned them), and so
    /// are paints of one drawn line or split beyond as many (a hand-made `refinements.json` alone
    /// could carry more).
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
        try apply(edit, to: template, verify: verify, reading: false)
    }

    /// `reading`: the edit is laid only to read its pieces (`painted`), so a split is not yet held
    /// to having different paints on its two sides.
    static func apply(
        _ edit: Edit, to template: Template, verify: Bool, reading: Bool
    ) throws -> (template: Template, outcome: Outcome) {
        // A line that meets others closer than the lattice can tell apart is made again with ends
        // and crossings snapped to vertices farther off, up to a few hundredths of a unit.
        let radii: [Int64] = [1, 3, 9, 27]
        for (k, radius) in radii.enumerated() {
            do {
                return try apply(edit, to: template, verify: verify, snapRadius: radius, reading: reading)
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
        _ edit: Edit, to template: Template, verify: Bool, snapRadius: Int64, reading: Bool
    ) throws -> (template: Template, outcome: Outcome) {
        var work = try EditWork(template, snapRadius: snapRadius)
        switch edit {
        case .draw(let points, let closed, let paints):
            try work.draw(points, closed: closed, nudging: paints != nil)
            if let paints { try work.paint(Array(paints.prefix(maximumPoints))) }
        case .split(let points, let closed, let paints):
            work.splitting = true
            try work.draw(points, closed: closed, nudging: true)
            guard work.summary.regionsSplit > 0 else { throw EditFailure.invalid("the split divides no area") }
            try work.paint(Array(paints.prefix(maximumPoints)))
            if !reading { try work.checkSplitPaints() }
        case .cellEdge(let points, let closed):
            work.splitting = true
            try work.draw(points, closed: closed, nudging: true)
            guard work.summary.regionsSplit > 0 else { throw EditFailure.invalid("the cell edge divides no area") }
            try work.paint([])
        case .merge(let points):
            let lattice = points.prefix(maximumPoints).filter { $0.x.isFinite && $0.y.isFinite }.map(Lattice.clampedPoint)
            try work.merge(along: lattice)
        case .brush(let path, let radius, let color):
            guard color.x.isFinite, color.y.isFinite, color.z.isFinite else { break }
            let lattice = path.prefix(maximumPoints).filter { $0.x.isFinite && $0.y.isFinite }.map(Lattice.clampedPoint)
            // No brush is wider than the canvas.
            let widest = Float(max(template.width, template.height))
            let reach = min(max(radius.isFinite ? radius : 0, 0), widest)
            try work.brush(path: lattice, radius: Int64((reach * Float(Lattice.unit)).rounded()), color: clampedLab(color))
        case .reshape(let from, let to, let reach, let target):
            guard from.x.isFinite, from.y.isFinite, to.x.isFinite, to.y.isFinite else { break }
            try work.reshape(from: Lattice.clampedPoint(from), to: Lattice.clampedPoint(to), reach: latticeReach(reach), target: target)
        case .moveLabel(let from, let to, let reach):
            guard from.x.isFinite, from.y.isFinite, to.x.isFinite, to.y.isFinite else { break }
            try work.moveLabel(from: Lattice.position(Lattice.clampedPoint(from)), to: Lattice.clampedPoint(to), reach: labelReach(reach))
        case .erase(let path, let radius):
            let lattice = path.prefix(maximumPoints).filter { $0.x.isFinite && $0.y.isFinite }.map(Lattice.clampedPoint)
            try work.erase(path: lattice, radius: Double(radius.isFinite ? min(max(radius, 0), Lattice.inputLimit) : 0))
        case .eraseLine(let point, let reach):
            guard point.x.isFinite, point.y.isFinite else { break }
            try work.eraseLine(near: Lattice.clampedPoint(point), reach: latticeReach(reach))
        case .fill(let point, let color), .paintArea(let point, let color):
            guard point.x.isFinite, point.y.isFinite, color.x.isFinite, color.y.isFinite, color.z.isFinite else { break }
            // A color OKLab can hold: lightness 0 to 1, chroma axes within the gamuts' reach.
            let lab = pointwiseMin(pointwiseMax(color, SIMD3(0, -0.5, -0.5)), SIMD3(1, 0.5, 0.5))
            if case .fill = edit {
                try work.fill(at: Lattice.clampedPoint(point), color: lab)
            } else {
                try work.paintArea(at: Lattice.clampedPoint(point), color: lab)
            }
        case .look, .repaint:
            try work.recolor(edit)
        }
        let s = work.summary
        guard s.lines > 0 || s.erased > 0 || s.fills > 0 || s.recolored > 0 || s.paintsChanged > 0 || s.paintsMerged > 0
            || s.regionsMerged > 0 || s.reshaped > 0 || s.labelsMoved > 0
        else {
            return (template, unchanged(template))
        }
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
        outcome.recolored = s.recolored
        outcome.paintsChanged = s.paintsChanged
        outcome.paintsMerged = s.paintsMerged
        outcome.reshaped = s.reshaped
        outcome.labelsMoved = s.labelsMoved
        outcome.pieces = mapping.pieces
        outcome.tooSmall = s.declined
        outcome.touchedRegions = mapping.touched
        outcome.continued = mapping.continued
        return (result, outcome)
    }

    /// `edit` with the photo's colors of the pieces it cuts, when it is a draw without them: the
    /// line laid on `template` as a draw with paints lays it (nudged), and each piece's color read
    /// over its pixels (`LineEdit.photoColor(ofRegion:in:image:)`) at its number. Another edit, or
    /// one that changes nothing, comes back as a draw that lays the same way with no paints.
    public static func painted(_ edit: Edit, on template: Template, photo: RGBAImage) -> Edit {
        let bare: Edit, wrap: ([Paint]) -> Edit
        switch edit {
        case .draw(let points, let closed, nil):
            bare = .draw(points: points, closed: closed, paints: [])
            wrap = { .draw(points: points, closed: closed, paints: $0) }
        case .split(let points, let closed, let given) where given.isEmpty:
            bare = edit
            wrap = { .split(points: points, closed: closed, paints: $0) }
        default:
            return edit
        }
        guard let (result, outcome) = try? apply(bare, to: template, verify: true, reading: true), outcome.changed,
              outcome.declined == nil
        else { return bare }
        let paints = outcome.pieces.compactMap { piece -> Paint? in
            guard let label = result.labels(ofRegion: piece).first,
                  let color = LineEdit.photoColor(ofRegion: piece, in: result, image: photo) else { return nil }
            return Paint(at: label.position, color: color)
        }
        return wrap(paints)
    }

    private static func unchanged(_ template: Template) -> Outcome {
        var outcome = Outcome()
        outcome.continued = Array(0..<template.regions.count)
        return outcome
    }

    /// Applies edits in order; one that is declined leaves the template as it was for the next.
    /// Each brings its colors through the looks and repaints made before it (`recolored`).
    public static func apply(
        _ edits: [Edit], to template: Template, verify: Bool = true
    ) throws -> (template: Template, outcomes: [Outcome]) {
        var current = template
        var outcomes: [Outcome] = []
        var recolors: [Edit] = []
        for edit in edits {
            let (next, outcome) = try apply(recolored(edit, by: recolors), to: current, verify: verify)
            if isRecolor(edit), outcome.changed { recolors.append(edit) }
            current = next
            outcomes.append(outcome)
        }
        return (current, outcomes)
    }
}
