#if UNRELEASED
import Foundation
import PaintCore

/// The areas the widget's Paint One Area paints, in order (painting-company row 348): the
/// paint in hand's largest areas, decided ahead so the widget can show each picture without
/// the painting.
nonisolated enum OutsideFills {
    /// How many areas the shelf holds pictures for. Past them the widget asks the painter in:
    /// a dozen taps between visits, each picture a few hundred kilobytes.
    static let most = 12

    /// Up to `limit` unpainted areas of `template`, each the next to paint after those before
    /// it: the paint in hand first (`PaintProgress.inHand`, else the first paint with areas
    /// left), its largest area left, and the next paint along the palette once one is finished.
    /// The largest, not the nearest as Zen Mode goes: in a widget's small picture a tap has to
    /// paint something that shows (painting-company row 348's critic: four taps of nearby
    /// slivers changed nothing to see). Never the painting's last area:
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
        var plan: [Int] = []
        while plan.count < count {
            var best: Int?
            var bestScore = Float.infinity
            for (i, region) in template.regions.enumerated() where Int(region.colorIndex) == color && !painted[i] {
                let score = -region.area
                if score < bestScore {
                    bestScore = score
                    best = i
                }
            }
            guard let best else { break }
            plan.append(best)
            painted[best] = true
            remaining[color] -= 1
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
