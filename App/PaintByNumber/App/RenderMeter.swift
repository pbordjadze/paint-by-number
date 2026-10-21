#if DEBUG
import Foundation
import os

/// Diagnostic (claude/handoff-stall-probe, never merged): counts body evaluations per name and,
/// when one renders more than 20 times in a second, logs how many and the states it rendered
/// with, so a render loop names what keeps changing.
@MainActor
enum RenderMeter {
    private struct Window {
        var start: ContinuousClock.Instant
        var count = 0
        var states: [String] = []
    }

    private static var windows: [String: Window] = [:]
    private static let clock = ContinuousClock()

    static func tick(_ name: String, _ state: @autoclosure () -> String = "") {
        let now = clock.now
        var window = windows[name] ?? Window(start: now)
        window.count += 1
        if window.states.count < 6 {
            let state = state()
            if !window.states.contains(state) { window.states.append(state) }
        }
        if now - window.start >= .seconds(1) {
            if window.count > 20 {
                let report = "\(name) rendered \(window.count) times in \(now - window.start): \(window.states.joined(separator: " | "))"
                Log.demo.notice("RenderMeter \(report, privacy: .public)")
            }
            window = Window(start: now)
        }
        windows[name] = window
    }

    static let galleryTop = "gallery top"

    static func note(_ message: String) {
        Log.demo.notice("RenderMeter \(message, privacy: .public)")
    }
}
#endif
