#if DEBUG
import Foundation
import os

/// Diagnostic (claude/start-handoff-hang): counts a view's body evaluations and, when one renders
/// more than 30 times in a second, logs how many and the different states it rendered with, so a
/// render loop names what keeps changing. Debug only; it comes out with the fix.
@MainActor
enum RenderMeter {
    private struct Window {
        var start: ContinuousClock.Instant
        var count = 0
        var states: [String] = []
    }

    private static var windows: [String: Window] = [:]
    private static let clock = ContinuousClock()
    private static var previousDescriptions: [String: [String: String]] = [:]
    private static var diffLogTimes: [String: [ContinuousClock.Instant]] = [:]

    /// Keep full descriptions for comparison; truncation only limits the logged values.
    /// MainActor serializes this state, just as it does the tick windows.
    static func diff(_ name: String, _ subject: Any) {
        var descriptions: [String: String] = [:]
        for child in Mirror(reflecting: subject).children {
            guard let label = child.label else { continue }
            descriptions[label] = String(reflecting: child.value)
        }
        let previous = previousDescriptions.updateValue(descriptions, forKey: name)
        guard let previous else { return }

        var logTimes = diffLogTimes[name] ?? []
        defer { diffLogTimes[name] = logTimes }
        for label in Set(previous.keys).union(descriptions.keys).sorted() {
            guard previous[label] != descriptions[label] else { continue }
            let now = clock.now
            logTimes.removeAll { now - $0 >= .seconds(1) }
            guard logTimes.count < 20 else { break }
            let before = String((previous[label] ?? "<absent>").prefix(300))
            let after = String((descriptions[label] ?? "<absent>").prefix(300))
            let report = "\(name).\(label): \(before) -> \(after)"
            Log.demo.notice("RenderMeter diff \(report, privacy: .public)")
            logTimes.append(now)
        }
    }

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

    static func paintViewState(
        title: Any, handoff: Any, peek: Any, seal: Any, feedback: Any,
        thanks: Any, complete: Any, started: Any, color: Any, replay: Any,
        size: Any, type: Any, unavailable: Any, photoUnavailable: Any, numbers: Any,
        zen: Any, undo: Any, scale: Any, scheme: Any, photoLoader: Any,
        source: Any, paper: Any, weight: Any, rows: Any, order: Any,
        shakes: Any, colorOrder: Any, turn: Any, motion: Any
    ) -> String {
        "title \(title) handoff \(handoff) peek \(peek) seal \(seal) feedback \(feedback) thanks \(thanks) complete \(complete) started \(started) color \(color) replay \(replay) size \(size) type \(type) unavailable \(unavailable) \(photoUnavailable) numbers \(numbers) zen \(zen) undo \(undo) scale \(scale) scheme \(scheme) photoLoader \(photoLoader) source \(source) paper \(paper) weight \(weight) rows \(rows) order \(order) shakes \(shakes) colorOrder \(colorOrder) turn \(turn) motion \(motion)"
    }

    static func paletteBarState(
        position: Any, lines: Any, axis: Any, shakes: Any, details: Any,
        color: Any, scale: Any, order: Any
    ) -> String {
        "position \(position) lines \(lines) axis \(axis) shakes \(shakes) details \(details) color \(color) scale \(scale) order \(order)"
    }

    static func artworkPaintingViewState(
        landed: Any, cover: Any, failure: Any, notice: Any, saveFailed: Any,
        regen: Any, autosaver: Any, photo: Any
    ) -> String {
        "landed \(landed) cover \(cover) failure \(failure) notice \(notice) saveFailed \(saveFailed) regen \(regen) autosaver \(autosaver) photo \(photo)"
    }
}
#endif
