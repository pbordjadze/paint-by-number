import Foundation

/// Counts the rings a smooth ramp was posterized into: regions whose boundary is weak (the
/// mean image step across it is below `contrast` × the difference of the two paints) over at
/// least `fraction` of their perimeter. A real contour carries most of the paint difference
/// within a pixel or two; the border between two bands of a ramp barely changes colour (see
/// `BandMerging`). The image border does not count toward the perimeter.
public enum BandRings {
    public static func count(_ segmentation: Segmentation, working: RGBAImage, contrast: Float = 0.25, fraction: Float = 0.7) -> Int {
        let w = segmentation.width, h = segmentation.height
        guard w > 0, h > 0, segmentation.regionCount > 1, working.width == w, working.height == h else { return 0 }
        let lab = ColorScience.okLabImage(from: working)
        let runs = RegionRuns(classes: segmentation.labels.storage, width: w, height: h)
        var adjacency = RegionAdjacency(runs)
        let steps = adjacency.boundarySteps(runs, colors: lab.storage)
        // Runs number regions in raster order; `classOf` holds the segmentation's region.
        let paint = runs.classOf.map { segmentation.palette[Int(segmentation.regionColor[Int($0)])].oklab }
        var weak = [Int](repeating: 0, count: runs.count)
        var perimeter = [Int](repeating: 0, count: runs.count)
        for k in adjacency.pairs.indices {
            let a = Int(adjacency.pairs[k] >> 32), b = Int(adjacency.pairs[k] & 0xFFFF_FFFF)
            let length = Int(adjacency.lengths[k])
            perimeter[a] += length
            perimeter[b] += length
            let difference = ColorScience.distance(paint[a], paint[b])
            if steps[k] < contrast * difference * Float(length) {
                weak[a] += length
                weak[b] += length
            }
        }
        var rings = 0
        for r in 0..<runs.count where perimeter[r] > 0 && Float(weak[r]) >= fraction * Float(perimeter[r]) { rings += 1 }
        return rings
    }
}
