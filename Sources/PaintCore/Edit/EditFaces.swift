import Foundation

extension EditWork {
    // MARK: - Tracing faces

    /// The boundaries of the faces on the left of `halves`, each a cycle of half edges. At a
    /// vertex the walk leaves along the half edge that turns most sharply to the left (the first
    /// clockwise from the way it came, in raw coordinates where a face's outer boundary runs
    /// counter-clockwise): the rule `BoundaryGraph.assembleRings` follows on the pixel lattice,
    /// so a region that meets itself at a vertex gets the rings it always had.
    func trace(_ halves: [HalfEdge]) throws -> [[HalfEdge]] {
        let starts = halves.map(start), ends = halves.map(end)
        let heads = halves.map(heading), backs = halves.map(arrival)
        var outgoing: [LatticePoint: [Int]] = [:]
        for i in halves.indices { outgoing[starts[i], default: []].append(i) }
        var used = [Bool](repeating: false, count: halves.count)
        var cycles: [[HalfEdge]] = []
        for first in halves.indices where !used[first] {
            var cycle: [HalfEdge] = []
            var current = first
            repeat {
                used[current] = true
                cycle.append(halves[current])
                guard let candidates = outgoing[ends[current]] else { throw EditFailure.collision("an outline is open") }
                var best = candidates[0]
                for c in candidates.dropFirst() where Lattice.clockwiseBefore(from: backs[current], heads[c], heads[best]) {
                    best = c
                }
                current = best
                if used[current] && current != first { throw EditFailure.collision("outlines share a half edge") }
            } while current != first
            cycles.append(cycle)
        }
        return cycles
    }

    /// One area the lines cut a region into: its outer boundary and the holes in it.
    struct Piece {
        var outer: [HalfEdge]
        var holes: [[HalfEdge]]
        var rings: [[LatticePoint]]
        var area2: Int64
        var plan: LabelPlan?
    }

    // MARK: - Splitting a region

    /// Cuts region `r` along the chain edges `chains` (provisional edges inside it, `left` and
    /// `right` both `r`, with the layer and weight they get as a boundary), wherever they close
    /// off part of it together with its outline. A chain edge that closes nothing (a dangling
    /// end, a slit between a ring and its hole) is not a boundary: it goes back to being a
    /// stroke. A piece with no room for a number, even a detail area's, is not cut off: the
    /// chain edges round it go back to strokes too, and the cell stays as it was.
    ///
    /// Each piece keeps the paint of the region (a piece with room only for a detail area's
    /// number becomes one), the largest keeps the region's index. The numbers stay where they
    /// were while their room does (`labelPlan`), the pixels go to the piece their centre is in,
    /// and the strokes of the region to the piece they lie in.
    mutating func splitRegion(_ r: Int, chains: [Int], fresh: Set<Int>) throws {
        let original = ringsOf(r)
        var ringsAt: [LatticePoint: [Int]] = [:]
        for (k, ring) in original.enumerated() {
            for h in halves(ring) { ringsAt[start(h), default: []].append(k) }
        }
        // The rings the chains attach to, and those that touch them at a vertex: tracing leaves
        // out no half edge a vertex of the traced ones also has.
        var seeded = Set<Int>()
        var queue: [Int] = []
        for c in chains {
            for p in [latticePoint(c, 0), latticePoint(c, Int(t.edges[c].pointCount) - 1)] {
                for k in ringsAt[p] ?? [] where seeded.insert(k).inserted { queue.append(k) }
            }
        }
        while let k = queue.popLast() {
            for h in halves(original[k]) {
                for j in ringsAt[start(h)] ?? [] where seeded.insert(j).inserted { queue.append(j) }
            }
        }
        let ringHalves = seeded.sorted().flatMap { halves(original[$0]) }
        let color = t.regions[r].colorIndex
        let wasDetail = regionDetail[r]
        let hints = hints(from: [r])

        var live = Set(chains)
        var pruned: [Int] = []
        var pieces: [Piece] = []
        while true {
            if live.isEmpty { break }
            let cycles = try trace(ringHalves + live.sorted().flatMap { [HalfEdge(edge: $0, reversed: false), HalfEdge(edge: $0, reversed: true)] })
            var cycleOf: [HalfEdge: Int] = [:]
            for (k, cycle) in cycles.enumerated() { for h in cycle { cycleOf[h] = k } }
            let loose = live.filter { cycleOf[HalfEdge(edge: $0, reversed: false)] == cycleOf[HalfEdge(edge: $0, reversed: true)] }
            if !loose.isEmpty {
                live.subtract(loose)
                pruned.append(contentsOf: loose.sorted())
                continue
            }

            // Faces (counter-clockwise cycles) and the holes in them.
            struct Cycle { var halves: [HalfEdge]; var polygon: [LatticePoint]; var area2: Int64 }
            var faces: [Cycle] = [], holes: [Cycle] = []
            func sort(_ halves: [HalfEdge]) throws {
                let polygon = self.polygon(halves)
                let area2 = Lattice.area2(polygon)
                guard area2 != 0 else { throw EditFailure.collision("an outline encloses nothing") }
                if area2 > 0 { faces.append(Cycle(halves: halves, polygon: polygon, area2: area2)) }
                else { holes.append(Cycle(halves: halves, polygon: polygon, area2: area2)) }
            }
            for cycle in cycles { try sort(cycle) }
            for (k, ring) in original.enumerated() where !seeded.contains(k) { try sort(halves(ring)) }

            var held = [[Cycle]](repeating: [], count: faces.count)
            for hole in holes {
                var home: Int?
                for (f, face) in faces.enumerated() where home == nil || face.area2 < faces[home!].area2 {
                    // A hole that is a face's own far side has every vertex on its outline.
                    for p in hole.polygon {
                        let place = Lattice.contains([face.polygon], p)
                        if place == .boundary { continue }
                        if place == .inside { home = f }
                        break
                    }
                }
                guard let home else { throw EditFailure.collision("a hole belongs to no area") }
                held[home].append(hole)
            }
            pieces = faces.indices.map { f in
                Piece(
                    outer: faces[f].halves, holes: held[f].map(\.halves), rings: [faces[f].polygon] + held[f].map(\.polygon),
                    area2: faces[f].area2 + held[f].reduce(0) { $0 + $1.area2 }, plan: nil)
            }
            let freshLines = splitting ? [] : pruned.filter { fresh.contains($0) }.map { lattice(of: $0).map(Lattice.position) }
            for i in pieces.indices {
                pieces[i].plan = labelPlan(
                    rings: pieces[i].rings, color: color, detail: wasDetail, hints: hints, region: r, keepOut: freshLines)
            }
            let failing = pieces.filter { $0.plan == nil }
            if failing.isEmpty { break }
            var removed = false
            for piece in failing {
                for h in piece.outer + piece.holes.flatMap({ $0 }) where live.remove(h.edge) != nil {
                    pruned.append(h.edge)
                    removed = true
                }
            }
            guard removed else { throw EditFailure.invalid("an area the lines left has no room for its number") }
            for piece in failing { summary.declined.append(Self.centre(of: piece.rings[0])) }
        }

        if live.isEmpty {
            let outline = [(id: r, rings: original.map { polygon($0) })]
            for e in pruned.sorted() { release(e, among: outline) }
            return
        }

        func corner(_ piece: Piece) -> LatticePoint { piece.rings[0].min { Lattice.lexicographicallyBefore($0, $1) }! }
        pieces.sort { a, b in
            a.area2 != b.area2 ? a.area2 > b.area2 : Lattice.lexicographicallyBefore(corner(a), corner(b))
        }
        let strokesHere = strokes.indices.filter { strokes[$0].alive && strokes[$0].region == r }
        var ids = [r]
        for piece in pieces.dropFirst() {
            ids.append(addRegion(color: color, detail: wasDetail || piece.plan!.needsDetail))
        }
        regionDetail[r] = wasDetail || pieces[0].plan!.needsDetail
        for (k, piece) in pieces.enumerated() {
            let id = ids[k]
            let cycles = [piece.outer] + piece.holes
            setRings(id, cycles.enumerated().map { i, cycle in
                WorkRing(refs: cycle.map { EdgeRef(edge: UInt32($0.edge), reversed: $0.reversed) }, isHole: i > 0)
            })
            for cycle in cycles {
                for h in cycle {
                    if h.reversed {
                        if t.edges[h.edge].right != UInt32(id) { t.edges[h.edge].right = UInt32(id); edgeDirty[h.edge] = true }
                    } else if t.edges[h.edge].left != UInt32(id) {
                        t.edges[h.edge].left = UInt32(id)
                        edgeDirty[h.edge] = true
                    }
                }
            }
            labels[id] = piece.plan!.labels.map { Label(position: $0.position, radius: $0.radius, region: UInt32(id)) }
            remesh.insert(id)
            regionTouched[id] = true
        }
        let shapes = pieces.indices.map { (id: ids[$0], rings: pieces[$0].rings) }
        distribute(
            region: r, among: pieces.indices.map { (id: ids[$0], rings: pieces[$0].rings, pole: pieces[$0].plan!.labels[0].position) })
        for e in pruned.sorted() { release(e, among: shapes) }
        reassign(strokes: strokesHere, among: shapes, cutters: live.sorted())
        summary.regionsSplit += pieces.count - 1
        summary.detailAreas += pieces.indices.filter { pieces[$0].plan!.needsDetail }.count
        summary.touched.formUnion(ids)
        summary.pieces.formUnion(ids)
    }

    /// Turns a chain edge that bounds nothing back into a stroke of the area it lies in.
    mutating func release(_ e: Int, among areas: [(id: Int, rings: [[LatticePoint]])]) {
        let points = lattice(of: e)
        let layer = layers[e], weight = weights[e]
        kill(e)
        // A split's stretch that closes nothing was never ink: it goes.
        if splitting && layer == LineLayer.color.rawValue { return }
        addStroke(points, layer: layer, weight: weight, region: areaContaining(points, among: areas))
    }

    /// The mean of a ring's vertices, canvas units: where a declined area is.
    static func centre(of ring: [LatticePoint]) -> SIMD2<Float> {
        var sum = SIMD2<Double>(repeating: 0)
        for p in ring { sum += Lattice.double(p) }
        return SIMD2<Float>(sum / Double(max(ring.count, 1)))
    }

    /// The area of `areas` a polyline lies in, judged by the midpoints of its steps (the first
    /// that is not on an outline); the first area if none decides.
    func areaContaining(_ points: [LatticePoint], among areas: [(id: Int, rings: [[LatticePoint]])]) -> Int {
        if areas.count == 1 { return areas[0].id }
        let doubled = areas.map { $0.rings.map { ring in ring.map { $0 &* 2 } } }
        for (a, b) in zip(points, points.dropFirst()) {
            for (k, rings) in doubled.enumerated() where Lattice.contains(rings, a &+ b) == .inside { return areas[k].id }
        }
        return areas[0].id
    }

    /// Gives the strokes `indices` (of the region just cut) to the area they lie in, cutting a
    /// stroke that crosses the new boundary `cutters` where it does.
    mutating func reassign(strokes indices: [Int], among areas: [(id: Int, rings: [[LatticePoint]])], cutters: [Int]) {
        let boundaries = cutters.map { lattice(of: $0) }
        for i in indices {
            let points = strokes[i].points.map(Lattice.point)
            var inserts: [(segment: Int, point: LatticePoint)] = []
            for k in 0..<(points.count - 1) {
                for boundary in boundaries {
                    for j in 0..<(boundary.count - 1) {
                        if case .cross(let p) = Lattice.contact(points[k], points[k + 1], boundary[j], boundary[j + 1]) {
                            inserts.append((k, p))
                        }
                    }
                }
            }
            let cut = inserts.isEmpty ? (parts: [], grown: false) : Self.cut(points, at: inserts)
            if cut.parts.isEmpty {
                let home = areaContaining(points, among: areas)
                if home != strokes[i].region { movedStrokes.insert(i) }
                strokes[i].region = home
                continue
            }
            let stroke = strokes[i]
            strokes[i].alive = false
            for part in cut.parts {
                guard Set(part).count >= 2 else { continue }
                strokes.append(WorkStroke(
                    points: part.map(Lattice.position), layer: stroke.layer, weight: stroke.weight,
                    region: areaContaining(part, among: areas), writing: stroke.writing))
            }
        }
    }
}
