import Foundation
import Testing
@testable import PaintByNumber

/// The feel of each haptic, as Core Haptics is handed it: every event's kind, intensity, sharpness,
/// time and length, and every curve's points (`HapticsPlayer.patterns()`). CI's simulators and iPads
/// have no haptics, so nothing else would notice a pattern that changed.
struct HapticPatternTests {
    private typealias Pattern = HapticsPlayer.Pattern

    /// The patterns `ask` makes, on a player that runs its queue as if the hardware had haptics.
    private func patterns(_ ask: (HapticsPlayer) -> Void) -> [Pattern] {
        let haptics = HapticsPlayer(isSupported: true)
        ask(haptics)
        return haptics.patterns()
    }

    private func expect(
        _ event: Pattern.Event, continuous: Bool, intensity: Float, sharpness: Float, time: TimeInterval,
        duration: TimeInterval = 0, _ comment: Comment? = nil, sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(event.isContinuous == continuous, comment, sourceLocation: sourceLocation)
        #expect(abs(event.intensity - intensity) < 1e-5, "intensity \(event.intensity)", sourceLocation: sourceLocation)
        #expect(abs(event.sharpness - sharpness) < 1e-5, "sharpness \(event.sharpness)", sourceLocation: sourceLocation)
        #expect(abs(event.time - time) < 1e-9, "time \(event.time)", sourceLocation: sourceLocation)
        if continuous {
            #expect(abs(event.duration - duration) < 1e-9, "duration \(event.duration)", sourceLocation: sourceLocation)
        }
    }

    private func expect(
        _ curve: Pattern.Curve, time: TimeInterval, points: [SIMD2<Double>], sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(abs(curve.time - time) < 1e-9, sourceLocation: sourceLocation)
        #expect(curve.points.count == points.count, sourceLocation: sourceLocation)
        for (point, expected) in zip(curve.points, points) {
            #expect(abs(point.x - expected.x) < 1e-6 && abs(point.y - expected.y) < 1e-6, "point \(point)", sourceLocation: sourceLocation)
        }
    }

    /// A fill: a soft press, then a swell as long as the fill's animation that fades as the paint
    /// spreads; a bigger area presses and swells harder.
    @Test func aFillIsAPressAndASwellThatFadesAsThePaintSpreads() throws {
        let made = patterns { $0.paint(strength: 0.5, duration: 0.4) }
        #expect(made.map(\.name) == ["paint"])
        let pattern = try #require(made.first)
        try #require(pattern.events.count == 2 && pattern.curves.count == 1)
        expect(pattern.events[0], continuous: false, intensity: 0.65, sharpness: 0.45, time: 0)
        expect(pattern.events[1], continuous: true, intensity: 0.425, sharpness: 0.12, time: 0.015, duration: 0.4)
        expect(pattern.curves[0], time: 0.015, points: [SIMD2(0, 1), SIMD2(0.14, 0.6), SIMD2(0.4, 0)])
    }

    /// Strength stays within 0…1 and the swell within 0.12…0.8 s, whatever is asked.
    @Test func aFillsStrengthAndLengthAreBounded() throws {
        let most = try #require(patterns { $0.paint(strength: 2, duration: 5) }.first)
        try #require(most.events.count == 2 && most.curves.count == 1)
        expect(most.events[0], continuous: false, intensity: 0.85, sharpness: 0.45, time: 0)
        expect(most.events[1], continuous: true, intensity: 0.6, sharpness: 0.12, time: 0.015, duration: 0.8)
        expect(most.curves[0], time: 0.015, points: [SIMD2(0, 1), SIMD2(0.28, 0.6), SIMD2(0.8, 0)])

        let least = try #require(patterns { $0.paint(strength: -1, duration: 0) }.first)
        try #require(least.events.count == 2 && least.curves.count == 1)
        expect(least.events[0], continuous: false, intensity: 0.45, sharpness: 0.45, time: 0)
        expect(least.events[1], continuous: true, intensity: 0.25, sharpness: 0.12, time: 0.015, duration: 0.12)
        expect(least.curves[0], time: 0.015, points: [SIMD2(0, 1), SIMD2(0.042, 0.6), SIMD2(0.12, 0)])
    }

    /// A stroke's fills come many a second: those within 45 ms of the last one felt are dropped, so
    /// drag painting is a texture and not a buzz.
    @Test func fillsCloseTogetherAreOneTexture() async throws {
        let haptics = HapticsPlayer(isSupported: true)
        haptics.paint(strength: 0.5, duration: 0.3)
        haptics.paint(strength: 0.5, duration: 0.3)
        #expect(haptics.played() == ["paint"])
        try await Task.sleep(for: .milliseconds(60))
        haptics.paint(strength: 0.5, duration: 0.3)
        #expect(haptics.played() == ["paint", "paint"])
    }

    /// A wrong color: two dull taps, the second softer.
    @Test func aRejectionIsTwoDullTaps() throws {
        let made = patterns { $0.reject() }
        #expect(made.map(\.name) == ["reject"])
        let pattern = try #require(made.first)
        try #require(pattern.events.count == 2)
        #expect(pattern.curves.isEmpty)
        expect(pattern.events[0], continuous: false, intensity: 0.5, sharpness: 0.15, time: 0)
        expect(pattern.events[1], continuous: false, intensity: 0.35, sharpness: 0.15, time: 0.085)
    }

    /// A finished color: three taps, each brighter and sharper, after the fill's own press.
    @Test func aFinishedColorIsABrightTriple() throws {
        let made = patterns { $0.colorComplete() }
        #expect(made.map(\.name) == ["colorComplete"])
        let pattern = try #require(made.first)
        try #require(pattern.events.count == 3)
        #expect(pattern.curves.isEmpty)
        expect(pattern.events[0], continuous: false, intensity: 0.55, sharpness: 0.6, time: 0.12)
        expect(pattern.events[1], continuous: false, intensity: 0.75, sharpness: 0.75, time: 0.195)
        expect(pattern.events[2], continuous: false, intensity: 0.95, sharpness: 0.9, time: 0.27)
    }

    /// A finished painting: a swell that rises for 0.7 s, then nine sharp sparkles dying away, each
    /// up to 30 ms late (the only chance in any pattern).
    @Test func aFinishedPaintingIsARisingShimmer() throws {
        let made = patterns { $0.celebrate() }
        #expect(made.map(\.name) == ["celebrate"])
        let pattern = try #require(made.first)
        try #require(pattern.events.count == 10 && pattern.curves.count == 1)
        expect(pattern.events[0], continuous: true, intensity: 0.6, sharpness: 0.25, time: 0, duration: 0.7)
        for i in 0..<9 {
            let event = pattern.events[i + 1]
            #expect(!event.isContinuous)
            #expect(abs(event.intensity - (0.9 - 0.08 * Float(i))) < 1e-5, "sparkle \(i): intensity \(event.intensity)")
            #expect(abs(event.sharpness - 0.85) < 1e-5)
            let earliest = 0.6 + 0.09 * Double(i)
            #expect(event.time >= earliest - 1e-9 && event.time <= earliest + 0.03 + 1e-9, "sparkle \(i) at \(event.time)")
        }
        expect(pattern.curves[0], time: 0, points: [SIMD2(0, 0.1), SIMD2(0.55, 1), SIMD2(0.7, 0)])
    }

    /// A detent (picking a color, an undo): one light, sharp tap.
    @Test func aDetentIsOneLightTap() throws {
        let made = patterns { $0.tick() }
        #expect(made.map(\.name) == ["tick"])
        let pattern = try #require(made.first)
        try #require(pattern.events.count == 1)
        #expect(pattern.curves.isEmpty)
        expect(pattern.events[0], continuous: false, intensity: 0.4, sharpness: 0.8, time: 0)
    }

    /// Hardware without haptics (an iPad) is asked for nothing.
    @Test func nothingPlaysWithoutHaptics() {
        let haptics = HapticsPlayer(isSupported: false)
        haptics.paint(strength: 1, duration: 0.4)
        haptics.reject()
        haptics.colorComplete()
        haptics.celebrate()
        haptics.tick()
        #expect(haptics.played().isEmpty)
    }
}
