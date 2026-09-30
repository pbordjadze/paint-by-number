import Foundation
import Observation
import PaintCore
import simd

/// Something that visualizes a painting session (the Metal canvas). The session tells it
/// what changed; the canvas owns animation and camera.
protocol PaintingCanvas: AnyObject {
    /// Regions became painted. `origin` is where the paint should spread from (canvas units).
    func session(_ session: PaintingSession, didPaint regions: [Int], from origin: SIMD2<Float>, animated: Bool)
    /// A region was un-painted (undo / reset).
    func session(_ session: PaintingSession, didUnpaint regions: [Int])
    /// The selected color changed (highlighting of matching regions must update).
    func sessionDidChangeSelection(_ session: PaintingSession)
    /// The user asked to be shown where to paint next.
    func session(_ session: PaintingSession, focusOn region: Int)
}

enum PaintEvent: Equatable {
    case painted(regions: [Int], color: Int)
    /// Tapped a region that needs another color.
    case rejected(region: Int, expectedColor: Int)
    case colorCompleted(Int)
    case artworkCompleted
    case undone(region: Int)
    /// A drag or Pencil stroke ended; `regions` are all it painted (it undoes as one step).
    case strokeEnded(regions: [Int])
    /// A tap painted nothing but landed just beside an unpainted area of the selected color
    /// that is small at this zoom: zooming in would help.
    case missedSmallArea(region: Int)
    /// The hint revealed `region`.
    case hintShown(region: Int)
}

/// The live state of painting one artwork: template, progress, selection and the rules of
/// what may be painted where. UI observes it; the canvas is driven through `PaintingCanvas`.
@Observable
final class PaintingSession {
    let template: Template
    private(set) var progress: PaintProgress
    /// Palette index currently loaded on the brush.
    private(set) var selectedColor: Int?
    /// Regions left to paint per palette color.
    private(set) var remainingByColor: [Int]
    let totalByColor: [Int]
    /// Names of the palette colors, index-aligned with `template.palette`.
    let colorNames: [ColorName]
    /// Increments on every progress change; cheap to observe for autosave/thumbnails.
    private(set) var revision = 0

    @ObservationIgnored weak var canvas: PaintingCanvas?
    @ObservationIgnored private var observers: [(PaintEvent) -> Void] = []
    @ObservationIgnored private var lastInteraction: ContinuousClock.Instant?
    @ObservationIgnored private let clock = ContinuousClock()
    /// Automatically select the next unfinished color when one is completed.
    @ObservationIgnored var autoAdvance = true
    /// Fills of the stroke in progress (nil between strokes).
    @ObservationIgnored private var strokeFills: [Int]?

    /// Saved progress that belongs to a different template (e.g. a stale or damaged file).
    nonisolated struct ProgressMismatch: Error, Equatable {
        let templateRegions: Int
        let progressRegions: Int
    }

    /// A fresh painting of `template`.
    convenience init(template: Template) {
        self.init(checked: template, progress: PaintProgress(regionCount: template.regions.count))
    }

    /// Resumes saved progress; throws instead of trapping when it does not fit the template.
    convenience init(template: Template, progress: PaintProgress) throws {
        guard progress.regionCount == template.regions.count else {
            throw ProgressMismatch(templateRegions: template.regions.count, progressRegions: progress.regionCount)
        }
        self.init(checked: template, progress: progress)
    }

    private init(checked template: Template, progress: PaintProgress) {
        self.template = template
        self.progress = progress
        let totals = template.regionCountsByColor
        totalByColor = totals
        colorNames = template.palette.map(\.colorName)
        var remaining = totals
        for (i, region) in template.regions.enumerated() where progress.isPainted(i) {
            remaining[Int(region.colorIndex)] -= 1
        }
        remainingByColor = remaining
        selectedColor = remaining.firstIndex { $0 > 0 }
    }

    // MARK: Queries

    var paletteCount: Int { template.palette.count }
    var fractionComplete: Double {
        progress.regionCount == 0 ? 0 : Double(progress.paintedCount) / Double(progress.regionCount)
    }
    var isComplete: Bool { progress.isComplete }

    func isPainted(_ region: Int) -> Bool { progress.isPainted(region) }
    func isColorComplete(_ color: Int) -> Bool { remainingByColor[color] == 0 }
    func colorOf(_ region: Int) -> Int { Int(template.regions[region].colorIndex) }

    func onEvent(_ observer: @escaping (PaintEvent) -> Void) { observers.append(observer) }

    // MARK: Selection

    func select(color: Int?) {
        guard color != selectedColor else { return }
        if let color, !(0..<paletteCount).contains(color) { return }
        selectedColor = color
        canvas?.sessionDidChangeSelection(self)
    }

    // MARK: Painting

    /// Handles a tap at a canvas-space point. `tolerance` (canvas units) lets a slightly
    /// imprecise tap still hit a small region of the selected color nearby.
    @discardableResult
    func tap(at point: SIMD2<Float>, tolerance: Float) -> PaintEvent? {
        guard let color = selectedColor, let hit = template.region(at: point) else { return nil }
        let target: Int?
        if !progress.isPainted(hit) && colorOf(hit) == color {
            target = hit
        } else {
            target = nearestPaintable(to: point, color: color, radius: tolerance)
        }
        guard let target else {
            let rejected: PaintEvent? = !progress.isPainted(hit) && colorOf(hit) != color
                ? .rejected(region: hit, expectedColor: colorOf(hit)) : nil
            if let rejected { emit(rejected) }
            // "Small" = its inscribed disc fits under the tolerance (a fingertip on screen).
            if tolerance > 0, let small = nearestPaintable(
                to: point, color: color, radius: tolerance * Self.nearMissReach, maxInscribedRadius: tolerance) {
                emit(.missedSmallArea(region: small))
            }
            return rejected
        }
        return paint([target], from: point, animated: true)
    }

    /// How far beyond the tap tolerance (as a multiple of it) a miss still counts as aimed
    /// at a small area.
    private static let nearMissReach: Float = 3

    /// Largest brush radius a drag paints with, in canvas units. The canvas never zooms out
    /// past "fit", so the finger's 11 pt covers at most about 78 units (the largest working
    /// canvas on the smallest iPhone) and about 24 on an iPad: the cap never bites on current
    /// devices, so drags paint the same at every zoom. It bounds the work should canvases or
    /// brushes grow; the capsule scan keeps the cost proportional to the area swept.
    static let maxBrushRadius: Float = 96

    /// Paints every region of the selected color that a brush of `radius` touches moving
    /// from `a` to `b`, in the order it reaches them (replays follow the stroke).
    @discardableResult
    func drag(from a: SIMD2<Float>, to b: SIMD2<Float>, radius: Float) -> PaintEvent? {
        guard let color = selectedColor else { return nil }
        let progress = self.progress
        let eligible = template.regions.indices.map { !progress.isPainted($0) && colorOf($0) == color }
        // Stroke parameter of the first contact per region; infinity = not touched.
        var enter = [Float](repeating: .infinity, count: eligible.count)
        var touched: [Int] = []
        forEachRegion(inCapsuleFrom: a, to: b, radius: min(max(0, radius), Self.maxBrushRadius), among: eligible) { region, t in
            guard t < enter[region] else { return }
            if enter[region] == .infinity { touched.append(region) }
            enter[region] = t
        }
        guard !touched.isEmpty else { return nil }
        let found = touched.sorted { (enter[$0], $0) < (enter[$1], $1) }
        return paint(found, from: b, animated: true)
    }

    /// Brackets a drag or Pencil stroke so everything it paints undoes together.
    func beginStroke() { strokeFills = [] }

    func endStroke() {
        guard let fills = strokeFills else { return }
        strokeFills = nil
        if !fills.isEmpty { emit(.strokeEnded(regions: fills)) }
    }

    var isStroking: Bool { strokeFills != nil }

    /// Paints regions (programmatic entry point; also used by demos and tests).
    @discardableResult
    func paint(_ regions: [Int], from origin: SIMD2<Float>, animated: Bool) -> PaintEvent? {
        noteInteraction()
        var newly: [Int] = []
        for r in regions where progress.paint(r) {
            newly.append(r)
            remainingByColor[colorOf(r)] -= 1
        }
        guard !newly.isEmpty else { return nil }
        strokeFills?.append(contentsOf: newly)
        revision += 1
        canvas?.session(self, didPaint: newly, from: origin, animated: animated)
        let color = colorOf(newly[0])
        let event = PaintEvent.painted(regions: newly, color: color)
        emit(event)
        let completedColors = Set(newly.map(colorOf)).filter { remainingByColor[$0] == 0 }
        for c in completedColors.sorted() { emit(.colorCompleted(c)) }
        if progress.isComplete {
            emit(.artworkCompleted)
        } else if autoAdvance, let selected = selectedColor, completedColors.contains(selected) {
            select(color: nextIncompleteColor(after: selected))
        }
        return event
    }

    /// Unpaints the most recent fill; returns its region.
    @discardableResult
    func undo() -> Int? {
        guard let region = progress.undo() else { return nil }
        remainingByColor[colorOf(region)] += 1
        revision += 1
        canvas?.session(self, didUnpaint: [region])
        emit(.undone(region: region))
        return region
    }

    func reset() {
        let painted = (0..<progress.regionCount).filter(progress.isPainted)
        progress.reset()
        remainingByColor = totalByColor
        revision += 1
        canvas?.session(self, didUnpaint: painted)
        select(color: remainingByColor.firstIndex { $0 > 0 })
    }

    /// Asks the canvas to reveal the unpainted region of the selected color nearest to
    /// `point` (or the largest one when no point is given).
    func showHint(near point: SIMD2<Float>? = nil) {
        guard let color = selectedColor else { return }
        var best: Int?
        var bestScore = Float.infinity
        for (i, r) in template.regions.enumerated() where Int(r.colorIndex) == color && !progress.isPainted(i) {
            let score: Float
            if let point, let label = template.labels(ofRegion: i).first {
                score = simd_distance_squared(label.position, point)
            } else {
                score = -r.area
            }
            if score < bestScore { bestScore = score; best = i }
        }
        if let best {
            canvas?.session(self, focusOn: best)
            emit(.hintShown(region: best))
        }
    }

    func nextIncompleteColor(after color: Int) -> Int? {
        let n = paletteCount
        for k in 1...n {
            let c = (color + k) % n
            if remainingByColor[c] > 0 { return c }
        }
        return nil
    }

    // MARK: Internals

    private func emit(_ event: PaintEvent) {
        for o in observers { o(event) }
    }

    private func noteInteraction() {
        let now = clock.now
        if let last = lastInteraction {
            let gap = now - last
            // Count time between strokes as painting time unless the user wandered off.
            if gap < .seconds(45) {
                progress.activeSeconds += Double(gap.components.seconds) + Double(gap.components.attoseconds) * 1e-18
            }
        }
        lastInteraction = now
    }

    private func nearestPaintable(
        to point: SIMD2<Float>, color: Int, radius: Float, maxInscribedRadius: Float = .infinity
    ) -> Int? {
        var best: Int?
        var bestD = Float.infinity
        forEachRegion(inDiscAt: point, radius: radius) { region, d2 in
            if d2 < bestD && !progress.isPainted(region) && colorOf(region) == color
                && template.regions[region].inscribedRadius <= maxInscribedRadius {
                bestD = d2
                best = region
            }
        }
        return best
    }

    /// Visits the pixels of `among` regions within `r` of the segment a→b (the area a brush
    /// of radius `r` sweeps; pixel centres on the canvas grid), with the stroke parameter
    /// 0…1 at which the moving brush first covers each. This is the continuous limit of
    /// stamping the disc every canvas unit, at a cost proportional to the swept area.
    private func forEachRegion(
        inCapsuleFrom a: SIMD2<Float>, to b: SIMD2<Float>, radius r: Float, among eligible: [Bool],
        _ body: (_ region: Int, _ enter: Float) -> Void
    ) {
        let map = template.regionMap
        guard map.width > 0, map.height > 0 else { return }
        let d = b - a
        let len2 = simd_length_squared(d), len = len2.squareRoot()
        let r2 = r * r
        // The bounds below are padded by a pixel so rounding never drops an edge pixel; the
        // exact distance test decides.
        let pad: Float = 1
        let y0 = max(0, Int((min(a.y, b.y) - r - pad).rounded(.down)))
        let y1 = min(map.height - 1, Int((max(a.y, b.y) + r + pad).rounded(.up)))
        guard y0 <= y1 else { return }
        map.storage.withUnsafeBufferPointer { regions in
            eligible.withUnsafeBufferPointer { eligible in
                for y in y0...y1 {
                    let cy = Float(y) + 0.5
                    // Only the part of the segment within r (vertically) of this row can
                    // bring its pixels within r.
                    var t0: Float = 0, t1: Float = 1
                    if d.y != 0 {
                        let u = (cy - r - pad - a.y) / d.y, v = (cy + r + pad - a.y) / d.y
                        t0 = max(0, min(u, v))
                        t1 = min(1, max(u, v))
                        if t0 > t1 { continue }
                    } else if abs(cy - a.y) > r + pad {
                        continue
                    }
                    let xa = a.x + d.x * t0, xb = a.x + d.x * t1
                    let x0 = max(0, Int((min(xa, xb) - r - pad).rounded(.down)))
                    let x1 = min(map.width - 1, Int((max(xa, xb) + r + pad).rounded(.up)))
                    guard x0 <= x1 else { continue }
                    let row = y * map.width
                    for x in x0...x1 {
                        let region = Int(regions[row + x])
                        guard eligible[region] else { continue }
                        let p = SIMD2(Float(x) + 0.5, cy) - a
                        let along = len2 > 0 ? simd_dot(p, d) / len2 : 0
                        guard simd_length_squared(p - d * min(max(along, 0), 1)) <= r2 else { continue }
                        var enter: Float = 0
                        if len > 0 {
                            let perp2 = max(0, simd_length_squared(p) - along * along * len2)
                            enter = min(max(along - max(0, r2 - perp2).squareRoot() / len, 0), 1)
                        }
                        body(region, enter)
                    }
                }
            }
        }
    }

    /// Visits region indices under a disc (sampled on the canvas grid) with squared distance.
    private func forEachRegion(inDiscAt p: SIMD2<Float>, radius: Float, _ body: (Int, Float) -> Void) {
        let map = template.regionMap
        let r = max(0, radius)
        let x0 = max(0, Int((p.x - r).rounded(.down))), x1 = min(map.width - 1, Int((p.x + r).rounded(.up)))
        let y0 = max(0, Int((p.y - r).rounded(.down))), y1 = min(map.height - 1, Int((p.y + r).rounded(.up)))
        guard x0 <= x1, y0 <= y1 else { return }
        let r2 = r * r
        map.storage.withUnsafeBufferPointer { buf in
            for y in y0...y1 {
                let dy = Float(y) + 0.5 - p.y
                for x in x0...x1 {
                    let dx = Float(x) + 0.5 - p.x
                    let d2 = dx * dx + dy * dy
                    if d2 <= r2 { body(Int(buf[y * map.width + x]), d2) }
                }
            }
        }
    }
}
