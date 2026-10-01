import Foundation

/// Counts the rings a smooth gradient was posterized into: a quality metric of the
/// pipeline's output (`pbn generate` reports it as `bandRings`), not a pipeline stage.
///
/// A ring's boundary has the tell `BandMerging` uses: the photo barely changes across it,
/// since the paints only changed because the ramp crossed the midpoint between them, while
/// a real contour carries most of the paint difference within a pixel or two. A region
/// whose borders are mostly that weak is one band of a posterized ramp (a bokeh highlight's
/// nested rings, a sky cut into stripes); a region with real outlines is a shape.
public enum BandRings {

    /// Regions whose boundary is weak (mean image step below `contrast` × the paint
    /// difference) over at least `fraction` of their perimeter: the rings a ramp posterizes
    /// into.
    ///
    /// The perimeter is a region's border with other regions (the frame carries no step);
    /// steps are measured between the 4-neighbour pixels of `working` across each border,
    /// paint differences between the paints' OKLab, both in true OKLab.
    /// - Parameters:
    ///   - segmentation: Final regions and paints.
    ///   - working: The image the segmentation was made from, at its size (the pipeline's
    ///     working image).
    /// - Returns: The number of such regions; 0 when `working` does not match the
    ///   segmentation's size or the segmentation is malformed.
    public static func count(
        _ segmentation: Segmentation, working: RGBAImage, contrast: Float = 0.25, fraction: Float = 0.7
    ) -> Int {
        let w = segmentation.width, h = segmentation.height
        guard w > 0, h > 0, working.width == w, working.height == h, segmentation.regionCount > 1,
              let lab = try? WorkingImage.okLab(working, chromaScale: 1, cancel: .none) else { return 0 }
        // Region ids as classes: the runs' regions are the segmentation's (4-connected)
        // regions, and `classOf` maps them back.
        let runs = RegionRuns(classes: segmentation.labels.storage, width: w, height: h)
        let paints = segmentation.palette.map(\.oklab)
        guard runs.classOf.allSatisfy({ Int($0) < segmentation.regionCount }),
              segmentation.regionColor.allSatisfy({ Int($0) < paints.count }) else { return 0 }
        let paintOf = runs.classOf.map { segmentation.regionColor[Int($0)] }
        var adjacency = RegionAdjacency(runs)
        let steps = adjacency.boundarySteps(runs, colors: lab.storage)

        var weak = [Int](repeating: 0, count: runs.count)
        var perimeter = [Int](repeating: 0, count: runs.count)
        for k in adjacency.pairs.indices {
            let a = Int(adjacency.pairs[k] >> 32), b = Int(adjacency.pairs[k] & 0xFFFF_FFFF)
            let length = Int(adjacency.lengths[k])
            perimeter[a] += length
            perimeter[b] += length
            let difference = ColorScience.distance(paints[Int(paintOf[a])], paints[Int(paintOf[b])])
            if steps[k] < contrast * difference * Float(length) {
                weak[a] += length
                weak[b] += length
            }
        }
        var rings = 0
        for r in 0..<runs.count where perimeter[r] > 0 && Float(weak[r]) >= fraction * Float(perimeter[r]) {
            rings += 1
        }
        return rings
    }
}
