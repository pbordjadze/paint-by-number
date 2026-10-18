import Foundation

/// Why an edit could not be made. `TemplateEditor` turns these into a declined edit: the
/// template it was asked about is returned as it was.
enum EditFailure: Error, Equatable {
    /// The template is not one the editor works on (no line art, or a canvas it cannot bound).
    case unsupported(String)
    /// The edit meets the drawing where exact arithmetic gives no single answer (a line laid
    /// along another for a stretch).
    case degenerate(String)
    /// Making the edit would break an invariant of the template.
    case invalid(String)
    /// Lines lie closer than the lattice can tell apart, and the arrangement they make has
    /// outlines that touch or overlap.
    case collision(String)
}

/// A directed use of an edge: the edge walked forwards or backwards.
struct HalfEdge: Hashable {
    var edge: Int
    var reversed: Bool
    var twin: HalfEdge { HalfEdge(edge: edge, reversed: !reversed) }
}

/// A template being edited. Geometry stays in the template's own arrays and only grows (new
/// points, edges, regions); what an edit replaces is flagged dead, or overridden per region
/// (`rings`, `labels`), until `finish` lays the survivors out again. Everything an edit leaves
/// alone is copied through as it was.
struct EditWork {
    struct WorkRing: Equatable {
        var refs: [EdgeRef]
        var isHole: Bool
    }

    struct WorkStroke {
        var points: [SIMD2<Float>]
        var layer: UInt8
        var weight: UInt8
        var region: Int
        /// Traced writing (`TemplateLineArt.writingStrokes`), kept by the pieces it is cut into.
        var writing = false
        var alive = true
    }

    var t: Template
    var layers: [UInt8]
    var weights: [UInt8]
    var strokes: [WorkStroke]
    /// Strokes from this index on are the edit's; `movedStrokes` are older ones given another region.
    let originalStrokeCount: Int
    var movedStrokes: Set<Int> = []
    var edgeDead: [Bool]
    /// Edges whose points or sides this edit changed or made: the ones to validate and to keep
    /// stored with `left < right`.
    var edgeDirty: [Bool]
    var regionAlive: [Bool]
    var regionDetail: [Bool]
    /// Regions whose paint, outline or numbers changed (or that an edit made): the strokes in them
    /// are checked against the pixel map.
    var regionTouched: [Bool]
    var rings: [Int: [WorkRing]] = [:]
    var labels: [Int: [Label]] = [:]
    /// Regions to triangulate again, and those whose numbers must be checked against the
    /// outline they now have.
    var remesh: Set<Int> = []
    var verifyLabels: Set<Int> = []
    /// Lines this edit left inside a region as strokes: numbers keep off them.
    var freshInk: [Int: [[SIMD2<Float>]]] = [:]
    var edgeBoxes: [Int: (lo: LatticePoint, hi: LatticePoint)] = [:]
    /// The distance between a region's numbers (`RegionFills.addExtraLabels`' spacing).
    let labelSpacing: Float
    /// What the edit did, counted.
    struct Tally {
        var lines = 0, joins = 0, regionsSplit = 0, regionsMerged = 0, detailAreas = 0, strokes = 0, erased = 0
        var fills = 0, paintsAdded = 0, recolored = 0
        var declined: [SIMD2<Float>] = []
        var touched = Set<Int>()
        /// The pieces drawn lines cut regions into (`splitRegion`).
        var pieces = Set<Int>()
    }
    var summary = Tally()
    /// The region each merged-away region continues as.
    var successor: [Int: Int] = [:]

    /// See `snapped`.
    let snapRadius: Int64
    /// The edit is a split (`TemplateEditor.Edit.split`): the line it lays is an undrawn boundary,
    /// its ends meet any edge, and what of it closes nothing leaves no stroke.
    var splitting = false
    /// The boundaries a split laid (the chains of its line; `drawRun`).
    var splitEdges: [Int] = []

    init(_ template: Template, snapRadius: Int64 = 1) throws {
        self.snapRadius = snapRadius
        guard template.width > 0, template.height > 0,
              template.width <= Lattice.maximumCanvas, template.height <= Lattice.maximumCanvas
        else { throw EditFailure.unsupported("canvas size") }
        guard let art = template.lineArt, art.edgeLayers.count == template.edges.count,
              art.edgeWeights.count == template.edges.count
        else { throw EditFailure.unsupported("the template has no line art") }
        t = template
        layers = art.edgeLayers
        weights = art.edgeWeights
        strokes = art.strokes.enumerated().map { i, s in
            WorkStroke(
                points: Array(art.strokePoints[Int(s.pointStart)..<Int(s.pointStart) + Int(s.pointCount)]),
                layer: s.layer, weight: s.weight, region: Int(s.region), writing: art.isWritingStroke(i))
        }
        originalStrokeCount = art.strokes.count
        edgeDead = [Bool](repeating: false, count: template.edges.count)
        edgeDirty = edgeDead
        regionAlive = [Bool](repeating: true, count: template.regions.count)
        regionDetail = (0..<template.regions.count).map { template.isDetailRegion($0) }
        regionTouched = [Bool](repeating: false, count: template.regions.count)
        let radii = template.regions.map(\.inscribedRadius).filter { $0 >= 1 }.sorted()
        let typical = min(max(radii.isEmpty ? 4 : radii[radii.count / 2], 3), 8)
        labelSpacing = max(10 * typical, Float(max(template.width, template.height)) / 16)
    }

    // MARK: - Geometry access

    func lattice(of e: Int) -> [LatticePoint] {
        let edge = t.edges[e]
        return t.points[Int(edge.pointStart)..<Int(edge.pointStart) + Int(edge.pointCount)].map(Lattice.point)
    }

    func latticePoint(_ e: Int, _ index: Int) -> LatticePoint {
        Lattice.point(t.points[Int(t.edges[e].pointStart) + index])
    }

    mutating func box(of e: Int) -> (lo: LatticePoint, hi: LatticePoint) {
        if let b = edgeBoxes[e] { return b }
        let edge = t.edges[e]
        var lo = LatticePoint(repeating: .max), hi = LatticePoint(repeating: .min)
        for p in t.points[Int(edge.pointStart)..<Int(edge.pointStart) + Int(edge.pointCount)] {
            let q = Lattice.point(p)
            lo = pointwiseMin(lo, q)
            hi = pointwiseMax(hi, q)
        }
        edgeBoxes[e] = (lo, hi)
        return (lo, hi)
    }

    func isFrame(_ e: Int) -> Bool { t.edges[e].right == BoundaryEdge.outside }
    func isInked(_ e: Int) -> Bool { layers[e] != LineLayer.color.rawValue }

    mutating func setPoints(_ e: Int, _ points: [LatticePoint]) {
        t.edges[e].pointStart = UInt32(t.points.count)
        t.edges[e].pointCount = UInt32(points.count)
        t.points.append(contentsOf: points.map(Lattice.position))
        edgeBoxes[e] = nil
        edgeDirty[e] = true
    }

    mutating func addEdge(left: Int, right: Int?, points: [LatticePoint], layer: UInt8, weight: UInt8) -> Int {
        let e = t.edges.count
        t.edges.append(BoundaryEdge(
            left: UInt32(left), right: right.map { UInt32($0) } ?? BoundaryEdge.outside,
            pointStart: UInt32(t.points.count), pointCount: UInt32(points.count)))
        t.points.append(contentsOf: points.map(Lattice.position))
        layers.append(layer)
        weights.append(weight)
        edgeDead.append(false)
        edgeDirty.append(true)
        return e
    }

    mutating func kill(_ e: Int) {
        edgeDead[e] = true
        edgeBoxes[e] = nil
    }

    func left(_ e: Int) -> Int { Int(t.edges[e].left) }
    /// The region on the right, nil outside the canvas.
    func right(_ e: Int) -> Int? { t.edges[e].right == BoundaryEdge.outside ? nil : Int(t.edges[e].right) }

    func start(_ h: HalfEdge) -> LatticePoint {
        let edge = t.edges[h.edge]
        return Lattice.point(t.points[Int(edge.pointStart) + (h.reversed ? Int(edge.pointCount) - 1 : 0)])
    }

    func end(_ h: HalfEdge) -> LatticePoint { start(h.twin) }

    /// The first step of a half edge, leaving its start.
    func heading(_ h: HalfEdge) -> LatticePoint {
        let edge = t.edges[h.edge], s = Int(edge.pointStart), n = Int(edge.pointCount)
        return h.reversed
            ? Lattice.point(t.points[s + n - 2]) &- Lattice.point(t.points[s + n - 1])
            : Lattice.point(t.points[s + 1]) &- Lattice.point(t.points[s])
    }

    /// The way back from a half edge's end along its last step.
    func arrival(_ h: HalfEdge) -> LatticePoint { heading(h.twin) }

    /// A half edge's points in the order it is walked.
    func walk(_ h: HalfEdge) -> [LatticePoint] {
        let pts = lattice(of: h.edge)
        return h.reversed ? pts.reversed() : pts
    }

    // MARK: - Rings

    func ringsOf(_ r: Int) -> [WorkRing] {
        if let rings = rings[r] { return rings }
        let region = t.regions[r]
        return (0..<Int(region.ringCount)).map { k in
            let ring = t.rings[Int(region.ringStart) + k]
            return WorkRing(
                refs: Array(t.ringEdges[Int(ring.edgeStart)..<Int(ring.edgeStart) + Int(ring.edgeCount)]), isHole: ring.isHole)
        }
    }

    mutating func setRings(_ r: Int, _ new: [WorkRing]) { rings[r] = new }

    func halves(_ ring: WorkRing) -> [HalfEdge] { ring.refs.map { HalfEdge(edge: Int($0.edge), reversed: $0.reversed) } }

    /// A ring as a polygon (no closing point).
    func polygon(_ ring: WorkRing) -> [LatticePoint] { polygon(halves(ring)) }

    func polygon(_ cycle: [HalfEdge]) -> [LatticePoint] {
        var out: [LatticePoint] = []
        for h in cycle { out.append(contentsOf: walk(h).dropLast()) }
        return out
    }

    func polygons(of r: Int) -> [[LatticePoint]] { ringsOf(r).map(polygon) }

    /// Where `p` lies against region `r`: inside, on its outline, or outside. With `scale`,
    /// `p` is in units of 1/`scale` of a lattice step (a midpoint is twice a sum).
    func contains(_ r: Int, _ p: LatticePoint, scale: Int64 = 1) -> Lattice.Containment {
        let rings = polygons(of: r)
        return Lattice.contains(scale == 1 ? rings : rings.map { $0.map { $0 &* scale } }, p)
    }

    mutating func replaceRef(in region: Int, edge e: Int, reversed: Bool, with refs: [EdgeRef]) {
        var all = ringsOf(region)
        search: for k in all.indices {
            for i in all[k].refs.indices where Int(all[k].refs[i].edge) == e && all[k].refs[i].reversed == reversed {
                all[k].refs.replaceSubrange(i...i, with: refs)
                break search
            }
        }
        rings[region] = all
    }

    // MARK: - Splitting an edge

    /// Cuts edge `e` at the given points, each lying on (or, within a lattice step, beside)
    /// segment `segment` of its polyline, and returns the pieces in order, the first keeping
    /// the edge's index. A point that is an end of the edge is no cut; one that is not yet a
    /// vertex becomes one. The regions on either side have their rings follow.
    @discardableResult
    mutating func split(edge e: Int, at inserts: [(segment: Int, point: LatticePoint)]) -> [Int] {
        guard !inserts.isEmpty else { return [e] }
        let cut = Self.cut(lattice(of: e), at: inserts)
        guard !cut.parts.isEmpty else { return [e] }
        var pieces = [e]
        let edge = t.edges[e], layer = layers[e], weight = weights[e]
        setPoints(e, cut.parts[0])
        for part in cut.parts.dropFirst() {
            pieces.append(addEdge(left: Int(edge.left), right: right(e), points: part, layer: layer, weight: weight))
        }
        replaceRef(
            in: Int(edge.left), edge: e, reversed: false, with: pieces.map { EdgeRef(edge: UInt32($0), reversed: false) })
        if let r = right(e) {
            replaceRef(in: r, edge: e, reversed: true, with: pieces.reversed().map { EdgeRef(edge: UInt32($0), reversed: true) })
        }
        // A split's own boundary cut by a later run of it stays the split's in every part.
        if splitting, splitEdges.contains(e) { splitEdges.append(contentsOf: pieces.dropFirst()) }
        if cut.grown { noteNewVertex(on: e) }
        return pieces
    }

    /// The parts of polyline `old` cut at the given points (each on or beside segment
    /// `segment`): in order along it, new points made vertices, a point that is an end of the
    /// polyline or repeats a cut being no cut. `parts` is empty when nothing is cut. `grown`:
    /// a cut point was not a vertex before.
    static func cut(_ old: [LatticePoint], at inserts: [(segment: Int, point: LatticePoint)]) -> (parts: [[LatticePoint]], grown: Bool) {
        let ordered = inserts.sorted { a, b in
            if a.segment != b.segment { return a.segment < b.segment }
            let d = old[a.segment + 1] &- old[a.segment]
            return Lattice.dot(a.point &- old[a.segment], d) < Lattice.dot(b.point &- old[b.segment], d)
        }
        var points: [LatticePoint] = []
        var grown = false
        var next = 0
        for i in 0..<(old.count - 1) {
            points.append(old[i])
            while next < ordered.count && ordered[next].segment == i {
                let p = ordered[next].point
                next += 1
                guard p != points[points.count - 1], p != old[i + 1] else { continue }
                points.append(p)
                grown = true
            }
        }
        points.append(old[old.count - 1])
        let cutAt = Set(ordered.map(\.point))
        let cuts = (1..<max(points.count - 1, 1)).filter { cutAt.contains(points[$0]) }
        guard !cuts.isEmpty else { return ([], false) }
        let bounds = [0] + cuts + [points.count - 1]
        return ((0..<(bounds.count - 1)).map { Array(points[bounds[$0]...bounds[$0 + 1]]) }, grown)
    }

    /// Adds a vertex to segment `segment` of edge `e` without cutting it: the polyline passes
    /// through `p` from then on.
    mutating func insertVertex(edge e: Int, segment: Int, _ p: LatticePoint) {
        var pts = lattice(of: e)
        guard p != pts[segment], p != pts[segment + 1] else { return }
        pts.insert(p, at: segment + 1)
        setPoints(e, pts)
        noteNewVertex(on: e)
    }

    /// An edge has a vertex the regions on its sides did not: their fills need it, and their
    /// numbers were measured against the outline without it.
    mutating func noteNewVertex(on e: Int) {
        for r in [left(e), right(e)].compactMap({ $0 }) {
            remesh.insert(r)
            verifyLabels.insert(r)
        }
    }

    // MARK: - Regions and strokes

    mutating func addRegion(color: UInt32, detail: Bool) -> Int {
        let r = t.regions.count
        t.regions.append(Region(colorIndex: color, area: 0, bounds: .empty, inscribedRadius: 0))
        regionAlive.append(true)
        regionDetail.append(detail)
        regionTouched.append(true)
        return r
    }

    mutating func addStroke(_ points: [LatticePoint], layer: UInt8, weight: UInt8, region: Int) {
        var clean: [LatticePoint] = []
        for p in points where p != clean.last { clean.append(p) }
        guard clean.count >= 2 else { return }
        strokes.append(WorkStroke(points: clean.map(Lattice.position), layer: layer, weight: weight, region: region))
        freshInk[region, default: []].append(clean.map(Lattice.position))
        summary.strokes += 1
        summary.touched.insert(region)
    }

    func area(of r: Int) -> Double {
        if let rings = rings[r] {
            return rings.reduce(0.0) { $0 + Double(Lattice.area2(polygon($1))) } / (2 * Double(Lattice.unit * Lattice.unit))
        }
        return Double(t.regions[r].area)
    }

    // MARK: - Locating

    /// The region a point lies in (`scale` as for `contains`), found exactly. A point on an
    /// outline goes to the first region that has it there.
    func locate(_ p: LatticePoint, scale: Int64 = 1) -> Int? {
        let x = min(max(Int(p.x / (scale * Lattice.unit)), 0), t.width - 1)
        let y = min(max(Int(p.y / (scale * Lattice.unit)), 0), t.height - 1)
        var candidates: [Int] = []
        func consider(_ dx: Int, _ dy: Int) {
            guard t.regionMap.contains(x: x + dx, y: y + dy) else { return }
            let r = Int(t.regionMap[x + dx, y + dy])
            if r < regionAlive.count, regionAlive[r], !candidates.contains(r) { candidates.append(r) }
        }
        consider(0, 0)
        for dy in -1...1 { for dx in -1...1 where dx != 0 || dy != 0 { consider(dx, dy) } }
        var onOutline: Int?
        for r in candidates {
            switch contains(r, p, scale: scale) {
            case .inside: return r
            case .boundary: onOutline = onOutline ?? r
            case .outside: break
            }
        }
        // The pixel's neighbourhood misses the region only where its outline has drifted far
        // from the pixels; every region is searched then.
        for r in 0..<regionAlive.count where regionAlive[r] && !candidates.contains(r) {
            switch contains(r, p, scale: scale) {
            case .inside: return r
            case .boundary: onOutline = onOutline ?? r
            case .outside: break
            }
        }
        return onOutline
    }
}
