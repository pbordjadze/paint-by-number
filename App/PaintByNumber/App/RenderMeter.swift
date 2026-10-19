#if DEBUG
import Foundation
import os

/// Diagnostic (claude/start-handoff-hang): counts a view's body evaluations and, when one renders
/// more than 30 times in a second, logs how many and the different states it rendered with, so a
/// render loop names what keeps changing. Debug only; it comes out with the fix.
enum RenderMeter {
    private struct Window {
        var start: ContinuousClock.Instant
        var count = 0
        var states: [String] = []
    }

    private static var windows: [String: Window] = [:]
    private static let clock = ContinuousClock()

    static func tick(_ name: String, _ state: @autoclosure () -> String) {
        let now = clock.now
        var window = windows[name] ?? Window(start: now)
        window.count += 1
        if window.states.count < 6 {
            let state = state()
            if !window.states.contains(state) { window.states.append(state) }
        }
        if now - window.start >= .seconds(1) {
            if window.count > 30 {
                let report = "\(name) rendered \(window.count) times in \(now - window.start): \(window.states.joined(separator: " | "))"
                Log.demo.notice("RenderMeter \(report, privacy: .public)")
            }
            window = Window(start: now)
        }
        windows[name] = window
    }
}
#endif
