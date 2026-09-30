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

    init(template: Template, progress: PaintProgress? = nil) {
        self.template = template
        let progress = progress ?? PaintProgress(regionCount: template.regions.count)
        precondition(progress.regionCount == template.regions.count, "progress does not match template")
        self.progress = progress
        let totals = template.regionCountsByColor
        totalByColor = totals
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

    /// Paints every region of the selected color touched by a drag segment.
    @discardableResult
    func drag(from a: SIMD2<Float>, to b: SIMD2<Float>, radius: Float) -> PaintEvent? {
        guard let color = selectedColor else { return nil }
        var found: [Int] = []
        var seen = Set<Int>()
        let length = simd_length(b - a)
        let steps = max(1, Int(length.rounded(.up)))
        for s in 0...steps {
            let p = a + (b - a) * (Float(s) / Float(steps))
            forEachRegion(inDiscAt: p, radius: radius) { region, _ in
                if !seen.contains(region) && !progress.isPainted(region) && colorOf(region) == color {
                    seen.insert(region)
                    found.append(region)
                }
            }
        }
        guard !found.isEmpty else { return nil }
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
