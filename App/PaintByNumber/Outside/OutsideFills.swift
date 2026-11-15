#if UNRELEASED
import Foundation
import PaintCore
import simd

/// The areas the widget's Paint One Area paints, in order (painting-company row 348): what
/// Zen Mode would lead a painter through, decided ahead so the widget can show each picture
/// without the painting.
nonisolated enum OutsideFills {
    /// How many areas the shelf holds pictures for. Past them the widget asks the painter in:
    /// a dozen taps between visits, each picture a few hundred kilobytes.
    static let most = 12

    /// Up to `limit` unpainted areas of `template`, each the next to paint after those before
    /// it: the paint in hand first (`PaintProgress.inHand`, else the first paint with areas
    /// left), its area nearest the last one painted (its largest when nothing is painted), and
    /// the next paint along the palette once one is finished. Never the painting's last area:
    /// finishing is the app's moment.
    static func plan(template: Template, progress: PaintProgress, limit: Int = most) -> [Int] {
        guard progress.regionCount == template.regions.count else { return [] }
        var painted = progress.painted
        var remaining = template.regionCountsByColor
        for (i, region) in template.regions.enumerated() where painted[i] {
            remaining[Int(region.colorIndex)] -= 1
        }
        let left = remaining.reduce(0, +)
        let count = min(limit, left - 1)
        guard count > 0 else { return [] }

        var color: Int
        if let hand = progress.inHand, remaining.indices.contains(hand), remaining[hand] > 0 {
            color = hand
        } else if let first = remaining.firstIndex(where: { $0 > 0 }) {
            color = first
        } else {
            return []
        }
        var anchor = progress.log.last.flatMap { template.labels(ofRegion: Int($0.region)).first?.position }
        var plan: [Int] = []
        while plan.count < count {
            var best: Int?
            var bestScore = Float.infinity
            for (i, region) in template.regions.enumerated() where Int(region.colorIndex) == color && !painted[i] {
                let score: Float
                if let anchor, let label = template.labels(ofRegion: i).first {
                    score = simd_distance_squared(label.position, anchor)
                } else {
                    score = -region.area
                }
                if score < bestScore {
                    bestScore = score
                    best = i
                }
            }
            guard let best else { break }
            plan.append(best)
            painted[best] = true
            remaining[color] -= 1
            anchor = template.labels(ofRegion: best).first?.position ?? anchor
            if remaining[color] == 0 {
                let n = remaining.count
                guard let next = (1...n).map({ (color + $0) % n }).first(where: { remaining[$0] > 0 }) else { break }
                color = next
            }
        }
        return plan
    }
}
#endif
