extension Template {
    /// How big region `index` is: the radius of the largest disc its polygon holds, wherever its
    /// number sits. `Region.inscribedRadius` is that only while the primary label is at the
    /// polygon's pole; a label moved off writing or a drawn line, or by the painter, leaves
    /// there the room of its new spot, and a reader that took it for the region's size would
    /// call a wide area small (a missed tap beside it, the small-region counts).
    ///
    /// The stored value is kept unless the polygon holds a disc larger by more than the pole
    /// search's own precision (`Vectorizer.labelPrecision`): the vectorizer promises its pole no
    /// closer to the best one than that, so a smaller difference says nothing of a moved label,
    /// and a region whose label sits at its pole answers exactly what it stores. (Now and then
    /// more: the vectorizer searches a long outline only around its raster pole, and the whole
    /// polygon can hold a larger disc elsewhere, as one region of the quality gate's thirty
    /// templates does.)
    ///
    /// A reader with a threshold passes it as `limit`: a region whose stored value is over it is
    /// answered at once, and the search of another's polygon ends at the first disc over it,
    /// so a result over `limit` says only that the region is bigger than that. The search is
    /// of the whole polygon (a region of thousands of vertices takes milliseconds): keep the
    /// answer rather than ask again.
    public func inscribedRadius(ofRegion index: Int, upTo limit: Float = .infinity) -> Float {
        let region = regions[index]
        let stored = region.inscribedRadius
        let slack = Float(Vectorizer.labelPrecision)
        guard stored <= limit, region.ringCount > 0 else { return stored }
        // No larger disc fits in the region's area.
        let larger = stored + slack
        guard !(region.area < .pi * larger * larger) else { return stored }
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
        let seed = region.labelCount > 0 ? SIMD2<Double>(labels[Int(region.labelStart)].position) : (lo + hi) / 2
        let found = PolyLabel.findAnywhere(
            poly, precision: Vectorizer.labelPrecision, seed: seed, enough: Double(max(limit, larger)))
        return Float(found.distance) > larger ? Float(found.distance) : stored
    }
}
