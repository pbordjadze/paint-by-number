#if UNRELEASED
import Foundation
import PaintCore

/// The areas the widget's Paint One Area paints, in order (painting-company row 348): the
/// largest left, decided ahead so the widget can show each picture without the painting.
nonisolated enum OutsideFills {
    /// How many areas the shelf holds pictures for. Past them the widget asks the painter in:
    /// a dozen taps between visits, each picture a few hundred kilobytes.
    static let most = 12

    /// Up to `limit` unpainted areas of `template`, each the next to paint after those before
    /// it: the largest area left, of whichever paint. Not Zen Mode's order (the paint in hand,
    /// its nearest area): in a widget's small picture a tap has to paint something that shows
    /// (painting-company row 348's critic, two rounds: nearby slivers, then the paint in hand's
    /// largest areas, which halfway through a painting are specks too, changed nothing to see).
    /// Never the painting's last area: finishing is the app's moment.
    static func plan(template: Template, progress: PaintProgress, limit: Int = most) -> [Int] {
        guard progress.regionCount == template.regions.count else { return [] }
        let left = progress.painted.indices.filter { !progress.painted[$0] }
        let count = min(limit, left.count - 1)
        guard count > 0 else { return [] }
        // Largest first; a tie goes to the lower index, so a plan is the same on every device.
        let byArea = left.sorted {
            let a = template.regions[$0].area, b = template.regions[$1].area
            return a != b ? a > b : $0 < $1
        }
        return Array(byArea.prefix(count))
    }
}
#endif
