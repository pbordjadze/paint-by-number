#if UNRELEASED
import CoreGraphics
import Foundation
import Observation
import PaintCore
import QuartzCore
import os

/// A watercolor painting open on screen (painting-company row 373): its template, the water and
/// pigment moving over it (PaintCore's `WatercolorSim`), the tap log that is the painting's record,
/// and the paint in hand. A tap on an area of the paint in hand lays its wash from where the finger
/// touched; a tap anywhere else is water alone, a bloom: no tap is wrong. Time runs in the
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

    /// A tap at `canvas`: the paint in hand where it is that area's paint, water elsewhere.
    @discardableResult
    func tap(at canvas: SIMD2<Float>) -> Int? {
        guard let r = region(at: canvas) else { return nil }
        let paint = selected == Int(template.regions[r].colorIndex)
        let wasLaid = sim.laid[r]
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
        return r
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

    /// An area of the paint in hand not yet painted, by its largest label: VoiceOver's way to paint.
    func nextArea() -> SIMD2<Float>? {
        guard let selected else { return nil }
        let candidates = template.labels.filter { label in
            let r = Int(label.region)
            return !sim.laid[r] && Int(template.regions[r].colorIndex) == selected
        }
        return candidates.max { $0.radius < $1.radius }?.position
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
    /// thirds of a frame instead. The number of steps taken.
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
        while owed >= dt, steps < maximumSteps, isRunning {
            timedStep()
            owed -= dt
            steps += 1
        }
        if steps == maximumSteps { owed = min(owed, dt * 0.5) }
        return steps
    }

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
