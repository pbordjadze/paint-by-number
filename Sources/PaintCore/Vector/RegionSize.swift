extension Template {
    /// How big region `index` is: the radius of the largest disc its polygon holds, wherever its
    /// number sits. `Region.inscribedRadius` is that only while the primary label is at the
    /// polygon's pole; a label moved off writing or a drawn line, or by the painter, leaves
    /// there the room of its new spot, and a reader that took it for the region's size would
    /// call a wide area small (a missed tap beside it, the small-region counts).
    ///
    /// The stored value is kept unless the polygon holds a disc larger by more than the pole
    /// search's own precision (`Vectorizer.labelPrecision`): the vectorizer promises its pole no
    /// farther from the best one than that, so a smaller difference says nothing of a moved
    /// label, and a region whose label sits at its pole answers exactly what it stores. (Now
    /// and then more: the vectorizer searches a long outline only around its raster pole, and
    /// the whole polygon can hold a larger disc elsewhere, as one region of the quality gate's
    /// thirty templates does.)
    ///
    /// A reader with a threshold passes it as `limit`: a region whose stored value is over it is
    /// answered at once, and the search of another's polygon ends at the first disc over it,
    /// so a result over `limit` says only that the region is bigger than that.
    ///
    /// The search is of the whole polygon and its work is bounded (`sizeSearchWork`): a wide
    /// region shows a larger disc within a few spots, but proving there is none in a long thin
    /// one (a strip, grout around a thousand tiles) would take a pass over every vertex for each
    /// of thousands of spots. When the bound is reached the answer is the largest disc found by
    /// then, the stored value where none was larger: such a region reads as it did before it
    /// could be measured. The bound is a count, so the answer is the same on every device.
    public func inscribedRadius(ofRegion index: Int, upTo limit: Float = .infinity) -> Float {
        measuredRadius(ofRegion: index, upTo: limit).radius
    }

    /// The outline segments a size search may measure against, over all the spots it tries: a
    /// spot costs one distance to every segment of the polygon, about 3.5 ns each in an
    /// optimized build on the Linux machine this was set on (not measured on a phone), so a
    /// search that runs out has taken about 3.5 ms there. A reader with a limit rarely gets
    /// near it, and the quality gate's metrics are the same with the bound as without.
    static let sizeSearchWork = 1_000_000
    /// The fewest spots worth a search: a polygon with too many vertices for these within
    /// `sizeSearchWork` is not searched at all.
    static let sizeSearchMinimumSpots = 8

    /// `inscribedRadius(ofRegion:upTo:)`, and whether the search ran to its end (or was not
    /// needed) rather than out of work.
    func measuredRadius(ofRegion index: Int, upTo limit: Float = .infinity) -> (radius: Float, complete: Bool) {
        let region = regions[index]
        let stored = region.inscribedRadius
        let slack = Float(Vectorizer.labelPrecision)
        guard stored <= limit, region.ringCount > 0 else { return (stored, true) }
        // No larger disc fits in the region's area.
        let larger = stored + slack
        guard !(region.area < .pi * larger * larger) else { return (stored, true) }
        var poly = FlatPolygon()
        var lo = SIMD2<Double>(repeating: .infinity), hi = SIMD2<Double>(repeating: -.infinity)
        for (k, ring) in polygons(ofRegion: index).enumerated() {
            for p in ring {
                let q = SIMD2<Double>(p)
                poly.points.append(q)
                if k == 0 { lo = pointwiseMin(lo, q); hi = pointwiseMax(hi, q) }
            }
            poly.closeRing()
        }
        let spots = Self.sizeSearchWork / max(poly.points.count, 1)
        guard spots >= Self.sizeSearchMinimumSpots else { return (stored, false) }
        let seed = region.labelCount > 0 ? SIMD2<Double>(labels[Int(region.labelStart)].position) : (lo + hi) / 2
        let found = PolyLabel.findAnywhere(
            poly, precision: Vectorizer.labelPrecision, seed: seed, enough: Double(max(limit, larger)), maxEvaluations: spots)
        var radius = Float(found.distance)
        // A disc the search saw over the limit stays over it once rounded.
        if found.distance > Double(limit) { radius = max(radius, limit.nextUp) }
        return (radius > larger ? radius : stored, found.complete)
    }
}
