import Foundation

/// Segmentation → vector template (shared smoothed boundaries, fill mesh, labels).
///
/// PLACEHOLDER implementation: computes region statistics and label positions from the
/// raster only; geometry arrays are left empty. The production vectorizer replaces it.
public enum Vectorizer {
    public static func vectorize(
        _ segmentation: Segmentation,
        settings: GenerationSettings,
        cancel: CancellationCheck,
        clock: StageClock
    ) throws -> Template {
        let w = segmentation.width, h = segmentation.height
        let labelsMap = segmentation.labels
        let count = segmentation.regionCount
        let dist = clock.measure("vectorize.edt") { DistanceTransform.interiorDistance(labels: labelsMap) }

        var area = [Float](repeating: 0, count: count)
        var bounds = [PixelBounds](repeating: .empty, count: count)
        var best = [Float](repeating: -1, count: count)
        var bestPos = [SIMD2<Float>](repeating: .zero, count: count)
        for y in 0..<h {
            for x in 0..<w {
                let i = y * w + x
                let r = Int(labelsMap.storage[i])
                area[r] += 1
                bounds[r].include(x: x, y: y)
                if dist.storage[i] > best[r] {
                    best[r] = dist.storage[i]
                    bestPos[r] = SIMD2(Float(x) + 0.5, Float(y) + 0.5)
                }
            }
        }
        var regions: [Region] = []
        var labels: [Label] = []
        for r in 0..<count {
            regions.append(Region(
                colorIndex: segmentation.regionColor[r], area: area[r], bounds: bounds[r],
                inscribedRadius: best[r], labelStart: UInt32(labels.count), labelCount: 1))
            labels.append(Label(position: bestPos[r], radius: best[r], region: UInt32(r)))
        }
        return Template(
            width: w, height: h, colorSpace: segmentation.colorSpace,
            palette: segmentation.palette, regions: regions,
            points: [], edges: [], ringEdges: [], rings: [],
            labels: labels, mesh: FillMesh(), regionMap: labelsMap)
    }
}
