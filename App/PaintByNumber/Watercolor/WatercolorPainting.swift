#if UNRELEASED
import CoreGraphics
import Foundation
import Observation
import PaintCore
import QuartzCore
import simd
import os

/// A watercolor painting open on screen (painting-company row 373): its template, the water and
/// pigment moving over it (PaintCore's `WatercolorSim`), the tap log that is the painting's record,
/// and the paint in hand. It plays as the main painting screen does (painting-company row 373, Paul,
/// November 26: "some of the UX features the main one has"): a tap on an area of the paint in hand,
/// or near a small one, lays its wash from where the finger touched; a tap on another paint's area
/// lays nothing and shakes that paint's pan (`shake`); a laid area tapped again blooms. A finger
/// dragged lays every area of the paint in hand it crosses; Undo takes the last tap back exactly
/// (`WatercolorSim.Checkpoint`); Hint and Zen Mode find the next area (`nextArea`). Time runs in the
/// simulation's fixed steps, as many as the display's frames need (`advance`), so the painting is
/// the same whatever the frame rate.
@MainActor
@Observable
final class WatercolorPainting {
    let id: UUID
    let template: Template
    @ObservationIgnored let sim: WatercolorSim
    @ObservationIgnored private(set) var log: WatercolorLog
    /// The palette index of the paint in hand, nil once every area is painted.
    var selected: Int?
    /// Areas left per paint (palette index).
    private(set) var remaining: [Int]
    private(set) var laidCount: Int
    /// When an area was last painted (simulation seconds): its number is fading until a moment after.
    @ObservationIgnored private(set) var lastPaintedAt: Float = -1
    /// Whether the sheet has changed since the shelf's picture was last made.
    @ObservationIgnored var pictureIsStale = false
    /// Taps since the painting was last saved.
    @ObservationIgnored private(set) var unsavedTaps = 0
    /// Shows the washes only once they have settled (Reduce Motion): the same picture, with no
    /// motion. The steps run as fast as a frame's budget allows (`advance`), and the renderer
    /// holds the sheet as it was until they are done.
    @ObservationIgnored var settlesAtOnce = false
    /// Told of every tap, after it is in the log.
    @ObservationIgnored var onTap: (() -> Void)?
    /// The paint whose pan shakes, and a count that moves each time (a tap on its area while
    /// another paint was in hand).
    var shake: (color: Int, count: Int) = (0, 0)
    /// What Undo takes back: the sheet before each tap (newest last), with the log's length then.
    @ObservationIgnored private var undoStack: [(sheet: WatercolorSim.Checkpoint, taps: Int, region: Int)] = []
    /// Whether there is a tap to take back.
    private(set) var canUndo = false
    /// Told when the sheet was put back (Undo): it is drawn again whole.
    @ObservationIgnored var onRestore: (() -> Void)?
    /// Checkpoints kept: each is the whole sheet (about 48 bytes a cell, 20 MB at most), so the
    /// last few taps, not the painting's history.
    static let undoDepth = 6
    /// Seconds of simulation owed to the wall clock, less than a step.
    @ObservationIgnored private var owed: Double = 0
    /// Each step's duration, for the frame report (`takeStepTimes`).
    @ObservationIgnored private var stepTimes: [Double] = []

    var isComplete: Bool { laidCount >= template.regions.count }
    var regionCount: Int { template.regions.count }

    init(id: UUID, template: Template, sim: WatercolorSim, log: WatercolorLog) {
        self.id = id
        self.template = template
        self.sim = sim
        self.log = log
        var remaining = Array(repeating: 0, count: template.palette.count)
        for (r, region) in template.regions.enumerated() where !sim.laid[r] && Int(region.colorIndex) < remaining.count {
            remaining[Int(region.colorIndex)] += 1
        }
        self.remaining = remaining
        laidCount = sim.laidCount
        selected = Self.opening(template, remaining: remaining)
    }

    /// The paint a painting opens on: the one with the most area left to paint.
    private static func opening(_ t: Template, remaining: [Int]) -> Int? {
        var area = Array(repeating: Float(0), count: t.palette.count)
        for region in t.regions where Int(region.colorIndex) < area.count { area[Int(region.colorIndex)] += region.area }
        return remaining.indices.filter { remaining[$0] > 0 }.max { area[$0] < area[$1] }
    }

    /// A painting's seed, from its id: every painting of a template is its own.
    nonisolated static func seed(of id: UUID) -> UInt64 {
        withUnsafeBytes(of: id.uuid) { $0.loadUnaligned(as: UInt64.self) }
    }

    /// The region under `canvas` (canvas units), nil off the sheet.
    func region(at canvas: SIMD2<Float>) -> Int? { template.region(at: canvas) }

    /// What a tap did.
    enum TapResult: Equatable {
        /// The paint in hand laid on this area.
        case painted(Int)
        /// Water on an area already laid: a bloom.
        case bloomed(Int)
        /// An area of another paint, not yet laid: nothing laid, that paint's pan shaken.
        case otherPaint(Int)
    }

    /// A tap at `canvas`, `tolerance` canvas units wide (a fingertip at the zoom): the paint in
    /// hand on its area or, within the tolerance, the nearest area of it not yet laid; water on a
    /// laid area (a bloom); on another paint's area, nothing but its pan shaken. `blooms` false
    /// (a drag) lays only the paint in hand.
    @discardableResult
    func tap(at canvas: SIMD2<Float>, tolerance: Float = 0, blooms: Bool = true) -> TapResult? {
        guard let hit = region(at: canvas) else { return nil }
        var r = hit
        if !isPaintable(r), tolerance > 0, let near = nearestPaintable(to: canvas, radius: tolerance) { r = near }
        let color = Int(template.regions[r].colorIndex)
        if isPaintable(r) {
            lay(region: r, at: canvas, paint: true)
            return .painted(r)
        }
        if sim.laid[r] {
            guard blooms else { return nil }
            lay(region: r, at: canvas, paint: false)
            return .bloomed(r)
        }
        guard blooms else { return nil }
        shake = (color, shake.count + 1)
        return .otherPaint(color)
    }

    /// Whether `r` takes the paint in hand: its paint, not yet laid.
    private func isPaintable(_ r: Int) -> Bool {
        !sim.laid[r] && selected == Int(template.regions[r].colorIndex)
    }

    /// The paintable area nearest `point` within `radius` (canvas units), by the region map.
    private func nearestPaintable(to point: SIMD2<Float>, radius: Float) -> Int? {
        let map = template.regionMap
        let r = Int(radius.rounded(.up))
        let cx = Int(point.x.rounded(.down)), cy = Int(point.y.rounded(.down))
        var best: Int?
        var bestD = Float.infinity
        // Every other pixel: a fingertip's disc, so a few hundred reads.
        for y in stride(from: max(cy - r, 0), through: min(cy + r, map.height - 1), by: 2) {
            for x in stride(from: max(cx - r, 0), through: min(cx + r, map.width - 1), by: 2) {
                let dx = Float(x) + 0.5 - point.x, dy = Float(y) + 0.5 - point.y
                let d = dx * dx + dy * dy
                guard d <= radius * radius, d < bestD else { continue }
                let here = Int(map[x, y])
                if here < template.regions.count, isPaintable(here) {
                    bestD = d
                    best = here
                }
            }
        }
        return best
    }

    /// Lays `region` from `canvas`: its paint, or water. Kept for Undo first.
    private func lay(region r: Int, at canvas: SIMD2<Float>, paint: Bool) {
        let wasLaid = sim.laid[r]
        undoStack.append((sim.checkpoint(), log.taps.count, r))
        if undoStack.count > Self.undoDepth { undoStack.removeFirst() }
        canUndo = true
        log.taps.append(.init(step: sim.step, region: r, x: canvas.x, y: canvas.y, paint: paint))
        let start = CACurrentMediaTime()
        sim.tap(region: r, at: canvas, paint: paint)
        let took = CACurrentMediaTime() - start
        if took > 0.008 {
            Log.canvas.notice("watercolor tap: \(took * 1000, format: .fixed(precision: 1)) ms for an area of \(self.template.regions[r].area, format: .fixed(precision: 0))")
        }
        unsavedTaps += 1
        pictureIsStale = true
        if paint && !wasLaid {
            let color = Int(template.regions[r].colorIndex)
            remaining[color] -= 1
            laidCount = sim.laidCount
            lastPaintedAt = sim.paintedAt[r]
            if remaining[color] == 0 { selected = next(after: color) }
        }
        EraSounds.shared.watercolor(.init(paint: paint, wasLaid: wasLaid, finishes: isComplete))
        onTap?()
    }

    /// Takes the last tap back: the sheet exactly as it was before it, water still moving where
    /// it moved, and its paint in hand again.
    func undo() {
        guard let last = undoStack.popLast() else { return }
        canUndo = !undoStack.isEmpty
        sim.restore(last.sheet)
        log.taps.removeLast(max(0, log.taps.count - last.taps))
        var remaining = Array(repeating: 0, count: template.palette.count)
        for (r, region) in template.regions.enumerated() where !sim.laid[r] && Int(region.colorIndex) < remaining.count {
            remaining[Int(region.colorIndex)] += 1
        }
        self.remaining = remaining
        laidCount = sim.laidCount
        lastPaintedAt = -1
        let color = Int(template.regions[last.region].colorIndex)
        if color < remaining.count, remaining[color] > 0 { selected = color }
        unsavedTaps += 1
        pictureIsStale = true
        onRestore?()
    }

    /// The next paint with areas left after `color`, coming round.
    private func next(after color: Int) -> Int? {
        let n = remaining.count
        guard n > 0 else { return nil }
        for k in 1...n {
            let c = (color + k) % n
            if remaining[c] > 0 { return c }
        }
        return nil
    }

    /// An area of the paint in hand not yet painted, by its largest label: VoiceOver's way to
    /// paint, and where Hint and Zen Mode fly. Its number's place and the area's bounds.
    func nextArea() -> SIMD2<Float>? { nextAreaFrame()?.point }

    /// The next area to paint and its bounds (canvas units), the nearest to `near` when given (Zen
    /// Mode goes on from where the painter is), the largest otherwise.
    func nextAreaFrame(near: SIMD2<Float>? = nil) -> (point: SIMD2<Float>, bounds: CGRect)? {
        guard let selected else { return nil }
        let candidates = template.labels.filter { label in
            let r = Int(label.region)
            return r < template.regions.count && !sim.laid[r] && Int(template.regions[r].colorIndex) == selected
        }
        let pick: Label?
        if let near {
            pick = candidates.min { simd_distance_squared($0.position, near) < simd_distance_squared($1.position, near) }
        } else {
            pick = candidates.max { $0.radius < $1.radius }
        }
        guard let pick else { return nil }
        let b = template.regions[Int(pick.region)].bounds
        return (pick.position, CGRect(x: CGFloat(b.minX), y: CGFloat(b.minY),
                                      width: CGFloat(b.maxX - b.minX), height: CGFloat(b.maxY - b.minY)))
    }

    /// Whether the simulation's clock must run: water moving, or a number fading (half a second
    /// after its area is painted, even an area too small to hold any water).
    var isRunning: Bool {
        sim.isActive || (lastPaintedAt >= 0 && sim.time - lastPaintedAt < 0.5)
    }

    /// Steps the simulation for `seconds` of wall time, at most `maximumSteps` steps, and lets
    /// the rest of a late frame's time go: catching up three steps a frame made the next frame
    /// late too, and the painting stuck at 40 frames a second (an iPad Air, November 21), where
    /// water a little slower is never seen. Settling at once, it steps for as long as about two
    /// thirds of a frame instead. A step taken, a second waits for the next frame once the
    /// frame has spent `stepBudget` on them: a whole sheet wet (one opened before it dried) cost
    /// about 24 ms a frame for two steps there, and ran at 40. The number of steps taken.
    func advance(by seconds: Double, maximumSteps: Int = 2) -> Int {
        guard isRunning else {
            owed = 0
            return 0
        }
        var steps = 0
        if settlesAtOnce && sim.isActive {
            let end = CACurrentMediaTime() + 0.011
            while sim.isActive, CACurrentMediaTime() < end {
                timedStep()
                steps += 1
            }
            owed = 0
            return steps
        }
        owed += seconds
        let dt = Double(WatercolorSim.dt)
        let end = CACurrentMediaTime() + Self.stepBudget
        while owed >= dt, steps < maximumSteps, isRunning, steps == 0 || CACurrentMediaTime() < end {
            timedStep()
            owed -= dt
            steps += 1
        }
        if steps > 0, owed >= dt { owed = min(owed, dt * 0.5) }
        return steps
    }

    /// The main thread's time for stepping in one frame, past which no further step is begun:
    /// with the upload and the encode it keeps a frame inside 16 ms.
    static let stepBudget: Double = 0.008

    private func timedStep() {
        let start = CACurrentMediaTime()
        sim.advance()
        stepTimes.append(CACurrentMediaTime() - start)
    }

    func takeStepTimes() -> [Double] {
        defer { stepTimes.removeAll(keepingCapacity: true) }
        return stepTimes
    }

    /// What to save: the log, and the sheet as it stands (`WatercolorSim.snapshot`).
    func saving() -> (log: WatercolorLog, snapshot: Data, laid: Int) {
        unsavedTaps = 0
        return (log, sim.snapshot(), laidCount)
    }
}
#endif
